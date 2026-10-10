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
	var out []Reminder
	for _, r := range allReminders(fields) {
		if r.FireAt.After(now) {
			out = append(out, r)
		}
	}
	return out
}

// allReminders 返回备忘录的全部提醒（含已过时刻的）。已完成或没有时间的备忘录没有提醒。
func allReminders(fields map[string]Value) []Reminder {
	at, ok := fields["at"].(int64)
	if !ok || fields["done"] == int64(1) {
		return nil
	}
	offsets, _ := fields["reminders"].(string)
	start := time.UnixMilli(at).UTC()
	var out []Reminder
	for _, m := range ParseOffsets(offsets) {
		out = append(out, Reminder{Offset: m, FireAt: start.Add(-time.Duration(m) * time.Minute)})
	}
	return out
}

// scheduleMemo 在推送事务内按备忘录的最新状态更新待发提醒（ADR-008）：
// 修改时间或提醒、标记完成、删除都会替换掉旧的提醒；已到时尚未发出、且时刻没变的提醒保留，
// 不会因为恰好此时修改了内容等其他字段而丢失。
func (w *writer) scheduleMemo(ctx context.Context, id uuid.UUID, next State) error {
	existing, err := w.q.ListMemoReminders(ctx, id)
	if err != nil {
		return fmt.Errorf("读取待发提醒失败: %w", err)
	}
	want := map[int]time.Time{}
	if !next.Deleted {
		now := w.s.d.Now()
		pending := map[int]time.Time{}
		for _, e := range existing {
			pending[int(e.OffsetMin)] = e.FireAt
		}
		for _, r := range allReminders(next.Fields) {
			if old, ok := pending[r.Offset]; r.FireAt.After(now) || (ok && old.Equal(r.FireAt)) {
				want[r.Offset] = r.FireAt
			}
		}
	}
	for _, e := range existing {
		if _, ok := want[int(e.OffsetMin)]; ok {
			continue
		}
		if err := w.q.DeleteMemoReminder(ctx, dbgen.DeleteMemoReminderParams{MemoID: id, OffsetMin: e.OffsetMin}); err != nil {
			return fmt.Errorf("删除提醒失败: %w", err)
		}
	}
	for offset, fire := range want {
		err := w.q.UpsertMemoReminder(ctx, dbgen.UpsertMemoReminderParams{
			MemoID: id, UserID: w.p.UserID, OffsetMin: int32(offset), FireAt: fire, //nolint:gosec // 已校验不超过 30 天
		})
		if err != nil {
			return fmt.Errorf("写入提醒失败: %w", err)
		}
	}
	return nil
}
