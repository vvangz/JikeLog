package syncer

import (
	"encoding/json"
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
