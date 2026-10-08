// Package account 实现当前账号相关接口：资料、修改密码、绑定/换绑手机号、注销账号、设备管理与用户设置。
package account

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

// 账号相关错误码。
const (
	CodePhoneNotBound       = "PHONE_NOT_BOUND"
	CodeDeviceNotFound      = "DEVICE_NOT_FOUND"
	CodeCannotRevokeCurrent = "CANNOT_REVOKE_CURRENT_DEVICE"
)

const (
	verifyFailLimit  = 5
	verifyFailWindow = 15 * time.Minute
)

var (
	errWrongPassword  = httpx.NewError(http.StatusBadRequest, auth.CodeInvalidCredentials, "当前密码错误")
	errPhoneNotBound  = httpx.NewError(http.StatusBadRequest, CodePhoneNotBound, "当前账号未绑定手机号")
	errNeedIdentity   = httpx.Validation(map[string]string{"currentPassword": "请输入当前密码或手机验证码"}) //nolint:gosec // 字段名与提示文案，不是凭据
	errDeviceNotFound = httpx.NewError(http.StatusNotFound, CodeDeviceNotFound, "设备不存在或已下线")
	errRevokeCurrent  = httpx.NewError(http.StatusBadRequest, CodeCannotRevokeCurrent, "不能下线当前设备，请使用退出登录")
)

// Service 为账号业务逻辑。
type Service struct {
	tx      db.TxRunner
	auth    *auth.Service
	limiter *ratelimit.Limiter
}

// NewService 创建 Service。
func NewService(tx db.TxRunner, authSvc *auth.Service, limiter *ratelimit.Limiter) *Service {
	return &Service{tx: tx, auth: authSvc, limiter: limiter}
}

// currentUser 读取调用方账号；账号已被删除时按未登录处理。
func (s *Service) currentUser(ctx context.Context, p auth.Principal) (dbgen.User, error) {
	u, err := s.tx.Queries().GetUserByID(ctx, p.UserID)
	if db.IsNotFound(err) {
		return dbgen.User{}, httpx.Unauthorized("账号不存在或已注销")
	}
	if err != nil {
		return dbgen.User{}, fmt.Errorf("查询用户失败: %w", err)
	}
	return u, nil
}

// verifyIdentity 用当前密码或当前手机号验证码确认是本人操作；连续失败会被临时限制。
func (s *Service) verifyIdentity(ctx context.Context, u dbgen.User, password, smsCode *string) error {
	key := "verify:fail:" + u.ID.String()
	lock, err := s.limiter.Peek(ctx, key, verifyFailLimit)
	if err != nil {
		return err
	}
	if !lock.Allowed {
		return httpx.TooManyRequests(httpx.CodeRateLimited, "验证失败次数过多，请稍后再试", lock.RetryAfter)
	}
	switch {
	case password != nil && *password != "":
		ok, err := s.auth.CheckUserPassword(ctx, u, *password)
		if err != nil {
			return err
		}
		if ok {
			return nil
		}
		if _, err := s.limiter.Hit(ctx, key, verifyFailLimit, verifyFailWindow); err != nil {
			return err
		}
		return errWrongPassword
	case smsCode != nil && *smsCode != "":
		if u.Phone == nil {
			return errPhoneNotBound
		}
		return s.auth.VerifySMS(ctx, auth.PurposeVerifyCurrent, *u.Phone, *smsCode)
	default:
		return errNeedIdentity
	}
}

// UpdateNickname 修改昵称。
func (s *Service) UpdateNickname(ctx context.Context, p auth.Principal, nickname string) (dbgen.User, error) {
	u, err := s.tx.Queries().UpdateUserNickname(ctx, dbgen.UpdateUserNicknameParams{ID: p.UserID, Nickname: nickname})
	if db.IsNotFound(err) {
		return dbgen.User{}, httpx.Unauthorized("账号不存在或已注销")
	}
	if err != nil {
		return dbgen.User{}, fmt.Errorf("修改昵称失败: %w", err)
	}
	return u, nil
}

// ChangePassword 验证身份后修改密码，其他设备全部下线。
func (s *Service) ChangePassword(ctx context.Context, p auth.Principal, current, smsCode *string, newPassword string) error {
	u, err := s.currentUser(ctx, p)
	if err != nil {
		return err
	}
	if err := s.verifyIdentity(ctx, u, current, smsCode); err != nil {
		return err
	}
	return s.auth.SetPassword(ctx, u.ID, newPassword, &p.DeviceID)
}

// DeleteAccount 验证身份后永久删除账号（级联删除全部数据），所有设备下线。
func (s *Service) DeleteAccount(ctx context.Context, p auth.Principal, current, smsCode *string) error {
	u, err := s.currentUser(ctx, p)
	if err != nil {
		return err
	}
	if err := s.verifyIdentity(ctx, u, current, smsCode); err != nil {
		return err
	}
	var revoked []uuid.UUID
	err = s.tx.InTx(ctx, func(q *dbgen.Queries) error {
		if revoked, err = q.RevokeAllDevices(ctx, u.ID); err != nil {
			return fmt.Errorf("下线设备失败: %w", err)
		}
		if _, err := q.DeleteUser(ctx, u.ID); err != nil {
			return fmt.Errorf("删除账号失败: %w", err)
		}
		return nil
	})
	if err != nil {
		return err
	}
	return s.auth.RevokeDevices(ctx, append(revoked, p.DeviceID))
}
