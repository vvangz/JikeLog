package server

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/platform/storage"
	"github.com/vvangz/JikeLog/server/internal/realtime"
)

// newWorklog 推送一条工作日志并返回其 ID。
func (a *testApp) newWorklog(s session, c e2eClient) string {
	a.t.Helper()
	id := newID()
	k := a.hlc(0, nodeA)
	a.expect(a.push(s, c, c.encode(worklogChange{id: id, fields: map[string]any{"date": "2026-10-09"}, clocks: map[string]string{"date": k}})), http.StatusOK, "")
	return id
}

func (a *testApp) requestUpload(s session, c e2eClient, owner, id, name string, body []byte) apiResp {
	a.t.Helper()
	sum := sha256.Sum256(body)
	return a.callWith(http.MethodPost, "/api/v1/attachments", map[string]any{
		"id": id, "ownerEntity": "worklog", "ownerId": owner,
		"fileName": c.seal("attachment", id, "fileName", e2e.KindValue, name),
		"mime":     "text/plain", "size": len(body), "sha256": hex.EncodeToString(sum[:]),
	}, s.access, c.headers())
}

func upload(t *testing.T, r apiResp, body []byte) int {
	t.Helper()
	d := r.data()
	req, err := http.NewRequest(http.MethodPut, d["uploadUrl"].(string), bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	for k, v := range d["headers"].(map[string]any) {
		req.Header.Set(k, v.(string))
	}
	req.ContentLength = int64(len(body))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode
}

func TestAttachmentUploadCompleteDownload(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("attach01")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	owner := a.newWorklog(d1, c1)
	id := newID()
	body := []byte("会议纪要 minutes")

	// 上传前确认完成：尚未上传
	r := a.requestUpload(d1, c1, owner, id, "会议纪要.txt", body)
	a.expect(r, http.StatusCreated, "")
	a.expect(a.call(http.MethodPost, "/api/v1/attachments/"+id+"/complete", nil, d1.access), http.StatusConflict, "UPLOAD_INCOMPLETE")
	// 重复申请是幂等的
	a.expect(a.requestUpload(d1, c1, owner, id, "会议纪要.txt", body), http.StatusCreated, "")
	if code := upload(t, r, body); code != http.StatusOK {
		t.Fatalf("上传失败：%d", code)
	}
	done := a.call(http.MethodPost, "/api/v1/attachments/"+id+"/complete", nil, d1.access)
	a.expect(done, http.StatusOK, "")
	seq := num(done.data(), "serverSeq")
	again := a.call(http.MethodPost, "/api/v1/attachments/"+id+"/complete", nil, d1.access)
	if num(again.data(), "serverSeq") != seq {
		t.Fatalf("重复确认应幂等：%v", again.data())
	}

	// 另一台设备拉到 attachment 记录，文件名用自己的会话解开
	var att map[string]any
	for _, rec := range a.pull(d2, c2, 0).records() {
		if rec["entity"] == "attachment" {
			att = rec
		}
	}
	if att == nil {
		t.Fatal("应拉到附件记录")
	}
	f := att["fields"].(map[string]any)
	name, err := c2.open("attachment", id, "fileName", f["fileName"].(string))
	if err != nil || name != "会议纪要.txt" || f["ownerId"] != owner || num(f, "size") != int64(len(body)) {
		t.Fatalf("附件记录不符：name=%q err=%v fields=%v", name, err, f)
	}

	dl := a.call(http.MethodGet, "/api/v1/attachments/"+id+"/download", nil, d2.access)
	a.expect(dl, http.StatusOK, "")
	resp, err := http.Get(dl.data()["url"].(string))
	if err != nil {
		t.Fatal(err)
	}
	got, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if !bytes.Equal(got, body) {
		t.Fatalf("下载内容不符：%q", got)
	}
	usage := a.call(http.MethodGet, "/api/v1/attachments/usage", nil, d1.access)
	if num(usage.data(), "used") != int64(len(body)) || num(usage.data(), "maxSize") != 65536 {
		t.Fatalf("usage=%v", usage.data())
	}

	// 客户端删除附件记录后，后台清理会删除对象
	a.expect(a.push(d1, c1, map[string]any{"entity": "attachment", "id": id, "deleted": true}), http.StatusOK, "")
	a.expect(a.call(http.MethodGet, "/api/v1/attachments/"+id+"/download", nil, d1.access), http.StatusNotFound, "ATTACHMENT_NOT_FOUND")
	if n, err := a.app.attachments.Cleanup(context.Background(), 10); err != nil || n != 1 {
		t.Fatalf("cleanup n=%d err=%v", n, err)
	}
	if _, err := a.store.Size(context.Background(), "u/"+d1.userID+"/"+id); !errors.Is(err, storage.ErrNotFound) {
		t.Fatalf("对象应已删除：%v", err)
	}
}

func TestAttachmentValidationAndQuota(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("attach02")
	c1 := a.handshake(d1)
	owner := a.newWorklog(d1, c1)

	a.expect(a.requestUpload(d1, c1, newID(), newID(), "a.txt", []byte("x")), http.StatusNotFound, "OWNER_NOT_FOUND")
	a.expect(a.requestUpload(d1, c1, owner, newID(), "../etc/passwd", []byte("x")), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(a.requestUpload(d1, c1, owner, newID(), "big.bin", make([]byte, 65537)), http.StatusRequestEntityTooLarge, "ATTACHMENT_TOO_LARGE")
	// 文件名必须加密传输
	a.expect(a.call(http.MethodPost, "/api/v1/attachments", map[string]any{
		"id": newID(), "ownerEntity": "worklog", "ownerId": owner, "fileName": "plain", "mime": "text/plain", "size": 1, "sha256": strings.Repeat("a", 64),
	}, d1.access), http.StatusConflict, e2e.CodeSessionInvalid)
	// 未完成上传的申请也计入配额（64KB + 64KB > 100KB）
	a.expect(a.requestUpload(d1, c1, owner, newID(), "1.bin", make([]byte, 65536)), http.StatusCreated, "")
	a.expect(a.requestUpload(d1, c1, owner, newID(), "2.bin", make([]byte, 65536)), http.StatusRequestEntityTooLarge, "QUOTA_EXCEEDED")
	// 客户端不能伪造附件记录
	k := a.hlc(0, nodeA)
	res := a.push(d1, c1, map[string]any{"entity": "attachment", "id": newID(), "fields": map[string]any{"size": 1}, "clocks": map[string]string{"size": k}}).results()[0]
	if res["status"] != "rejected" {
		t.Fatalf("应拒绝：%v", res)
	}
}

func TestDeleteAccountRemovesObjects(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("attach03")
	c1 := a.handshake(d1)
	owner := a.newWorklog(d1, c1)
	id := newID()
	body := []byte("x")
	r := a.requestUpload(d1, c1, owner, id, "a.txt", body)
	a.expect(r, http.StatusCreated, "")
	if code := upload(t, r, body); code != http.StatusOK {
		t.Fatalf("上传失败：%d", code)
	}
	a.expect(a.call(http.MethodPost, "/api/v1/me/deletion", map[string]any{"currentPassword": "secret123"}, d1.access), http.StatusOK, "")
	if _, err := a.store.Size(context.Background(), "u/"+d1.userID+"/"+id); !errors.Is(err, storage.ErrNotFound) {
		t.Fatalf("注销后对象应被删除：%v", err)
	}
	var n int
	_ = a.pool.QueryRow(context.Background(), "SELECT count(*) FROM records").Scan(&n)
	if n != 0 {
		t.Fatalf("注销后记录应随账号删除：%d", n)
	}
}

func TestWebSocketNotifiesOtherDevices(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("realtime01")
	c1 := a.handshake(d1)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go a.app.RunBackground(ctx)
	waitSub := time.Now().Add(3 * time.Second)
	for a.mr.PubSubNumPat() == 0 && time.Now().Before(waitSub) {
		time.Sleep(10 * time.Millisecond)
	}
	srv := httptest.NewServer(a.h)
	t.Cleanup(srv.Close)

	// dial 连接并返回升级失败时的状态码
	dial := func(token string) (*websocket.Conn, int, error) {
		dctx, dcancel := context.WithTimeout(ctx, 3*time.Second)
		defer dcancel()
		conn, resp, err := websocket.Dial(dctx, "ws"+strings.TrimPrefix(srv.URL, "http")+"/api/v1/sync/ws",
			&websocket.DialOptions{HTTPHeader: http.Header{"Authorization": {"Bearer " + token}}})
		status := 0
		if resp != nil {
			status = resp.StatusCode
			if resp.Body != nil {
				_ = resp.Body.Close()
			}
		}
		return conn, status, err
	}
	if _, status, err := dial("bad-token"); err == nil || status != http.StatusUnauthorized {
		t.Fatalf("未登录不能连接：%v", err)
	}
	conn, _, err := dial(d2.access)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.CloseNow() })
	read := func() realtime.Event {
		rctx, rcancel := context.WithTimeout(ctx, 3*time.Second)
		defer rcancel()
		var ev realtime.Event
		if err := wsjson.Read(rctx, conn, &ev); err != nil {
			t.Fatal(err)
		}
		return ev
	}
	if ev := read(); ev.Type != realtime.EventHello || ev.Seq != 0 {
		t.Fatalf("hello=%+v", ev)
	}
	a.newWorklog(d1, c1)
	ev := read()
	if ev.Type != realtime.EventChanged || ev.Seq != 1 || ev.Origin == nil || ev.Origin.String() != d1.deviceID {
		t.Fatalf("changed=%+v", ev)
	}
}
