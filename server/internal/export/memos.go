package export

import (
	"cmp"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/vvangz/JikeLog/server/internal/syncer"
)

// writeMemos 写出备忘录：可导入日历的 ICS（带提醒）和 CSV 表格。
func (a *archive) writeMemos(d *dataset) error {
	if !d.has(ModuleMemo) {
		return nil
	}
	dir := moduleLabel[ModuleMemo]
	memos := slices.Clone(d.records(syncer.EntityMemo))
	slices.SortStableFunc(memos, func(x, y syncer.Snapshot) int {
		return cmp.Compare(num(x.Fields, "at"), num(y.Fields, "at"))
	})
	w, err := a.create(a.names.unique(dir, "备忘录", ".ics"))
	if err != nil {
		return err
	}
	if _, err := w.Write([]byte(a.calendar(memos))); err != nil {
		return err
	}
	t := table{name: "备忘录", header: []string{"时间", "全天", "内容", "提醒", "已完成"}}
	for _, m := range memos {
		f := m.Fields
		at := time.UnixMilli(num(f, "at")).In(a.loc)
		when := at.Format("2006-01-02 15:04")
		if flag(f, "allDay") {
			when = at.Format("2006-01-02")
		}
		t.rows = append(t.rows, []any{when, flag(f, "allDay"), str(f, "content"), offsetsText(str(f, "reminders")), flag(f, "done")})
	}
	cw, err := a.create(a.names.unique(dir, "备忘录", ".csv"))
	if err != nil {
		return err
	}
	return writeCSV(cw, t)
}

// calendar 生成 iCalendar（RFC 5545）。全天备忘按导出时区的日期写成全天事件。
func (a *archive) calendar(memos []syncer.Snapshot) string {
	var b strings.Builder
	line := func(s string) { b.WriteString(foldICS(s)) }
	line("BEGIN:VCALENDAR")
	line("VERSION:2.0")
	line("PRODID:-//JikeLog//Export//ZH")
	line("CALSCALE:GREGORIAN")
	line("X-WR-CALNAME:即刻日志备忘录")
	stamp := a.now.UTC().Format("20060102T150405Z")
	for _, m := range memos {
		f := m.Fields
		at := time.UnixMilli(num(f, "at"))
		line("BEGIN:VEVENT")
		line("UID:" + m.ID.String() + "@jikelog")
		line("DTSTAMP:" + stamp)
		if flag(f, "allDay") {
			day := at.In(a.loc)
			line("DTSTART;VALUE=DATE:" + day.Format("20060102"))
			line("DTEND;VALUE=DATE:" + day.AddDate(0, 0, 1).Format("20060102"))
		} else {
			line("DTSTART:" + at.UTC().Format("20060102T150405Z"))
		}
		summary := memoTitle(str(f, "content"))
		if flag(f, "done") {
			summary = "[已完成] " + summary
		}
		line("SUMMARY:" + escapeICS(summary))
		if content := str(f, "content"); content != "" {
			line("DESCRIPTION:" + escapeICS(content))
		}
		if !flag(f, "done") {
			for _, off := range syncer.ParseOffsets(str(f, "reminders")) {
				line("BEGIN:VALARM")
				line("ACTION:DISPLAY")
				line("DESCRIPTION:" + escapeICS(summary))
				line(fmt.Sprintf("TRIGGER:-PT%dM", off))
				line("END:VALARM")
			}
		}
		line("END:VEVENT")
	}
	line("END:VCALENDAR")
	return b.String()
}

// memoTitle 为备忘内容的第一行（最多 100 个字符）。
func memoTitle(content string) string {
	for _, l := range strings.Split(content, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			if utf8.RuneCountInString(l) > 100 {
				return string([]rune(l)[:100]) + "…"
			}
			return l
		}
	}
	return "备忘"
}

// escapeICS 转义 TEXT 值中的反斜杠、分号、逗号与换行。
func escapeICS(s string) string {
	return strings.NewReplacer(`\`, `\\`, ";", `\;`, ",", `\,`, "\r\n", `\n`, "\n", `\n`, "\r", `\n`).Replace(s)
}

// foldICS 把一行折成不超过 75 个字节的若干行（续行以空格开头），不拆开多字节字符；行尾为 CRLF。
func foldICS(s string) string {
	const limit = 75
	var b strings.Builder
	width := 0
	for _, r := range s {
		n := utf8.RuneLen(r)
		if width+n > limit {
			b.WriteString("\r\n ")
			width = 1
		}
		b.WriteRune(r)
		width += n
	}
	b.WriteString("\r\n")
	return b.String()
}

// offsetsText 把提前提醒的分钟数写成"准时、提前 15 分钟、提前 1 天"。
func offsetsText(s string) string {
	var parts []string
	for _, m := range syncer.ParseOffsets(s) {
		switch {
		case m == 0:
			parts = append(parts, "准时")
		case m%1440 == 0:
			parts = append(parts, fmt.Sprintf("提前 %d 天", m/1440))
		case m%60 == 0:
			parts = append(parts, fmt.Sprintf("提前 %d 小时", m/60))
		default:
			parts = append(parts, fmt.Sprintf("提前 %d 分钟", m))
		}
	}
	return strings.Join(parts, "、")
}
