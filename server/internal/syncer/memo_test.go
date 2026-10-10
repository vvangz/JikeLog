package syncer

import (
	"testing"
	"time"
)

func TestReminderTimes(t *testing.T) {
	now := time.Date(2026, 10, 10, 8, 0, 0, 0, time.UTC)
	at := time.Date(2026, 10, 10, 9, 0, 0, 0, time.UTC)
	memo := func(reminders any, done int64) map[string]Value {
		return map[string]Value{"content": "开会", "at": at.UnixMilli(), "reminders": reminders, "done": done}
	}
	cases := []struct {
		name   string
		fields map[string]Value
		want   []Reminder
	}{
		{"准时与提前 15 分钟", memo("0,15", 0), []Reminder{{0, at}, {15, at.Add(-15 * time.Minute)}}},
		{"已过的提醒不再保留", memo("0,60,120", 0), []Reminder{{0, at}}},
		{"恰好此刻的提醒已过", memo("60", 0), nil},
		{"已完成没有提醒", memo("0,15", 1), nil},
		{"不提醒", memo("", 0), nil},
		{"提醒字段为空", memo(nil, 0), nil},
		{"缺少时间", map[string]Value{"content": "x", "reminders": "0"}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := ReminderTimes(c.fields, now)
			if len(got) != len(c.want) {
				t.Fatalf("got %v want %v", got, c.want)
			}
			for i := range got {
				if got[i].Offset != c.want[i].Offset || !got[i].FireAt.Equal(c.want[i].FireAt) {
					t.Fatalf("got %v want %v", got, c.want)
				}
			}
		})
	}
}
