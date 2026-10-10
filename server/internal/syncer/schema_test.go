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
