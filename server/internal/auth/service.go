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

var (
	errInvalidCredentials = httpx.NewError(http.StatusUnauthorized, CodeInvalidCredentials, "用户名或密码错误")
	errRefreshInvalid     = httpx.NewError(http.StatusUnauthorized, CodeRefreshInvalid, "登录已失效，请重新登录")
	errTicketInvalid      = httpx.NewError(http.StatusBadRequest, CodeTicketInvalid, "注册已超时，请重新获取验证码")
	errCaptchaFailed      = httpx.NewError(http.StatusBadRequest, CodeCaptchaFailed, "人机验证未通过，请重试")
	errUsernameTaken      = httpx.NewError(http.StatusConflict, CodeUsernameTaken, "用户名已被占用")
	errPhoneTaken         = httpx.NewError(http.StatusConflict, CodePhoneTaken, "该手机号已绑定其他账号")
	errDeviceOffline      = httpx.Unauthorized("该设备已下线，请重新登录")
)

// CaptchaVerifier 校验人机验证结果。生产实现为阿里云验证码 2.0（v0.9.0）。
type CaptchaVerifier interface {
	Verify(ctx context.Context, param, ip string) (bool, error)
}

// NoopCaptcha 总是通过，仅用于开发与测试（配置校验禁止在其他环境使用）。
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
	Replay     *RefreshReplay
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

// now 返回毫秒精度的当前时间：令牌的签发时间只精确到毫秒，会话时间点必须与之可比。
func (s *Service) now() time.Time { return s.d.Now().Truncate(time.Millisecond) }

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
	if err := s.limitIP(ctx, bucketRegister, ip); err != nil {
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
		opened, err := s.openSession(ctx, q, user, dev, ip)
		sess = opened
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
// 复用设备时 tokens_valid_after 更新为本次登录时刻，该设备此前的令牌全部作废。
func (s *Service) openSession(ctx context.Context, q *dbgen.Queries, user dbgen.User, dev DeviceMeta, ip string) (Session, error) {
	raw, hash, err := NewRefreshToken()
	if err != nil {
		return Session{}, err
	}
	now := s.now()
	refreshExp := now.Add(s.d.RefreshTTL)
	device, err := q.UpsertDevice(ctx, dbgen.UpsertDeviceParams{
		ID: uuid.Must(uuid.NewV7()), UserID: user.ID, InstallationID: dev.InstallationID, Platform: dev.Platform,
		Model: dev.Model, OsVersion: dev.OSVersion, AppVersion: dev.AppVersion,
		RefreshHash: hash, RefreshExpiresAt: &refreshExp, LastIp: ip, Now: now,
	})
	if err != nil {
		return Session{}, fmt.Errorf("保存设备会话失败: %w", err)
	}
	access, accessExp, err := s.d.Tokens.IssueAccess(user.ID, device.ID, now)
	if err != nil {
		return Session{}, err
	}
	return Session{User: user, DeviceID: device.ID, Tokens: TokenPair{
		AccessToken: access, AccessExpiresAt: accessExp, RefreshToken: raw, RefreshExpiresAt: refreshExp,
	}}, nil
}

// Authenticate 校验 Bearer 令牌，并在数据库中确认设备会话仍有效、令牌签发于本次会话开始之后。
// 下线与修改密码都在同一事务中更新设备行，因此立即生效，不依赖缓存。
func (s *Service) Authenticate(ctx context.Context, authorization string) (Principal, error) {
	raw, ok := strings.CutPrefix(authorization, "Bearer ")
	if !ok || raw == "" {
		return Principal{}, httpx.Unauthorized("请先登录")
	}
	p, err := s.d.Tokens.ParseAccess(raw)
	if err != nil {
		return Principal{}, httpx.Unauthorized("登录已失效，请重新登录")
	}
	sess, err := s.d.Tx.Queries().GetDeviceSession(ctx, p.DeviceID)
	if db.IsNotFound(err) {
		return Principal{}, errDeviceOffline
	}
	if err != nil {
		s.d.Logger.ErrorContext(ctx, "device session lookup failed", "error", err)
		return Principal{}, httpx.NewError(http.StatusServiceUnavailable, httpx.CodeUnavailable, "服务暂时不可用，请稍后重试")
	}
	if sess.UserID != p.UserID || p.IssuedAt.UnixMilli() < sess.TokensValidAfter.UnixMilli() {
		return Principal{}, errDeviceOffline
	}
	return p, nil
}

// errReused 表示 Refresh Token 在宽限期外被重放，需在事务提交后让设备下线。
var errReused = errors.New("refresh token reused")
