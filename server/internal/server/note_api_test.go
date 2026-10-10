package server

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

func TestNoteSyncEncryptedAcrossDevices(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("notes01")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	folder, note, worklog := newID(), newID(), newID()
	k := a.hlc(0, nodeA)
	r := a.push(d1, c1,
		c1.encode(worklogChange{entity: "note_folder", id: folder,
			fields: map[string]any{"name": "项目资料", "parentId": nil},
			clocks: map[string]string{"name": k, "parentId": k}}),
		c1.encode(worklogChange{entity: "note", id: note,
			fields: map[string]any{
				"title": "接口设计", "body": "## 表格\n\n| a | b |\n| --- | --- |", "format": "rich",
				"folderId": folder, "favorite": 1, "pinned": 0, "tags": "后端\n草稿", "worklogs": worklog,
			},
			clocks: map[string]string{"title": k, "body": k, "format": k, "folderId": k, "favorite": k, "pinned": k, "tags": k, "worklogs": k}}),
	)
	a.expect(r, http.StatusOK, "")
	for _, res := range r.results() {
		if res["status"] != "applied" {
			t.Fatalf("推送应成功：%v", res)
		}
	}

	// 标题、正文、标签、文件夹名加密落库；格式与关联 ID 保持明文
	rows, err := a.pool.Query(context.Background(), "SELECT fields::text FROM records WHERE id = ANY($1::uuid[])", []string{folder, note})
	if err != nil {
		t.Fatal(err)
	}
	var stored strings.Builder
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err != nil {
			t.Fatal(err)
		}
		stored.WriteString(s)
	}
	rows.Close()
	for _, plain := range []string{"项目资料", "接口设计", "表格", "后端"} {
		if strings.Contains(stored.String(), plain) {
			t.Fatalf("%q 应加密落库：%s", plain, stored.String())
		}
	}
	if !strings.Contains(stored.String(), `"rich"`) || !strings.Contains(stored.String(), worklog) {
		t.Fatalf("格式与关联应为明文：%s", stored.String())
	}

	got := map[string]map[string]any{}
	for _, rec := range a.pull(d2, c2, 0).records() {
		got[rec["entity"].(string)] = rec["fields"].(map[string]any)
	}
	n := got["note"]
	title, err1 := c2.open("note", note, "title", n["title"].(string))
	tags, err2 := c2.open("note", note, "tags", n["tags"].(string))
	name, err3 := c2.open("note_folder", folder, "name", got["note_folder"]["name"].(string))
	if err1 != nil || err2 != nil || err3 != nil || title != "接口设计" || tags != "后端\n草稿" || name != "项目资料" {
		t.Fatalf("另一台设备应能解密：%q %q %q (%v %v %v)", title, tags, name, err1, err2, err3)
	}
	if n["folderId"] != folder || num(n, "favorite") != 1 || n["format"] != "rich" {
		t.Fatalf("fields=%v", n)
	}
}

func TestNoteTagsMergeConcurrentAdditions(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("notes02")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	id := newID()
	base := a.hlc(0, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{entity: "note", id: id,
		fields: map[string]any{"format": "markdown", "tags": "Go"},
		clocks: map[string]string{"format": base, "tags": base}})), http.StatusOK, "")

	k1 := a.hlc(1, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{entity: "note", id: id,
		fields: map[string]any{"tags": "Go\n工作"}, clocks: map[string]string{"tags": k1},
		baseClocks: map[string]string{"tags": base},
		patches:    map[string]string{"tags": patchJSON(map[string]any{"p": 2, "b": "Go", "d": "", "i": "\n工作", "a": ""})},
	})), http.StatusOK, "")

	k2 := a.hlc(2, nodeB)
	r := a.push(d2, c2, c2.encode(worklogChange{entity: "note", id: id,
		fields: map[string]any{"tags": "Go\n学习"}, clocks: map[string]string{"tags": k2},
		baseClocks: map[string]string{"tags": base},
		patches:    map[string]string{"tags": patchJSON(map[string]any{"p": 2, "b": "Go", "d": "", "i": "\n学习", "a": ""})},
	}))
	res := r.results()[0]
	if res["status"] != "merged" {
		t.Fatalf("两台设备同时加标签应合并：%v", res)
	}
	tags, err := c2.open("note", id, "tags", res["record"].(map[string]any)["fields"].(map[string]any)["tags"].(string))
	if err != nil || !strings.Contains(tags, "工作") || !strings.Contains(tags, "学习") || !strings.HasPrefix(tags, "Go\n") {
		t.Fatalf("tags=%q err=%v", tags, err)
	}
}

func TestNoteRejectsInvalidFields(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("notes03")
	c1 := a.handshake(d1)
	k := a.hlc(0, nodeA)
	r := a.push(d1, c1,
		c1.encode(worklogChange{entity: "note", id: newID(),
			fields: map[string]any{"format": "html"}, clocks: map[string]string{"format": k}}),
		c1.encode(worklogChange{entity: "note", id: newID(),
			fields: map[string]any{"format": "markdown", "favorite": 2}, clocks: map[string]string{"format": k, "favorite": k}}),
		c1.encode(worklogChange{entity: "note", id: newID(),
			fields: map[string]any{"title": "缺少格式"}, clocks: map[string]string{"title": k}}),
		c1.encode(worklogChange{entity: "note_folder", id: newID(),
			fields: map[string]any{"name": ""}, clocks: map[string]string{"name": k}}),
	)
	a.expect(r, http.StatusOK, "")
	for i, res := range r.results() {
		if res["status"] != "rejected" {
			t.Errorf("第 %d 条应被拒绝：%v", i, res)
		}
	}
}

func TestNoteAttachments(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("notes04")
	c1 := a.handshake(d1)
	note, folder := newID(), newID()
	k := a.hlc(0, nodeA)
	a.expect(a.push(d1, c1,
		c1.encode(worklogChange{entity: "note", id: note, fields: map[string]any{"format": "markdown"}, clocks: map[string]string{"format": k}}),
		c1.encode(worklogChange{entity: "note_folder", id: folder, fields: map[string]any{"name": "资料"}, clocks: map[string]string{"name": k}}),
	), http.StatusOK, "")

	body := []byte("%PDF-1.7")
	a.expect(a.requestUploadFor(d1, c1, "note", note, newID(), "说明.pdf", body), http.StatusCreated, "")
	a.expect(a.requestUploadFor(d1, c1, "note_folder", folder, newID(), "说明.pdf", body), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
}
