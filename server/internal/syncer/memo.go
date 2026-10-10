package syncer

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
)

// Reminder 为备忘录的一次提醒：提前量（分钟）与提醒时刻。
type Reminder struct {
	Offset int
	FireAt time.Time
}

// ReminderTimes 返回备忘录尚未到时的提醒。已完成或没有时间的备忘录没有提醒。
func ReminderTimes(fields map[string]Value, now time.Time) []Reminder {
	at, ok := fields["at"].(int64)
	if !ok || fields["done"] == int64(1) {
		return nil
	}
	offsets, _ := fields["reminders"].(string)
	start := time.UnixMilli(at).UTC()
	var out []Reminder
	for _, m := range ParseOffsets(offsets) {
		fire := start.Add(-time.Duration(m) * time.Minute)
		if fire.After(now) {
			out = append(out, Reminder{Offset: m, FireAt: fire})
		}
	}
	return out
}

// scheduleMemo 在推送事务内按备忘录的最新状态重建待发提醒（ADR-008）：
// 修改时间或提醒、标记完成、删除都会替换掉旧的提醒。
func (w *writer) scheduleMemo(ctx context.Context, id uuid.UUID, next State) error {
	if err := w.q.DeleteMemoReminders(ctx, id); err != nil {
		return fmt.Errorf("清除旧提醒失败: %w", err)
	}
	if next.Deleted {
		return nil
	}
	for _, r := range ReminderTimes(next.Fields, w.s.d.Now()) {
		err := w.q.InsertMemoReminder(ctx, dbgen.InsertMemoReminderParams{
			MemoID: id, UserID: w.p.UserID, OffsetMin: int32(r.Offset), FireAt: r.FireAt, //nolint:gosec // 已校验不超过 30 天
		})
		if err != nil {
			return fmt.Errorf("写入提醒失败: %w", err)
		}
	}
	return nil
}
