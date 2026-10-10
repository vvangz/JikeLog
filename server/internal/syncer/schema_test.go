package syncer

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
)

func TestDecodeValue(t *testing.T) {
	wl := Registry[EntityWorklog].Fields
	att := Registry[EntityAttachment].Fields
	ok := []struct {
		name string
		f    Field
		raw  string
		want Value
	}{
		{"日期", wl["date"], `"2026-10-09"`, "2026-10-09"},
		{"可选字段清空", wl["location"], `null`, nil},
		{"长文本", wl["content"], `"内容"`, "内容"},
		{"整数", att["size"], `1024`, int64(1024)},
		{"UUID", att["ownerId"], `"01a120ee-dabc-74d8-9de1-efc4e24cfd4e"`, "01a120ee-dabc-74d8-9de1-efc4e24cfd4e"},
	}
	for _, c := range ok {
		t.Run(c.name, func(t *testing.T) {
			got, err := c.f.DecodeValue(json.RawMessage(c.raw))
			if err != nil || got != c.want {
				t.Fatalf("got=%v err=%v", got, err)
			}
		})
	}
	bad := []struct {
		name string
		f    Field
		raw  string
	}{
		{"必填为 null", wl["date"], `null`},
		{"日期格式", wl["date"], `"2026/10/09"`},
		{"不是字符串", wl["location"], `123`},
		{"不是整数", att["size"], `"1"`},
		{"超长", wl["location"], `"` + strings.Repeat("长", maxLocationLen+1) + `"`},
		{"UUID 格式", att["ownerId"], `"not-a-uuid"`},
		{"必填为空串", att["mime"], `""`},
	}
	for _, c := range bad {
		t.Run(c.name, func(t *testing.T) {
			if _, err := c.f.DecodeValue(json.RawMessage(c.raw)); err == nil {
				t.Fatal("应当报错")
			}
		})
	}
}

func TestCheckValue(t *testing.T) {
	wl := Registry[EntityWorklog].Fields
	size := Registry[EntityAttachment].Fields["size"]
	if v, err := wl["content"].CheckValue("文本"); err != nil || v != "文本" {
		t.Fatalf("v=%v err=%v", v, err)
	}
	if v, err := size.CheckValue(int64(3)); err != nil || v != int64(3) {
		t.Fatalf("v=%v err=%v", v, err)
	}
	if v, err := wl["location"].CheckValue(nil); err != nil || v != nil {
		t.Fatalf("v=%v err=%v", v, err)
	}
	for name, c := range map[string]struct {
		f Field
		v Value
	}{
		"必填为 nil":  {wl["date"], nil},
		"整数给字符串字段": {wl["location"], int64(1)},
		"字符串给整数字段": {size, "1"},
		"不支持的类型":   {wl["location"], 1.5},
		"非法 UTF-8": {wl["location"], string([]byte{0xff})},
	} {
		if _, err := c.f.CheckValue(c.v); err == nil {
			t.Errorf("%s：应当报错", name)
		}
	}
}

func TestFieldErrorsMessageIsSorted(t *testing.T) {
	err := FieldErrors{"b": "二", "a": "一"}
	if got := err.Error(); got != "字段校验失败：a: 一; b: 二" {
		t.Fatalf("got %q", got)
	}
}

func TestNoteSchema(t *testing.T) {
	note := Registry[EntityNote].Fields
	folder := Registry[EntityNoteFolder].Fields
	for _, f := range []string{"title", "body", "tags"} {
		if !note[f].Sensitive {
			t.Errorf("note.%s 应为敏感字段", f)
		}
	}
	if !folder["name"].Sensitive || !folder["name"].Required {
		t.Error("note_folder.name 应为必填的敏感字段")
	}
	for _, f := range []string{"body", "tags", "worklogs"} {
		if note[f].Kind != KindText {
			t.Errorf("note.%s 应可补丁合并", f)
		}
	}
	if Registry[EntityNote].ServerCreated || Registry[EntityNoteFolder].ServerCreated {
		t.Error("笔记与文件夹由客户端创建")
	}

	ok := []struct {
		name string
		f    Field
		raw  string
		want Value
	}{
		{"格式 markdown", note["format"], `"markdown"`, "markdown"},
		{"格式 rich", note["format"], `"rich"`, "rich"},
		{"收藏", note["favorite"], `1`, int64(1)},
		{"取消置顶", note["pinned"], `0`, int64(0)},
		{"未分类", note["folderId"], `null`, nil},
		{"顶层文件夹", folder["parentId"], `null`, nil},
	}
	for _, c := range ok {
		t.Run(c.name, func(t *testing.T) {
			got, err := c.f.DecodeValue(json.RawMessage(c.raw))
			if err != nil || got != c.want {
				t.Fatalf("got=%v err=%v", got, err)
			}
		})
	}
	bad := []struct {
		name string
		f    Field
		raw  string
	}{
		{"未知格式", note["format"], `"html"`},
		{"格式为空", note["format"], `""`},
		{"标记超出范围", note["favorite"], `2`},
		{"标记为负数", note["pinned"], `-1`},
		{"标记不是整数", note["favorite"], `true`},
		{"文件夹名为空", folder["name"], `""`},
		{"文件夹名超长", folder["name"], `"` + strings.Repeat("名", maxFolderNameLen+1) + `"`},
		{"标题超长", note["title"], `"` + strings.Repeat("题", maxTitleLen+1) + `"`},
		{"所属文件夹不是 UUID", note["folderId"], `"inbox"`},
	}
	for _, c := range bad {
		t.Run(c.name, func(t *testing.T) {
			if _, err := c.f.DecodeValue(json.RawMessage(c.raw)); err == nil {
				t.Fatal("应当报错")
			}
		})
	}
}

func TestCheckValueFlagAndChoices(t *testing.T) {
	note := Registry[EntityNote].Fields
	if v, err := note["favorite"].CheckValue(int64(1)); err != nil || v != int64(1) {
		t.Fatalf("v=%v err=%v", v, err)
	}
	for name, c := range map[string]struct {
		f Field
		v Value
	}{
		"标记超出范围":  {note["favorite"], int64(5)},
		"标记给字符串":  {note["favorite"], "1"},
		"格式不在取值中": {note["format"], "doc"},
	} {
		if _, err := c.f.CheckValue(c.v); err == nil {
			t.Errorf("%s：应当报错", name)
		}
	}
}

func TestMemoSchema(t *testing.T) {
	memo := Registry[EntityMemo].Fields
	if !memo["content"].Sensitive || !memo["content"].Required || memo["content"].Kind != KindText {
		t.Error("memo.content 应为必填、可补丁合并的敏感字段")
	}
	// 服务端要按时推送提醒，时间与提醒设置不能是密文
	for _, f := range []string{"at", "allDay", "reminders", "done"} {
		if memo[f].Sensitive {
			t.Errorf("memo.%s 不应加密", f)
		}
	}
	if !memo["at"].Required {
		t.Error("memo.at 必填")
	}

	ok := []struct {
		name string
		f    Field
		raw  string
		want Value
	}{
		{"时间", memo["at"], `1791374400000`, int64(1791374400000)},
		{"准时提醒", memo["reminders"], `"0"`, "0"},
		{"多个提醒", memo["reminders"], `"0,15,1440"`, "0,15,1440"},
		{"最长提前 30 天", memo["reminders"], `"43200"`, "43200"},
		{"不提醒", memo["reminders"], `""`, ""},
		{"清空提醒", memo["reminders"], `null`, nil},
		{"全天", memo["allDay"], `1`, int64(1)},
		{"已完成", memo["done"], `1`, int64(1)},
	}
	for _, c := range ok {
		t.Run(c.name, func(t *testing.T) {
			got, err := c.f.DecodeValue(json.RawMessage(c.raw))
			if err != nil || got != c.want {
				t.Fatalf("got=%v err=%v", got, err)
			}
		})
	}
	bad := []struct {
		name string
		f    Field
		raw  string
	}{
		{"时间不是整数", memo["at"], `"2026-10-10"`},
		{"时间早于 2000 年", memo["at"], `946684799999`},
		{"时间晚于 2200 年", memo["at"], `7258118400000`},
		{"时间为空", memo["at"], `null`},
		{"提醒为负数", memo["reminders"], `"-5"`},
		{"提醒超过 30 天", memo["reminders"], `"43201"`},
		{"提醒不是数字", memo["reminders"], `"soon"`},
		{"提醒未排序", memo["reminders"], `"15,0"`},
		{"提醒重复", memo["reminders"], `"5,5"`},
		{"提醒超过 5 个", memo["reminders"], `"0,5,10,15,30,60"`},
		{"提醒有空项", memo["reminders"], `"0,,5"`},
		{"提醒有前导零", memo["reminders"], `"05"`},
		{"提醒有空格", memo["reminders"], `"0, 5"`},
		{"内容为空", memo["content"], `""`},
		{"内容超长", memo["content"], `"` + strings.Repeat("备", maxMemoLen+1) + `"`},
	}
	for _, c := range bad {
		t.Run(c.name, func(t *testing.T) {
			if _, err := c.f.DecodeValue(json.RawMessage(c.raw)); err == nil {
				t.Fatal("应当报错")
			}
		})
	}
	if _, err := memo["at"].CheckValue(int64(1)); err == nil {
		t.Error("CheckValue 也应校验时间范围")
	}
}

func TestParseOffsets(t *testing.T) {
	if got := ParseOffsets("0,15,1440"); !slices.Equal(got, []int{0, 15, 1440}) {
		t.Fatalf("got %v", got)
	}
	if got := ParseOffsets(""); len(got) != 0 {
		t.Fatalf("got %v", got)
	}
}

func TestLedgerSchema(t *testing.T) {
	acc := Registry[EntityLedgerAccount].Fields
	cat := Registry[EntityLedgerCategory].Fields
	loan := Registry[EntityLedgerLoan].Fields
	entry := Registry[EntityLedgerEntry].Fields
	// 金额、账户名、对方、备注都是敏感字段（ADR-009）
	for name, f := range map[string]Field{
		"account.name": acc["name"], "account.initialBalance": acc["initialBalance"],
		"category.name": cat["name"], "loan.counterparty": loan["counterparty"], "loan.note": loan["note"],
		"entry.amount": entry["amount"], "entry.fee": entry["fee"], "entry.note": entry["note"],
	} {
		if !f.Sensitive {
			t.Errorf("%s 应为敏感字段", name)
		}
	}
	ok := []struct {
		name string
		f    Field
		raw  string
		want Value
	}{
		{"金额（分）", entry["amount"], `"12345"`, "12345"},
		{"手续费为 0", entry["fee"], `"0"`, "0"},
		{"初始余额为负（信用卡欠款）", acc["initialBalance"], `"-50000"`, "-50000"},
		{"转账", entry["type"], `"transfer"`, "transfer"},
		{"收款", entry["type"], `"collect"`, "collect"},
		{"信用卡", acc["type"], `"credit"`, "credit"},
		{"支出分类", cat["kind"], `"expense"`, "expense"},
		{"借出", loan["direction"], `"lend"`, "lend"},
		{"日期", entry["date"], `"2026-10-11"`, "2026-10-11"},
	}
	for _, c := range ok {
		t.Run(c.name, func(t *testing.T) {
			got, err := c.f.DecodeValue(json.RawMessage(c.raw))
			if err != nil || got != c.want {
				t.Fatalf("got=%v err=%v", got, err)
			}
		})
	}
	bad := []struct {
		name string
		f    Field
		raw  string
	}{
		{"金额为 0", entry["amount"], `"0"`},
		{"金额为负", entry["amount"], `"-5"`},
		{"金额不是数字", entry["amount"], `"12.5"`},
		{"金额有前导零", entry["amount"], `"012"`},
		{"金额超出范围", entry["amount"], `"10000000000000000"`},
		{"金额为整数类型", entry["amount"], `12`},
		{"手续费为负", entry["fee"], `"-1"`},
		{"负零", acc["initialBalance"], `"-0"`},
		{"未知流水类型", entry["type"], `"refund"`},
		{"未知账户类型", acc["type"], `"bank"`},
		{"账户名为空", acc["name"], `""`},
		{"对方为空", loan["counterparty"], `""`},
	}
	for _, c := range bad {
		t.Run(c.name, func(t *testing.T) {
			if _, err := c.f.DecodeValue(json.RawMessage(c.raw)); err == nil {
				t.Fatal("应当报错")
			}
		})
	}
	if _, err := entry["amount"].CheckValue("0"); err == nil {
		t.Error("解密后的金额同样要校验")
	}
}
