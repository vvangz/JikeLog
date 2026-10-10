package account

import (
	"context"
	"fmt"
	"time"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
)

const (
	maxPushTokenLen = 128
	maxTimeZoneLen  = 64
)

// UpdatePush 登记当前设备的推送标识与提醒能力（ADR-008）。
// 同一推送标识只属于一台设备：它出现在新设备（或新账号）上时，从原设备摘除。
func (s *Service) UpdatePush(ctx context.Context, p auth.Principal, in apigen.PushRegistration) error {
	provider, token, err := checkPush(in)
	if err != nil {
		return err
	}
	return s.tx.InTx(ctx, func(q *dbgen.Queries) error {
		if token != nil {
			err := q.ReleasePushToken(ctx, dbgen.ReleasePushTokenParams{PushProvider: provider, PushToken: token, ID: p.DeviceID})
			if err != nil {
				return fmt.Errorf("释放推送标识失败: %w", err)
			}
		}
		n, err := q.SetDevicePush(ctx, dbgen.SetDevicePushParams{
			PushProvider: provider, PushToken: token, TimeZone: in.TimeZone,
			LocalReminders: in.LocalReminders, ID: p.DeviceID, UserID: p.UserID,
		})
		if err != nil {
			return fmt.Errorf("保存推送登记失败: %w", err)
		}
		if n == 0 {
			return errDeviceNotFound
		}
		return nil
	})
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
