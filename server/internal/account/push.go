package account

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// CodePushTokenInUse 表示推送标识正被其他账号仍在使用的设备占用。
const CodePushTokenInUse = "PUSH_TOKEN_IN_USE" //nolint:gosec // 错误码，不是凭据

const (
	maxPushTokenLen = 128
	maxTimeZoneLen  = 64
	// 每台设备每小时最多登记推送的次数（正常只在登录、回到前台且有变化时登记）。
	pushPerHour = 30
	// pushTokenKey 为推送标识唯一索引（见 00003_reminders.sql）。
	pushTokenKey = "devices_push_token_key"
)

var errPushTokenInUse = httpx.NewError(http.StatusConflict, CodePushTokenInUse, "推送标识已被其他账号的设备使用")

// UpdatePush 登记当前设备的推送标识与提醒能力（ADR-008）。
//
// 同一推送标识只属于一台设备：同一账号的其他设备（重装 App），或已下线、会话已过期的设备
// （同一部手机换了账号）上的标识会被摘除；其他账号仍在使用的设备上的标识不能抢占。
func (s *Service) UpdatePush(ctx context.Context, p auth.Principal, in apigen.PushRegistration) error {
	provider, token, err := checkPush(in)
	if err != nil {
		return err
	}
	r, err := s.limiter.Hit(ctx, "push:register:"+p.DeviceID.String(), pushPerHour, time.Hour)
	if err != nil {
		return err
	}
	if !r.Allowed {
		return httpx.TooManyRequests(httpx.CodeRateLimited, "推送登记过于频繁，请稍后再试", r.RetryAfter)
	}
	err = s.tx.InTx(ctx, func(q *dbgen.Queries) error {
		if token != nil {
			err := q.ReleasePushToken(ctx, dbgen.ReleasePushTokenParams{
				PushProvider: provider, PushToken: token, ID: p.DeviceID, UserID: p.UserID,
			})
			if err != nil {
				return fmt.Errorf("释放推送标识失败: %w", err)
			}
		}
		n, err := q.SetDevicePush(ctx, dbgen.SetDevicePushParams{
			PushProvider: provider, PushToken: token, TimeZone: in.TimeZone,
			LocalReminders: in.LocalReminders, LocalUntil: in.LocalUntil, ID: p.DeviceID, UserID: p.UserID,
		})
		if err != nil {
			return fmt.Errorf("保存推送登记失败: %w", err)
		}
		if n == 0 {
			return errDeviceNotFound
		}
		return nil
	})
	if db.IsUniqueViolation(err, pushTokenKey) {
		return errPushTokenInUse
	}
	return err
}

// checkPush 校验推送登记，返回通道与标识（不接收推送时均为 nil）。
func checkPush(in apigen.PushRegistration) (provider, token *string, err error) {
	f := auth.FieldErrors{}
	hasProvider := in.Provider != nil
	hasToken := in.Token != nil
	switch {
	case hasProvider != hasToken:
		f.Add("token", "推送通道与标识必须同时提供")
	case hasProvider && !in.Provider.Valid():
		f.Add("provider", "不支持的推送通道")
	case hasToken && !validPushToken(*in.Token):
		f.Add("token", "推送标识格式不正确")
	}
	if len(in.TimeZone) > maxTimeZoneLen {
		f.Add("timeZone", "时区名称过长")
	} else if in.TimeZone != "" {
		if _, err := time.LoadLocation(in.TimeZone); err != nil {
			f.Add("timeZone", "未知的时区")
		}
	}
	if err := f.Err(); err != nil {
		return nil, nil, err
	}
	if !hasProvider {
		return nil, nil, nil
	}
	pv := string(*in.Provider)
	return &pv, in.Token, nil
}

// validPushToken 只接受可打印 ASCII（极光 Registration ID 为字母数字）。
func validPushToken(s string) bool {
	if s == "" || len(s) > maxPushTokenLen {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] <= ' ' || s[i] > '~' {
			return false
		}
	}
	return true
}
