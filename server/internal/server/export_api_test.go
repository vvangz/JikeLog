package server

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/export"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/pusher"
	"github.com/vvangz/JikeLog/server/internal/platform/storage"
	"github.com/vvangz/JikeLog/server/internal/syncer"
)

var allModules = []string{"worklog", "note", "memo", "ledger"}

func (a *testApp) createExport(s session, modules []string, attachments bool) apiResp {
	a.t.Helper()
	return a.call(http.MethodPost, "/api/v1/exports", map[string]any{"modules": modules, "attachments": attachments}, s.access)
}

func (a *testApp) runExports() int {
	a.t.Helper()
	n, err := a.app.Exports.Tick(context.Background())
	if err != nil {
		a.t.Fatal(err)
	}
	return n
}

// download 通过预签名地址下载导出文件并解开。
func (a *testApp) download(s session, id string) map[string][]byte {
	a.t.Helper()
	r := a.call(http.MethodGet, "/api/v1/exports/"+id+"/download", nil, s.access)
	a.expect(r, http.StatusOK, "")
	resp, err := http.Get(r.str("data", "url"))
	if err != nil {
		a.t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		a.t.Fatalf("下载失败：%d %s", resp.StatusCode, body)
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		a.t.Fatal(err)
	}
	files := map[string][]byte{}
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			a.t.Fatal(err)
		}
		b, _ := io.ReadAll(rc)
		_ = rc.Close()
		files[f.Name] = b
	}
	return files
}

func TestExportGeneratesDecryptedZip(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("export01")
	c1 := a.handshake(d1)
	a.registerPush(d1, "token-export-1", true)
	a.registerPush(d2, "token-export-2", true)

	k := a.hlc(0, nodeA)
	change := func(entity, id string, fields map[string]any) map[string]any {
		clocks := map[string]string{}
		for f := range fields {
			clocks[f] = k
		}
		return c1.encode(worklogChange{entity: entity, id: id, fields: fields, clocks: clocks})
	}
	wl, folder, note, memo, acc, cat, entry, att := newID(), newID(), newID(), newID(), newID(), newID(), newID(), newID()
	r := a.push(d1, c1,
		change("worklog", wl, map[string]any{"date": "2026-10-09", "location": "上海虹桥", "content": "季度评审"}),
		change("note_folder", folder, map[string]any{"name": "项目"}),
		change("note", note, map[string]any{
			"title": "周报", "body": "![图](attachment:" + att + ")\n本周完成", "format": "markdown", "folderId": folder, "tags": "工作",
		}),
		change("memo", memo, map[string]any{"content": "交房租", "at": time.Date(2026, 10, 12, 7, 0, 0, 0, time.UTC).UnixMilli(), "allDay": 0, "reminders": "15", "done": 0}),
		change("ledger_account", acc, map[string]any{"name": "钱包", "type": "cash", "initialBalance": "0"}),
		change("ledger_category", cat, map[string]any{"name": "餐饮", "kind": "expense"}),
		change("ledger_entry", entry, map[string]any{"type": "expense", "amount": "3850", "date": "2026-10-11", "accountId": acc, "categoryId": cat, "note": "午饭"}),
	)
	a.expect(r, http.StatusOK, "")
	img := []byte("PNG image body")
	up := a.requestUploadFor(d1, c1, "note", note, att, "图.png", img)
	a.expect(up, http.StatusCreated, "")
	if code := upload(t, up, img); code != http.StatusOK {
		t.Fatalf("上传失败：%d", code)
	}
	a.expect(a.call(http.MethodPost, "/api/v1/attachments/"+att+"/complete", nil, d1.access), http.StatusOK, "")

	created := a.createExport(d1, allModules, true)
	a.expect(created, http.StatusAccepted, "")
	id := created.str("data", "id")
	if created.str("data", "status") != "pending" {
		t.Fatalf("新建的导出应在排队：%v", created.data())
	}
	a.expect(a.createExport(d1, []string{"memo"}, false), http.StatusConflict, export.CodeInProgress)
	a.expect(a.call(http.MethodGet, "/api/v1/exports/"+id+"/download", nil, d1.access), http.StatusConflict, export.CodeNotReady)
	a.expect(a.call(http.MethodDelete, "/api/v1/exports/"+id, nil, d1.access), http.StatusConflict, export.CodeInProgress)

	if n := a.runExports(); n != 1 {
		t.Fatalf("应处理 1 个导出，实际 %d", n)
	}
	got := a.call(http.MethodGet, "/api/v1/exports/"+id, nil, d1.access)
	a.expect(got, http.StatusOK, "")
	if got.str("data", "status") != "done" || num(got.data(), "size") <= 0 {
		t.Fatalf("导出应完成：%v", got.data())
	}
	expires, _ := time.Parse(time.RFC3339Nano, got.str("data", "expiresAt"))
	if d := expires.Sub(a.clock.Now()); d < 23*time.Hour || d > 25*time.Hour {
		t.Fatalf("文件保留 24 小时：%v", expires)
	}

	files := a.download(d1, id)
	for name, want := range map[string]string{
		"工作日志/2026-10-09.md":   "上海虹桥",
		"笔记/项目/周报.md":          "](<../../附件/" + att + "/图.png>)",
		"备忘录/备忘录.ics":          "SUMMARY:交房租",
		"记账/流水.csv":            "2026-10-11,支出,38.50,0.00,钱包,,餐饮,,午饭",
		"附件/" + att + "/图.png": "PNG image body",
		"data.json":            "季度评审",
		"README.txt":           "1 个附件文件",
	} {
		if !strings.Contains(string(files[name]), want) {
			t.Errorf("%s 应包含 %q：%q", name, want, files[name])
		}
	}

	// 只通知发起导出的设备，且通知中不含数据
	sent := a.pushes.take()
	if len(sent) != 1 || sent[0].Tokens[0] != "token-export-1" || sent[0].Channel != pusher.ChannelGeneral ||
		sent[0].Extras["exportId"] != id || strings.Contains(sent[0].Body, "交房租") {
		t.Fatalf("推送：%+v", sent)
	}

	list := a.call(http.MethodGet, "/api/v1/exports", nil, d2.access)
	a.expect(list, http.StatusOK, "")
	if items := list.Body["data"].([]any); len(items) != 1 {
		t.Fatalf("同一账号的设备都能看到导出：%v", items)
	}

	// 其他账号看不到
	other := a.register("export01b", "secret123", "install-x")
	a.expect(a.call(http.MethodGet, "/api/v1/exports/"+id, nil, other.access), http.StatusNotFound, export.CodeNotFound)
	a.expect(a.call(http.MethodGet, "/api/v1/exports/"+id+"/download", nil, other.access), http.StatusNotFound, export.CodeNotFound)
	a.expect(a.call(http.MethodDelete, "/api/v1/exports/"+id, nil, other.access), http.StatusNotFound, export.CodeNotFound)

	// 删除后文件与记录都不在了
	uid := a.userID(d1)
	a.expect(a.call(http.MethodDelete, "/api/v1/exports/"+id, nil, d1.access), http.StatusOK, "")
	if _, err := a.store.Size(context.Background(), export.ObjectKey(uid, uuid.MustParse(id))); !errors.Is(err, storage.ErrNotFound) {
		t.Fatalf("文件应已删除：%v", err)
	}
	a.expect(a.call(http.MethodGet, "/api/v1/exports/"+id, nil, d1.access), http.StatusNotFound, export.CodeNotFound)
}

func TestExportValidationLimitAndExpiry(t *testing.T) {
	a := newTestApp(t)
	s := a.register("export02", "secret123", "install-a")
	a.expect(a.createExport(s, []string{}, false), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(a.createExport(s, []string{"photos"}, false), http.StatusUnprocessableEntity, "VALIDATION_FAILED")

	var first string
	for i := 0; i < export.MaxPerDay; i++ {
		r := a.createExport(s, []string{"memo", "memo"}, false)
		a.expect(r, http.StatusAccepted, "")
		if mods := r.data()["modules"].([]any); len(mods) != 1 {
			t.Fatalf("重复的模块只算一次：%v", mods)
		}
		if i == 0 {
			first = r.str("data", "id")
		}
		a.runExports()
		a.clock.Advance(time.Minute)
	}
	a.expect(a.createExport(s, []string{"memo"}, false), http.StatusTooManyRequests, export.CodeLimit)
	// 没有注册推送的设备不发通知
	if sent := a.pushes.take(); len(sent) != 0 {
		t.Fatalf("不应推送：%v", sent)
	}

	// 24 小时后文件过期：清理后不能再下载，额度也恢复
	a.clock.Advance(24 * time.Hour)
	n, err := a.app.Exports.Cleanup(context.Background())
	s = a.relogin("export02", "install-a") // 访问令牌已过期
	if err != nil || n != export.MaxPerDay {
		t.Fatalf("应清理 %d 个文件：%d %v", export.MaxPerDay, n, err)
	}
	got := a.call(http.MethodGet, "/api/v1/exports/"+first, nil, s.access)
	if got.str("data", "status") != "expired" {
		t.Fatalf("应为已过期：%v", got.data())
	}
	a.expect(a.call(http.MethodGet, "/api/v1/exports/"+first+"/download", nil, s.access), http.StatusConflict, export.CodeNotReady)
	if _, err := a.store.Size(context.Background(), export.ObjectKey(a.userID(s), uuid.MustParse(first))); !errors.Is(err, storage.ErrNotFound) {
		t.Fatalf("过期文件应已删除：%v", err)
	}
	a.expect(a.createExport(s, []string{"memo"}, false), http.StatusAccepted, "")

	// 已过期的记录可以删除；30 天后自动清除
	a.expect(a.call(http.MethodDelete, "/api/v1/exports/"+first, nil, s.access), http.StatusOK, "")
	a.clock.Advance(31 * 24 * time.Hour)
	if _, err := a.app.Exports.Cleanup(context.Background()); err != nil {
		t.Fatal(err)
	}
	s = a.relogin("export02", "install-a")
	list := a.call(http.MethodGet, "/api/v1/exports", nil, s.access)
	for _, item := range list.Body["data"].([]any) {
		if item.(map[string]any)["status"] == "expired" {
			t.Fatalf("30 天前的过期记录应已清除：%v", item)
		}
	}
}

// flakyStore 上传失败若干次。
type flakyStore struct {
	*storage.Store
	failures int
}

func (f *flakyStore) PutFile(ctx context.Context, key, path, contentType string) error {
	if f.failures > 0 {
		f.failures--
		return errors.New("对象存储不可用")
	}
	return f.Store.PutFile(ctx, key, path, contentType)
}

// noRecords 为没有任何记录的来源。
type noRecords struct{}

func (noRecords) EachRecord(context.Context, uuid.UUID, []string, func(syncer.Snapshot) error) error {
	return nil
}

func TestExportRetriesThenFails(t *testing.T) {
	a := newTestApp(t)
	s := a.register("export03", "secret123", "install-a")
	a.registerPush(s, "token-export-3", true)
	store := &flakyStore{Store: a.store, failures: 3}
	svc := export.NewService(export.Deps{
		Tx: db.NewTxRunner(a.pool), Store: store, Records: noRecords{}, Pusher: a.pushes,
		Logger: a.app.logger, Now: a.clock.Now, TempDir: t.TempDir(),
	})
	tick := func() int {
		n, err := svc.Tick(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		return n
	}
	status := func(id string) map[string]any {
		r := a.call(http.MethodGet, "/api/v1/exports/"+id, nil, s.access)
		a.expect(r, http.StatusOK, "")
		return r.data()
	}

	id := a.createExport(s, []string{"memo"}, false).str("data", "id")
	if tick() != 1 || status(id)["status"] != "pending" {
		t.Fatalf("第一次失败后等待重试：%v", status(id))
	}
	if tick() != 0 {
		t.Fatal("重试间隔未到时不领取")
	}
	a.clock.Advance(2 * time.Minute)
	tick()
	a.clock.Advance(2 * time.Minute)
	tick()
	got := status(id)
	if got["status"] != "failed" || got["error"] == "" || got["attempts"] != nil {
		t.Fatalf("三次失败后标记为失败：%v", got)
	}
	sent := a.pushes.take()
	if len(sent) != 1 || sent[0].Title != "导出失败" {
		t.Fatalf("失败时通知：%+v", sent)
	}

	// 失败后可以重新发起，这次成功
	id2 := a.createExport(s, []string{"memo"}, false).str("data", "id")
	tick()
	if status(id2)["status"] != "done" {
		t.Fatalf("重新导出应成功：%v", status(id2))
	}

	// 生成中崩溃（领取后没有结果）：领取过期后重新领取，超过次数则放弃
	id3 := uuid.Must(uuid.NewV7())
	_, err := a.pool.Exec(context.Background(),
		`INSERT INTO exports (id, user_id, modules, attachments, status, attempts, lease_until, created_at)
		 VALUES ($1, $2, '{memo}', false, 'running', 3, $3, $3)`, id3, a.userID(s), a.clock.Now().Add(-time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	tick()
	if status(id3.String())["status"] != "failed" {
		t.Fatalf("超过尝试次数应失败：%v", status(id3.String()))
	}
}

func (a *testApp) userID(s session) uuid.UUID { return uuid.MustParse(s.userID) }

func (a *testApp) relogin(username, installation string) session {
	a.t.Helper()
	r := a.login(username, "secret123", installation)
	a.expect(r, http.StatusOK, "")
	return sessionFrom(r)
}
