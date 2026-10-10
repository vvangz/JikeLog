package reminder

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
)

func TestReminderBody(t *testing.T) {
	sh := location("Asia/Shanghai")
	at := time.Date(2026, 10, 12, 15, 30, 0, 0, sh)
	cases := []struct {
		name   string
		memo   memoTime
		offset int
		fire   time.Time
		want   string
	}{
		{"准时", memoTime{At: at}, 0, at, "15:30 的备忘到时间了"},
		{"当天提前", memoTime{At: at}, 15, at.Add(-15 * time.Minute), "今天 15:30 有一条备忘"},
		{"提前一天", memoTime{At: at}, 1440, at.AddDate(0, 0, -1), "明天 15:30 有一条备忘"},
		{"提前更久", memoTime{At: at}, 4320, at.AddDate(0, 0, -3), "10月12日 15:30 有一条备忘"},
		{"全天当天", memoTime{At: at, AllDay: true}, 0, at, "今天有一条全天备忘"},
		{"全天提前", memoTime{At: at, AllDay: true}, 4320, at.AddDate(0, 0, -3), "10月12日有一条全天备忘"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := reminderBody(c.memo, c.offset, c.fire, sh); got != c.want {
				t.Fatalf("got %q want %q", got, c.want)
			}
		})
	}
}

func TestLocationFallback(t *testing.T) {
	if location("").String() != defaultTimeZone {
		t.Fatal("未上报时区时使用默认时区")
	}
	if location("Mars/Base") != time.UTC {
		t.Fatal("无效时区退回 UTC")
	}
}

func TestParseMemo(t *testing.T) {
	ms := time.Date(2026, 10, 12, 7, 30, 0, 0, time.UTC).UnixMilli()
	raw, _ := json.Marshal(map[string]any{"content": "v1:密文", "at": ms, "allDay": 1})
	m, err := parseMemo(dbgen.Record{Fields: raw})
	if err != nil || !m.AllDay || m.At.UnixMilli() != ms {
		t.Fatalf("m=%+v err=%v", m, err)
	}
	if _, err := parseMemo(dbgen.Record{Fields: []byte(`{"content":"x"}`)}); err == nil {
		t.Fatal("缺少时间应报错")
	}
	if _, err := parseMemo(dbgen.Record{Fields: []byte(`not json`)}); err == nil {
		t.Fatal("非法 JSON 应报错")
	}
}
