package account

import (
	"context"
	"fmt"
	"slices"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

// ListDevices 返回已登录设备，标记出当前设备。
func (s *Service) ListDevices(ctx context.Context, p auth.Principal) ([]apigen.Device, error) {
	rows, err := s.tx.Queries().ListActiveDevices(ctx, p.UserID)
	if err != nil {
		return nil, fmt.Errorf("查询设备失败: %w", err)
	}
	out := make([]apigen.Device, 0, len(rows))
	for _, d := range rows {
		out = append(out, apigen.Device{
			Id: d.ID, Platform: d.Platform, Model: d.Model, OsVersion: d.OsVersion, AppVersion: d.AppVersion,
			LastActiveAt: d.LastActiveAt, CreatedAt: d.CreatedAt, Current: d.ID == p.DeviceID,
		})
	}
	return out, nil
}

// RevokeDevice 让本账号的另一台设备下线。
func (s *Service) RevokeDevice(ctx context.Context, p auth.Principal, deviceID uuid.UUID) error {
	if deviceID == p.DeviceID {
		return errRevokeCurrent
	}
	ids, err := s.tx.Queries().RevokeDevice(ctx, dbgen.RevokeDeviceParams{ID: deviceID, UserID: p.UserID})
	if err != nil {
		return fmt.Errorf("下线设备失败: %w", err)
	}
	if len(ids) == 0 {
		return errDeviceNotFound
	}
	return s.auth.RevokeDevices(ctx, ids)
}

const (
	minFontScale    = 0.8
	maxFontScale    = 1.4
	maxReminders    = 5
	maxReminderMins = 30 * 24 * 60
)

// GetSettings 返回用户设置；缺失时补建默认值。
func (s *Service) GetSettings(ctx context.Context, p auth.Principal) (dbgen.UserSetting, error) {
	q := s.tx.Queries()
	st, err := q.GetSettings(ctx, p.UserID)
	if db.IsNotFound(err) {
		if err := q.CreateDefaultSettings(ctx, p.UserID); err != nil {
			return dbgen.UserSetting{}, fmt.Errorf("创建默认设置失败: %w", err)
		}
		st, err = q.GetSettings(ctx, p.UserID)
	}
	if err != nil {
		return dbgen.UserSetting{}, fmt.Errorf("查询设置失败: %w", err)
	}
	return st, nil
}

// UpdateSettings 校验并保存用户设置。提醒列表会去重并升序排列。
func (s *Service) UpdateSettings(ctx context.Context, p auth.Principal, in apigen.SettingsInput) (dbgen.UserSetting, error) {
	f := auth.FieldErrors{}
	if !in.ThemeMode.Valid() {
		f.Add("themeMode", "不支持的主题")
	}
	if in.FontScale < minFontScale || in.FontScale > maxFontScale {
		f.Add("fontScale", "字号缩放范围为 0.8–1.4")
	}
	if !in.WeekStart.Valid() {
		f.Add("weekStart", "一周的第一天只能是周一或周日")
	}
	reminders := slices.Clone(in.DefaultReminders)
	slices.Sort(reminders)
	reminders = slices.Compact(reminders)
	if len(reminders) > maxReminders {
		f.Add("defaultReminders", "最多设置 5 个提醒")
	}
	for _, m := range reminders {
		if m < 0 || m > maxReminderMins {
			f.Add("defaultReminders", "提前提醒范围为 0 分钟到 30 天")
		}
	}
	if err := f.Err(); err != nil {
		return dbgen.UserSetting{}, err
	}
	if _, err := s.GetSettings(ctx, p); err != nil { // 确保行存在
		return dbgen.UserSetting{}, err
	}
	st, err := s.tx.Queries().UpdateSettings(ctx, dbgen.UpdateSettingsParams{
		UserID: p.UserID, ThemeMode: string(in.ThemeMode), FontScale: in.FontScale,
		DefaultReminders: reminders, WeekStart: int16(in.WeekStart), //nolint:gosec // 已校验只能为 1 或 7
	})
	if err != nil {
		return dbgen.UserSetting{}, fmt.Errorf("保存设置失败: %w", err)
	}
	return st, nil
}

// ToSettings 把数据库设置转换为接口模型。
func ToSettings(st dbgen.UserSetting) apigen.Settings {
	return apigen.Settings{
		ThemeMode: apigen.ThemeMode(st.ThemeMode), FontScale: st.FontScale,
		DefaultReminders: st.DefaultReminders, WeekStart: apigen.SettingsWeekStart(st.WeekStart),
		UpdatedAt: st.UpdatedAt,
	}
}
