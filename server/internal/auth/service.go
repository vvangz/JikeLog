// Package auth 实现注册、登录、令牌签发与刷新、短信验证码和找回密码，
// 并提供认证中间件以及供其他模块复用的身份校验能力。
package auth

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

// 认证相关错误码。
const (
	CodeInvalidCredentials = "INVALID_CREDENTIALS" //nolint:gosec // 错误码，不是凭据
	CodeAccountLocked      = "ACCOUNT_LOCKED"
	CodeUsernameTaken      = "USERNAME_TAKEN"
	CodePhoneTaken         = "PHONE_TAKEN"
	CodeRefreshInvalid     = "REFRESH_INVALID"
	CodeTicketInvalid      = "REGISTRATION_TICKET_INVALID"
	CodeCaptchaFailed      = "CAPTCHA_FAILED"
)

const (
	loginFailLimit  = 5
	loginLockWindow = 15 * time.Minute
	loginIPLimit    = 30
	loginIPWindow   = 10 * time.Minute
	// refreshGrace 内重复使用刚被轮换的 Refresh Token 视为网络重试而非泄露
	refreshGrace = 30 * time.Second
)

var (
	errInvalidCredentials = httpx.NewError(http.StatusUnauthorized, CodeInvalidCredentials, "用户名或密码错误")
	errRefreshInvalid     = httpx.NewError(http.StatusUnauthorized, CodeRefreshInvalid, "登录已失效，请重新登录")
	errTicketInvalid      = httpx.NewError(http.StatusBadRequest, CodeTicketInvalid, "注册已超时，请重新获取验证码")
	errCaptchaFailed      = httpx.NewError(http.StatusBadRequest, CodeCaptchaFailed, "人机验证未通过，请重试")
	errUsernameTaken      = httpx.NewError(http.StatusConflict, CodeUsernameTaken, "用户名已被占用")
	errPhoneTaken         = httpx.NewError(http.StatusConflict, CodePhoneTaken, "该手机号已绑定其他账号")
)

// CaptchaVerifier 校验人机验证结果。生产实现为阿里云验证码 2.0（v0.9.0）。
type CaptchaVerifier interface {
	Verify(ctx context.Context, param, ip string) (bool, error)
}

// NoopCaptcha 总是通过，仅用于开发与测试。
type NoopCaptcha struct{}

// Verify 实现 CaptchaVerifier。
func (NoopCaptcha) Verify(context.Context, string, string) (bool, error) { return true, nil }

// Deps 为 Service 的依赖。
type Deps struct {
	Tx         db.TxRunner
	Hasher     *Hasher
	Tokens     *TokenManager
	SMS        *SMSCodes
	Tickets    *RegistrationTickets
	Revoked    *Revocations
	Limiter    *ratelimit.Limiter
	Captcha    CaptchaVerifier
	RefreshTTL time.Duration
	Logger     *slog.Logger
	Now        func() time.Time
}

// Service 为认证业务逻辑。
type Service struct {
	d Deps
	// dummyHash 用于用户名不存在时也执行一次哈希校验，使响应时间无法区分用户是否存在
	dummyHash string
}

// NewService 创建 Service。
func NewService(ctx context.Context, d Deps) (*Service, error) {
	if d.Logger == nil {
		d.Logger = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if d.Now == nil {
		d.Now = time.Now
	}
	if d.Captcha == nil {
		d.Captcha = NoopCaptcha{}
	}
	dummy, err := d.Hasher.Hash(ctx, "jikelog-dummy-password-0")
	if err != nil {
		return nil, err
	}
	return &Service{d: d, dummyHash: dummy}, nil
}

// TokenPair 为签发给客户端的令牌。
type TokenPair struct {
	AccessToken      string
	AccessExpiresAt  time.Time
	RefreshToken     string
	RefreshExpiresAt time.Time
}

// Session 为登录成功后的会话。
type Session struct {
	User     dbgen.User
	DeviceID uuid.UUID
	Tokens   TokenPair
}

// NewUser 为创建账号所需的已校验字段。
type NewUser struct {
	Username string
	Password string
	Nickname string
	Phone    *string
}

// Register 创建账号并登录。
func (s *Service) Register(ctx context.Context, nu NewUser, dev DeviceMeta, ip string) (Session, error) {
	if err := s.limitLoginIP(ctx, ip); err != nil {
		return Session{}, err
	}
	return s.createAccount(ctx, nu, dev, ip)
}

func (s *Service) createAccount(ctx context.Context, nu NewUser, dev DeviceMeta, ip string) (Session, error) {
	hash, err := s.d.Hasher.Hash(ctx, nu.Password)
	if err != nil {
		return Session{}, err
	}
	var sess Session
	err = s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		user, err := q.CreateUser(ctx, dbgen.CreateUserParams{
			ID: uuid.Must(uuid.NewV7()), Username: nu.Username, Nickname: nu.Nickname,
			Phone: nu.Phone, PasswordHash: hash,
		})
		if err != nil {
			return mapUserConflict(err)
		}
		if err := q.CreateDefaultSettings(ctx, user.ID); err != nil {
			return fmt.Errorf("创建默认设置失败: %w", err)
		}
		sess, err = s.openSession(ctx, q, user, dev, ip)
		return err
	})
	return sess, err
}

func mapUserConflict(err error) error {
	switch {
	case db.IsUniqueViolation(err, "users_username_key"):
		return errUsernameTaken
	case db.IsUniqueViolation(err, "users_phone_key"):
		return errPhoneTaken
	}
	return fmt.Errorf("创建用户失败: %w", err)
}

// openSession 创建或复用设备会话并签发令牌，须在事务中调用。
func (s *Service) openSession(ctx context.Context, q *dbgen.Queries, user dbgen.User, dev DeviceMeta, ip string) (Session, error) {
	raw, hash, err := NewRefreshToken()
	if err != nil {
		return Session{}, err
	}
	refreshExp := s.d.Now().Add(s.d.RefreshTTL)
	device, err := q.UpsertDevice(ctx, dbgen.UpsertDeviceParams{
		ID: uuid.Must(uuid.NewV7()), UserID: user.ID, InstallationID: dev.InstallationID, Platform: dev.Platform,
		Model: dev.Model, OsVersion: dev.OSVersion, AppVersion: dev.AppVersion,
		RefreshHash: hash, RefreshExpiresAt: &refreshExp, LastIp: ip,
	})
	if err != nil {
		return Session{}, fmt.Errorf("保存设备会话失败: %w", err)
	}
	access, accessExp, err := s.d.Tokens.IssueAccess(user.ID, device.ID)
	if err != nil {
		return Session{}, err
	}
	return Session{User: user, DeviceID: device.ID, Tokens: TokenPair{
		AccessToken: access, AccessExpiresAt: accessExp, RefreshToken: raw, RefreshExpiresAt: refreshExp,
	}}, nil
}

func (s *Service) limitLoginIP(ctx context.Context, ip string) error {
	r, err := s.d.Limiter.Hit(ctx, "login:ip:"+ip, loginIPLimit, loginIPWindow)
	if err != nil {
		return err
	}
	if !r.Allowed {
		return httpx.TooManyRequests(httpx.CodeRateLimited, "操作过于频繁，请稍后再试", r.RetryAfter)
	}
	return nil
}

func loginFailKey(username string) string { return "login:fail:" + strings.ToLower(username) }

// LoginPassword 用户名密码登录；连续失败 loginFailLimit 次后锁定 loginLockWindow。
func (s *Service) LoginPassword(ctx context.Context, username, password string, dev DeviceMeta, ip string) (Session, error) {
	if err := s.limitLoginIP(ctx, ip); err != nil {
		return Session{}, err
	}
	lock, err := s.d.Limiter.Peek(ctx, loginFailKey(username), loginFailLimit)
	if err != nil {
		return Session{}, err
	}
	if !lock.Allowed {
		return Session{}, httpx.TooManyRequests(CodeAccountLocked, "密码错误次数过多，账号已临时锁定，可使用短信验证码登录", lock.RetryAfter)
	}
	user, ok, err := s.verifyLogin(ctx, username, password)
	if err != nil {
		return Session{}, err
	}
	if !ok {
		if _, err := s.d.Limiter.Hit(ctx, loginFailKey(username), loginFailLimit, loginLockWindow); err != nil {
			return Session{}, err
		}
		return Session{}, errInvalidCredentials
	}
	_ = s.d.Limiter.Reset(ctx, loginFailKey(username))
	var sess Session
	err = s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		sess, err = s.openSession(ctx, q, user, dev, ip)
		return err
	})
	return sess, err
}

// verifyLogin 校验用户名与密码；用户不存在时也做一次等价耗时的校验。参数过时时顺带升级哈希。
func (s *Service) verifyLogin(ctx context.Context, username, password string) (dbgen.User, bool, error) {
	q := s.d.Tx.Queries()
	user, err := q.GetUserByUsername(ctx, username)
	if db.IsNotFound(err) {
		_, _, _ = s.d.Hasher.Verify(ctx, password, s.dummyHash)
		return dbgen.User{}, false, nil
	}
	if err != nil {
		return dbgen.User{}, false, fmt.Errorf("查询用户失败: %w", err)
	}
	ok, rehash, err := s.d.Hasher.Verify(ctx, password, user.PasswordHash)
	if err != nil || !ok {
		return dbgen.User{}, false, err
	}
	if rehash {
		s.upgradeHash(ctx, user.ID, password)
	}
	return user, true, nil
}

func (s *Service) upgradeHash(ctx context.Context, userID uuid.UUID, password string) {
	hash, err := s.d.Hasher.Hash(ctx, password)
	if err == nil {
		err = s.d.Tx.Queries().UpdateUserPasswordHash(ctx, dbgen.UpdateUserPasswordHashParams{ID: userID, PasswordHash: hash})
	}
	if err != nil {
		s.d.Logger.WarnContext(ctx, "password rehash failed", "user_id", userID, "error", err)
	}
}

// RevokeDevices 让这些设备立即下线：Access Token 通过下线标记失效，Refresh Token 已在库中清除。
func (s *Service) RevokeDevices(ctx context.Context, ids []uuid.UUID) error {
	return s.d.Revoked.MarkRevoked(ctx, ids, s.d.Now())
}

// Authenticate 校验 Bearer 令牌并确认设备未下线。
func (s *Service) Authenticate(ctx context.Context, authorization string) (Principal, error) {
	raw, ok := strings.CutPrefix(authorization, "Bearer ")
	if !ok || raw == "" {
		return Principal{}, httpx.Unauthorized("请先登录")
	}
	p, err := s.d.Tokens.ParseAccess(raw)
	if err != nil {
		return Principal{}, httpx.Unauthorized("登录已失效，请重新登录")
	}
	revoked, err := s.d.Revoked.IsRevoked(ctx, p)
	if err != nil {
		s.d.Logger.ErrorContext(ctx, "revocation check failed", "error", err)
		return Principal{}, httpx.NewError(http.StatusServiceUnavailable, httpx.CodeUnavailable, "服务暂时不可用，请稍后重试")
	}
	if revoked {
		return Principal{}, httpx.Unauthorized("该设备已下线，请重新登录")
	}
	return p, nil
}

// errReused 表示 Refresh Token 在宽限期外被重放，需在事务提交后让设备下线。
var errReused = errors.New("refresh token reused")
