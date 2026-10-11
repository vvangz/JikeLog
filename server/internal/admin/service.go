// Package admin 实现 Web 管理后台（ADR-011）：独立的管理员账号与会话、只读的用户配置查询，
// 以及覆盖全部查看与管理操作的审计日志。管理员看不到任何用户内容。
package admin

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

// 角色。
const (
	RoleSuperAdmin = "super_admin"
	RoleViewer     = "viewer"
)

const (
	// SessionTTL 为管理员会话的最长时长，到期后必须重新登录。
	SessionTTL = 12 * time.Hour
	// maxFailures 为同一用户名从同一 IP 在 lockDuration 内允许的登录失败次数，达到后锁定到窗口结束。
	// 按用户名计数（不论是否存在），锁定的表现一致，不能借此判断用户名是否存在；
	// 加上 IP，别人无法在自己的网络里把管理员锁住。
	maxFailures  = 5
	lockDuration = 15 * time.Minute
	// maxUserFailures 为同一用户名（不论来源）每小时允许的失败次数，防止换 IP 分布式猜密码。
	maxUserFailures   = 30
	userFailureWindow = time.Hour
	// maxPasswordChecks 为修改密码时当前密码校验错误的上限（每 15 分钟），防止用盗来的令牌猜密码。
	maxPasswordChecks = 5
	// refreshGrace 为 Refresh Token 轮换后旧令牌仍可换取 Access Token 的时长（多个标签页同时刷新）。
	refreshGrace = 10 * time.Second
	// ipLoginLimit 为同一 IP 在 ipLoginWindow 内最多尝试登录的次数。
	ipLoginLimit  = 20
	ipLoginWindow = 15 * time.Minute
)

// 错误码。
const (
	CodeInvalidCredentials = "INVALID_CREDENTIALS" //nolint:gosec // 错误码，不是凭据
	CodeLocked             = "ADMIN_LOCKED"
	CodeDisabled           = "ADMIN_DISABLED"
	CodeForbidden          = "ADMIN_FORBIDDEN"
	CodePasswordChange     = "PASSWORD_CHANGE_REQUIRED"
	CodeUsernameTaken      = "USERNAME_TAKEN"
	CodeLastSuperAdmin     = "LAST_SUPER_ADMIN"
	CodeNotFound           = "NOT_FOUND"
)

var (
	errInvalidCredentials = httpx.NewError(http.StatusUnauthorized, CodeInvalidCredentials, "用户名或密码错误")
	errDisabled           = httpx.NewError(http.StatusForbidden, CodeDisabled, "该管理员账号已停用")
	errSession            = httpx.Unauthorized("登录已失效，请重新登录")
	errForbidden          = httpx.NewError(http.StatusForbidden, CodeForbidden, "没有权限执行此操作")
	errPasswordChange     = httpx.NewError(http.StatusForbidden, CodePasswordChange, "请先修改初始密码")
	errUsernameTaken      = httpx.NewError(http.StatusConflict, CodeUsernameTaken, "用户名已被使用")
	errLastSuperAdmin     = httpx.NewError(http.StatusConflict, CodeLastSuperAdmin, "至少要保留一个启用的超级管理员")
	errNotFound           = httpx.NewError(http.StatusNotFound, CodeNotFound, "对象不存在")
)

// Deps 为 Service 的依赖。
type Deps struct {
	Tx      db.TxRunner
	Hasher  *auth.Hasher
	Tokens  *Tokens
	Limiter *ratelimit.Limiter
	Logger  *slog.Logger
	// Quota 为每个账号的附件总量上限（用户详情中显示）。
	Quota int64
	// Now 为空时使用 time.Now。
	Now func() time.Time
}

// Service 为管理后台的业务逻辑。
type Service struct {
	d Deps
	// dummyHash 用于用户名不存在时执行一次同样耗时的校验（见 dummy）。
	dummyOnce sync.Once
	dummyHash string
}

// NewService 创建 Service。
func NewService(d Deps) *Service {
	if d.Now == nil {
		d.Now = time.Now
	}
	return &Service{d: d}
}

// dummy 返回一个真实的密码哈希，用户名不存在时用它校验，避免通过响应时间判断用户名是否存在。
// 不使用请求的 ctx：请求取消不能让它永久为空。
func (s *Service) dummy() string {
	s.dummyOnce.Do(func() {
		h, err := s.d.Hasher.Hash(context.Background(), "jikelog-dummy-password-1")
		if err != nil {
			s.d.Logger.Error("compute dummy hash failed", "error", err)
			return
		}
		s.dummyHash = h
	})
	return s.dummyHash
}

// Principal 为通过认证的管理员。
type Principal struct {
	AdminID   uuid.UUID
	SessionID uuid.UUID
	Username  string
	Role      string
	// MustChangePassword 为 true 时只能修改密码、查看自己或退出。
	MustChangePassword bool
}

// Meta 为请求来源，写入审计日志。
type Meta struct {
	IP        string
	UserAgent string
}

// Session 为登录或刷新的结果：Access Token 交给页面，Refresh Token 写入 Cookie。
type Session struct {
	AccessToken  string
	ExpiresAt    time.Time
	RefreshToken string
	// RefreshExpires 为会话（Refresh Token）的到期时刻。
	RefreshExpires time.Time
	Admin          dbgen.AdminUser
}

// Authenticate 校验 Authorization 头中的管理员令牌，且会话仍有效（未退出、未改密码、账号未停用）。
func (s *Service) Authenticate(ctx context.Context, header string) (Principal, error) {
	raw, ok := bearer(header)
	if !ok {
		return Principal{}, errSession
	}
	adminID, sessionID, err := s.d.Tokens.Parse(raw)
	if err != nil {
		return Principal{}, errSession
	}
	row, err := s.d.Tx.Queries().GetAdminForSession(ctx, dbgen.GetAdminForSessionParams{
		SessionID: sessionID, AdminID: adminID, Now: s.d.Now(),
	})
	if db.IsNotFound(err) {
		return Principal{}, errSession
	}
	if err != nil {
		return Principal{}, fmt.Errorf("校验管理员会话失败: %w", err)
	}
	return Principal{
		AdminID: row.ID, SessionID: sessionID, Username: row.Username, Role: row.Role,
		MustChangePassword: row.MustChangePassword,
	}, nil
}

// Login 用用户名和密码登录。失败时不区分用户名不存在与密码错误；同一用户名失败过多时，
// 不论是否存在都同样锁定。
func (s *Service) Login(ctx context.Context, username, password string, m Meta) (Session, error) {
	if r, err := s.d.Limiter.Hit(ctx, "admin-login-ip:"+m.IP, ipLoginLimit, ipLoginWindow); err != nil {
		return Session{}, err
	} else if !r.Allowed {
		return Session{}, httpx.TooManyRequests(httpx.CodeRateLimited, "尝试次数过多，请稍后再试", r.RetryAfter)
	}
	name := strings.ToLower(auditUsername(username))
	keys := failKeys{pair: "admin-login-fail:" + name + "|" + m.IP, user: "admin-login-fail:" + name}
	if retry, locked, err := s.lockedOut(ctx, keys); err != nil {
		return Session{}, err
	} else if locked {
		s.audit(ctx, auditEntry{username: username, action: ActionLoginFailed, meta: m, detail: map[string]any{"reason": "locked"}})
		return Session{}, lockedError(retry)
	}
	if len(username) > maxUsernameLen || len(password) > maxPasswordLen {
		_, _, _ = s.d.Hasher.Verify(ctx, "", s.dummy())
		return Session{}, s.loginFailed(ctx, keys, nil, username, "unknown_user", m)
	}
	q := s.d.Tx.Queries()
	a, err := q.GetAdminByUsername(ctx, username)
	if db.IsNotFound(err) {
		_, _, _ = s.d.Hasher.Verify(ctx, password, s.dummy()) // 与用户存在时耗时相近
		return Session{}, s.loginFailed(ctx, keys, nil, username, "unknown_user", m)
	}
	if err != nil {
		return Session{}, fmt.Errorf("查询管理员失败: %w", err)
	}
	ok, _, err := s.d.Hasher.Verify(ctx, password, a.PasswordHash)
	if err != nil {
		return Session{}, err
	}
	if !ok {
		return Session{}, s.loginFailed(ctx, keys, &a.ID, a.Username, "password", m)
	}
	if a.Disabled {
		s.audit(ctx, auditEntry{adminID: &a.ID, username: a.Username, action: ActionLoginFailed, meta: m, detail: map[string]any{"reason": "disabled"}})
		return Session{}, errDisabled
	}
	_ = s.d.Limiter.Reset(ctx, keys.pair)
	now := s.d.Now()
	if err := q.RecordAdminLogin(ctx, dbgen.RecordAdminLoginParams{ID: a.ID, Now: &now}); err != nil {
		return Session{}, fmt.Errorf("记录登录失败: %w", err)
	}
	a.LastLoginAt = &now
	sess, err := s.newSession(ctx, a)
	if err != nil {
		return Session{}, err
	}
	s.audit(ctx, auditEntry{adminID: &a.ID, username: a.Username, action: ActionLogin, meta: m})
	return sess, nil
}

func lockedError(retry time.Duration) error {
	e := httpx.NewError(http.StatusLocked, CodeLocked, "登录失败次数过多，已临时锁定，请稍后再试")
	e.RetryAfter = retry
	return e
}

// failKeys 为登录失败计数的两个键：用户名 + IP，以及只按用户名。
type failKeys struct{ pair, user string }

// lockedOut 报告是否因失败过多而锁定，以及还需等待多久。
func (s *Service) lockedOut(ctx context.Context, k failKeys) (time.Duration, bool, error) {
	pair, err := s.d.Limiter.Peek(ctx, k.pair, maxFailures)
	if err != nil {
		return 0, false, err
	}
	if !pair.Allowed {
		return pair.RetryAfter, true, nil
	}
	user, err := s.d.Limiter.Peek(ctx, k.user, maxUserFailures)
	if err != nil {
		return 0, false, err
	}
	return user.RetryAfter, !user.Allowed, nil
}

// loginFailed 记录一次登录失败；达到上限时返回锁定。
func (s *Service) loginFailed(ctx context.Context, k failKeys, adminID *uuid.UUID, username, reason string, m Meta) error {
	pair, err := s.d.Limiter.Hit(ctx, k.pair, maxFailures, lockDuration)
	if err != nil {
		return err
	}
	user, err := s.d.Limiter.Hit(ctx, k.user, maxUserFailures, userFailureWindow)
	if err != nil {
		return err
	}
	s.audit(ctx, auditEntry{adminID: adminID, username: username, action: ActionLoginFailed, meta: m, detail: map[string]any{"reason": reason}})
	switch {
	case pair.Count >= maxFailures:
		return lockedError(pair.RetryAfter)
	case user.Count >= maxUserFailures:
		return lockedError(user.RetryAfter)
	}
	return errInvalidCredentials
}

// newSession 创建会话并签发令牌。
func (s *Service) newSession(ctx context.Context, a dbgen.AdminUser) (Session, error) {
	raw, hash, err := auth.NewRefreshToken()
	if err != nil {
		return Session{}, err
	}
	id, err := uuid.NewV7()
	if err != nil {
		return Session{}, err
	}
	now := s.d.Now()
	expires := now.Add(SessionTTL)
	if err := s.d.Tx.Queries().CreateAdminSession(ctx, dbgen.CreateAdminSessionParams{
		ID: id, AdminID: a.ID, RefreshHash: hash, Now: now, ExpiresAt: expires,
	}); err != nil {
		return Session{}, fmt.Errorf("创建会话失败: %w", err)
	}
	return s.issue(a, id, raw, expires)
}

func (s *Service) issue(a dbgen.AdminUser, sessionID uuid.UUID, refresh string, expires time.Time) (Session, error) {
	token, exp, err := s.d.Tokens.Issue(a.ID, sessionID)
	if err != nil {
		return Session{}, err
	}
	return Session{AccessToken: token, ExpiresAt: exp, RefreshToken: refresh, RefreshExpires: expires, Admin: a}, nil
}

// Refresh 用 Refresh Token 换取新的 Access Token，Refresh Token 同时轮换。会话的到期时刻不变。
// 刚被轮换掉的旧令牌在 refreshGrace 内仍可换取 Access Token（多个标签页同时刷新），但不再轮换，
// 返回的 Session.RefreshToken 为空，Cookie 保持另一个标签页设置的新值。
func (s *Service) Refresh(ctx context.Context, refresh string) (Session, error) {
	if refresh == "" {
		return Session{}, errSession
	}
	var out Session
	var reused *uuid.UUID
	err := s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		hash := auth.HashToken(refresh)
		sess, err := q.GetAdminSessionByHashForUpdate(ctx, hash)
		rotate := true
		if db.IsNotFound(err) {
			sess, err = q.GetAdminSessionByPrevHash(ctx, hash)
			rotate = false
		}
		if db.IsNotFound(err) {
			return errSession
		}
		if err != nil {
			return fmt.Errorf("查询会话失败: %w", err)
		}
		now := s.d.Now()
		if sess.RevokedAt != nil || !now.Before(sess.ExpiresAt) {
			return errSession
		}
		if !rotate && (sess.RotatedAt == nil || now.Sub(*sess.RotatedAt) > refreshGrace) {
			// 已轮换掉的令牌在宽限期后又被使用：可能被盗用，撤销整个会话（事务回滚后在外面执行）
			reused = &sess.ID
			return errReused
		}
		a, err := q.GetAdmin(ctx, sess.AdminID)
		if err != nil {
			return fmt.Errorf("查询管理员失败: %w", err)
		}
		if a.Disabled {
			return errSession
		}
		raw := ""
		if rotate {
			var newHash []byte
			if raw, newHash, err = auth.NewRefreshToken(); err != nil {
				return err
			}
			if err := q.RotateAdminSession(ctx, dbgen.RotateAdminSessionParams{ID: sess.ID, RefreshHash: newHash, Now: &now}); err != nil {
				return fmt.Errorf("轮换会话失败: %w", err)
			}
		}
		out, err = s.issue(a, sess.ID, raw, sess.ExpiresAt)
		return err
	})
	if errors.Is(err, errReused) && reused != nil {
		if err := s.d.Tx.Queries().RevokeAdminSession(ctx, dbgen.RevokeAdminSessionParams{ID: *reused, Now: ptr(s.d.Now())}); err != nil {
			return Session{}, fmt.Errorf("撤销会话失败: %w", err)
		}
		s.d.Logger.WarnContext(ctx, "admin refresh token reused, session revoked", "session_id", *reused)
		return Session{}, errSession
	}
	return out, err
}

// errReused 表示旧 Refresh Token 在宽限期后被再次使用。
var errReused = errors.New("refresh token reused")

// Logout 让 Refresh Token 对应的会话失效（会话不存在也视为成功）。
func (s *Service) Logout(ctx context.Context, refresh string, m Meta) error {
	if refresh == "" {
		return nil
	}
	q := s.d.Tx.Queries()
	sess, err := q.GetAdminSessionByHashForUpdate(ctx, auth.HashToken(refresh))
	if db.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("查询会话失败: %w", err)
	}
	if err := q.RevokeAdminSession(ctx, dbgen.RevokeAdminSessionParams{ID: sess.ID, Now: ptr(s.d.Now())}); err != nil {
		return fmt.Errorf("退出失败: %w", err)
	}
	if a, err := q.GetAdmin(ctx, sess.AdminID); err == nil {
		s.audit(ctx, auditEntry{adminID: &a.ID, username: a.Username, action: ActionLogout, meta: m})
	}
	return nil
}

// Me 返回当前管理员。
func (s *Service) Me(ctx context.Context, p Principal) (dbgen.AdminUser, error) {
	a, err := s.d.Tx.Queries().GetAdmin(ctx, p.AdminID)
	if err != nil {
		return dbgen.AdminUser{}, fmt.Errorf("查询管理员失败: %w", err)
	}
	return a, nil
}

// ChangePassword 修改自己的密码：其他会话全部失效，当前会话保留。
func (s *Service) ChangePassword(ctx context.Context, p Principal, current, next string, m Meta) error {
	if err := checkPassword(next); err != nil {
		return err
	}
	a, err := s.Me(ctx, p)
	if err != nil {
		return err
	}
	checkKey := "admin-password-check:" + a.ID.String()
	if r, err := s.d.Limiter.Peek(ctx, checkKey, maxPasswordChecks); err != nil {
		return err
	} else if !r.Allowed {
		return httpx.TooManyRequests(httpx.CodeRateLimited, "当前密码错误次数过多，请稍后再试", r.RetryAfter)
	}
	ok, _, err := s.d.Hasher.Verify(ctx, current, a.PasswordHash)
	if err != nil {
		return err
	}
	if !ok {
		if _, err := s.d.Limiter.Hit(ctx, checkKey, maxPasswordChecks, lockDuration); err != nil {
			return err
		}
		return httpx.Validation(map[string]string{"currentPassword": "当前密码不正确"}) //nolint:gosec // 校验提示，不是凭据
	}
	if current == next {
		return httpx.Validation(map[string]string{"newPassword": "新密码不能与当前密码相同"}) //nolint:gosec // 校验提示，不是凭据
	}
	hash, err := s.d.Hasher.Hash(ctx, next)
	if err != nil {
		return err
	}
	err = s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		now := s.d.Now()
		if err := q.SetAdminPassword(ctx, dbgen.SetAdminPasswordParams{ID: a.ID, PasswordHash: hash, MustChangePassword: false, Now: now}); err != nil {
			return err
		}
		return q.RevokeOtherAdminSessions(ctx, dbgen.RevokeOtherAdminSessionsParams{AdminID: a.ID, Keep: p.SessionID, Now: &now})
	})
	if err != nil {
		return fmt.Errorf("修改密码失败: %w", err)
	}
	s.audit(ctx, auditEntry{adminID: &a.ID, username: a.Username, action: ActionChangePassword, meta: m})
	return nil
}

func ptr[T any](v T) *T { return &v }

// sessionRetention 为过期会话在表中保留的时长（之后清除）。
const sessionRetention = 24 * time.Hour

// Cleanup 清除早已过期的管理员会话。
func (s *Service) Cleanup(ctx context.Context) error {
	if _, err := s.d.Tx.Queries().PruneAdminSessions(ctx, s.d.Now().Add(-sessionRetention)); err != nil {
		return fmt.Errorf("清除管理员会话失败: %w", err)
	}
	return nil
}

// IsAdminToken 报告 Authorization 头是否携带管理员令牌。
func (s *Service) IsAdminToken(header string) bool { return s.d.Tokens.IsAdminToken(header) }
