package auth

import (
	"context"
	"fmt"
	"net/netip"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// 按接口划分的单 IP 限额：同一出口 IP 后可能有大量用户（运营商 NAT、公司网络），限额按此放宽，
// 主要用于挡住脚本批量请求；针对单个账号的猜测由失败计数负责。
type ipBucket struct {
	name   string
	limit  int64
	window time.Duration
}

var (
	bucketRegister  = ipBucket{"register", 20, time.Hour}
	bucketLogin     = ipBucket{"login", 100, 10 * time.Minute}
	bucketSMSLogin  = ipBucket{"smslogin", 100, 10 * time.Minute}
	bucketRefresh   = ipBucket{"refresh", 300, 10 * time.Minute}
	loginLockWindow = 15 * time.Minute
)

const (
	// 同一账号 + 同一 IP 连续失败上限
	loginFailPerIP = 5
	// 同一账号来自所有 IP 的失败上限：更高，防分布式猜测，同时让单个攻击者难以锁住他人账号
	loginFailPerUser = 20
)

// ipKey 为限流用的 IP 归并键：IPv6 按 /64 归并（一个用户通常拥有整个 /64）。
func ipKey(ip string) string {
	addr, err := netip.ParseAddr(ip)
	if err != nil {
		return ip
	}
	if addr.Is6() && !addr.Is4In6() {
		if p, err := addr.Prefix(64); err == nil {
			return p.String()
		}
	}
	return addr.Unmap().String()
}

func (s *Service) limitIP(ctx context.Context, b ipBucket, ip string) error {
	r, err := s.d.Limiter.Hit(ctx, b.name+":ip:"+ipKey(ip), b.limit, b.window)
	if err != nil {
		return err
	}
	if !r.Allowed {
		return httpx.TooManyRequests(httpx.CodeRateLimited, "操作过于频繁，请稍后再试", r.RetryAfter)
	}
	return nil
}

func loginFailKeys(username, ip string) (perIP, perUser string) {
	u := strings.ToLower(username)
	return "login:fail:" + u + ":" + ipKey(ip), "login:fail:" + u
}

// takeLoginAttempt 先计数再校验，使并发请求也不能超过失败上限；登录成功时清零。
func (s *Service) takeLoginAttempt(ctx context.Context, username, ip string) error {
	perIP, perUser := loginFailKeys(username, ip)
	for _, c := range []struct {
		key   string
		limit int64
	}{{perIP, loginFailPerIP}, {perUser, loginFailPerUser}} {
		r, err := s.d.Limiter.Hit(ctx, c.key, c.limit, loginLockWindow)
		if err != nil {
			return err
		}
		if !r.Allowed {
			return httpx.TooManyRequests(CodeAccountLocked, "密码错误次数过多，账号已临时锁定，可使用短信验证码登录", r.RetryAfter)
		}
	}
	return nil
}

func (s *Service) clearLoginFailures(ctx context.Context, username, ip string) {
	perIP, perUser := loginFailKeys(username, ip)
	_ = s.d.Limiter.Reset(ctx, perIP)
	_ = s.d.Limiter.Reset(ctx, perUser)
}

// LoginPassword 用户名密码登录。
func (s *Service) LoginPassword(ctx context.Context, username, password string, dev DeviceMeta, ip string) (Session, error) {
	if err := s.limitIP(ctx, bucketLogin, ip); err != nil {
		return Session{}, err
	}
	if err := s.takeLoginAttempt(ctx, username, ip); err != nil {
		return Session{}, err
	}
	user, ok, err := s.verifyLogin(ctx, username, password)
	if err != nil {
		return Session{}, err
	}
	if !ok {
		return Session{}, errInvalidCredentials
	}
	s.clearLoginFailures(ctx, username, ip)
	var sess Session
	err = s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		opened, err := s.openSession(ctx, q, user, dev, ip)
		sess = opened
		return err
	})
	return sess, err
}

// verifyLogin 校验用户名与密码；用户不存在时也做一次等价耗时的校验。参数过时时顺带升级哈希。
func (s *Service) verifyLogin(ctx context.Context, username, password string) (dbgen.User, bool, error) {
	user, err := s.d.Tx.Queries().GetUserByUsername(ctx, username)
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
		s.upgradeHash(ctx, user, password)
	}
	return user, true, nil
}

// upgradeHash 用当前参数重新哈希；只在库中仍是旧哈希时写入，避免覆盖并发修改的新密码。
func (s *Service) upgradeHash(ctx context.Context, user dbgen.User, password string) {
	hash, err := s.d.Hasher.Hash(ctx, password)
	if err == nil {
		err = s.d.Tx.Queries().UpdateUserPasswordHash(ctx, dbgen.UpdateUserPasswordHashParams{
			ID: user.ID, PasswordHash: hash, OldHash: user.PasswordHash,
		})
	}
	if err != nil {
		s.d.Logger.WarnContext(ctx, "password rehash failed", "user_id", user.ID, "error", err)
	}
}

// CheckUserPassword 校验指定用户的当前密码。
func (s *Service) CheckUserPassword(ctx context.Context, user dbgen.User, password string) (bool, error) {
	ok, _, err := s.d.Hasher.Verify(ctx, password, user.PasswordHash)
	return ok, err
}

// SetPassword 更新密码并让其他设备下线（同一事务）；keep 为需要保留的当前设备，nil 表示全部下线。
func (s *Service) SetPassword(ctx context.Context, userID uuid.UUID, password string, keep *uuid.UUID) error {
	hash, err := s.d.Hasher.Hash(ctx, password)
	if err != nil {
		return err
	}
	now := s.now()
	return s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		if err := q.UpdateUserPassword(ctx, dbgen.UpdateUserPasswordParams{ID: userID, PasswordHash: hash}); err != nil {
			return fmt.Errorf("更新密码失败: %w", err)
		}
		var err error
		if keep != nil {
			_, err = q.RevokeOtherDevices(ctx, dbgen.RevokeOtherDevicesParams{UserID: userID, KeepID: *keep, Now: now})
		} else {
			_, err = q.RevokeAllDevices(ctx, dbgen.RevokeAllDevicesParams{UserID: userID, Now: now})
		}
		if err != nil {
			return fmt.Errorf("下线其他设备失败: %w", err)
		}
		return nil
	})
}

// Now 返回服务使用的当前时间（毫秒精度），供其他模块在下线设备等操作中保持一致。
func (s *Service) Now() time.Time { return s.now() }
