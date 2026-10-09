package server

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/vvangz/JikeLog/server/internal/e2e"
)

// twoDevices 注册一个账号，并在两台设备上登录。
func (a *testApp) twoDevices(username string) (session, session) {
	a.t.Helper()
	s1 := a.register(username, "secret123", "install-a")
	r := a.login(username, "secret123", "install-b")
	a.expect(r, http.StatusOK, "")
	return s1, sessionFrom(r)
}

func TestSyncPushPullAcrossDevices(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("syncer01")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	id := newID()
	clk := a.hlc(0, nodeA)
	r := a.push(d1, c1, c1.encode(worklogChange{
		id:     id,
		fields: map[string]any{"date": "2026-10-09", "location": "公司", "content": "上午：周会。\n下午：写代码。"},
		clocks: map[string]string{"date": clk, "location": clk, "content": clk},
	}))
	a.expect(r, http.StatusOK, "")
	res := r.results()[0]
	if res["status"] != "applied" || num(res, "version") != 1 || num(res, "serverSeq") != 1 || num(r.data(), "cursor") != 1 {
		t.Fatalf("push=%v", r.data())
	}

	// 落库为密文：数据库中查不到明文
	var raw string
	if err := a.pool.QueryRow(context.Background(), "SELECT fields::text FROM records WHERE id = $1", id).Scan(&raw); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(raw, "周会") || strings.Contains(raw, "公司") || !strings.Contains(raw, "2026-10-09") {
		t.Fatalf("敏感字段应加密落库，日期保持明文：%s", raw)
	}

	p := a.pull(d2, c2, 0)
	a.expect(p, http.StatusOK, "")
	recs := p.records()
	if len(recs) != 1 || p.data()["hasMore"] != false || num(p.data(), "nextSince") != 1 {
		t.Fatalf("pull=%v", p.data())
	}
	fields := recs[0]["fields"].(map[string]any)
	content, err := c2.open("worklog", id, "content", fields["content"].(string))
	if err != nil || content != "上午：周会。\n下午：写代码。" || fields["date"] != "2026-10-09" {
		t.Fatalf("另一台设备应能用自己的会话解密：%q err=%v fields=%v", content, err, fields)
	}
	if _, err := c1.open("worklog", id, "content", fields["content"].(string)); err == nil {
		t.Fatal("下发的密文只能用拉取方自己的会话解开")
	}
	if p := a.pull(d2, c2, 1); len(p.records()) != 0 {
		t.Fatal("since=1 之后没有新记录")
	}
}

func TestSyncMergesConcurrentTextEdits(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("syncer02")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	id := newID()
	base := a.hlc(0, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{
		id: id, fields: map[string]any{"date": "2026-10-09", "content": "上午：周会。\n下午：写代码。"},
		clocks: map[string]string{"date": base, "content": base},
	})), http.StatusOK, "")

	// 设备一改第二行
	k1 := a.hlc(1, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{
		id: id, fields: map[string]any{"content": "上午：周会。\n下午：写代码和评审。"},
		clocks: map[string]string{"content": k1}, baseClocks: map[string]string{"content": base},
	})), http.StatusOK, "")

	// 设备二基于旧版本改第一行，带补丁
	k2 := a.hlc(2, nodeB)
	r := a.push(d2, c2, c2.encode(worklogChange{
		id: id, fields: map[string]any{"content": "上午：周会，定排期。\n下午：写代码。"},
		clocks: map[string]string{"content": k2}, baseClocks: map[string]string{"content": base},
		patches: map[string]string{"content": patchJSON(map[string]any{"p": 5, "b": "上午：周会", "d": "", "i": "，定排期", "a": "。\n下午"})},
	}))
	a.expect(r, http.StatusOK, "")
	res := r.results()[0]
	if res["status"] != "merged" {
		t.Fatalf("应合并：%v", res)
	}
	rec := res["record"].(map[string]any)
	merged, err := c2.open("worklog", id, "content", rec["fields"].(map[string]any)["content"].(string))
	if err != nil || merged != "上午：周会，定排期。\n下午：写代码和评审。" {
		t.Fatalf("merged=%q err=%v", merged, err)
	}

	// 重试同一推送：幂等，不会重复插入
	again := a.push(d2, c2, c2.encode(worklogChange{
		id: id, fields: map[string]any{"content": "上午：周会，定排期。\n下午：写代码。"},
		clocks: map[string]string{"content": k2}, baseClocks: map[string]string{"content": base},
		patches: map[string]string{"content": patchJSON(map[string]any{"p": 5, "b": "上午：周会", "d": "", "i": "，定排期", "a": "。\n下午"})},
	}))
	if res := again.results()[0]; res["status"] != "applied" || num(res, "version") != num(rec, "version") {
		t.Fatalf("重试应为空操作：%v", res)
	}
}

func TestSyncConflictKeepsLoserInRevisions(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("syncer03")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	id := newID()
	base := a.hlc(0, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{
		id: id, fields: map[string]any{"date": "2026-10-09", "location": "公司"},
		clocks: map[string]string{"date": base, "location": base},
	})), http.StatusOK, "")
	newer := a.hlc(5, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{
		id: id, fields: map[string]any{"location": "客户现场"},
		clocks: map[string]string{"location": newer}, baseClocks: map[string]string{"location": base},
	})), http.StatusOK, "")
	older := a.hlc(3, nodeB)
	r := a.push(d2, c2, c2.encode(worklogChange{
		id: id, fields: map[string]any{"location": "家"},
		clocks: map[string]string{"location": older}, baseClocks: map[string]string{"location": base},
	}))
	res := r.results()[0]
	if res["status"] != "conflict" {
		t.Fatalf("应为冲突：%v", res)
	}
	loc, _ := c2.open("worklog", id, "location", res["record"].(map[string]any)["fields"].(map[string]any)["location"].(string))
	if loc != "客户现场" {
		t.Fatalf("修改更晚的一方胜出，得到 %q", loc)
	}

	list := a.call(http.MethodGet, "/api/v1/records/"+id+"/revisions", nil, d2.access)
	a.expect(list, http.StatusOK, "")
	items, _ := list.Body["data"].([]any)
	var conflictID string
	for _, it := range items {
		m := it.(map[string]any)
		if m["reason"] == "conflict" {
			conflictID = m["id"].(string)
		}
	}
	if conflictID == "" {
		t.Fatalf("修订历史中应有冲突版本：%v", items)
	}
	rev := a.callWith(http.MethodGet, "/api/v1/revisions/"+conflictID, nil, d2.access, c2.headers())
	a.expect(rev, http.StatusOK, "")
	lost, err := c2.open("worklog", id, "location", rev.data()["fields"].(map[string]any)["location"].(string))
	if err != nil || lost != "家" {
		t.Fatalf("冲突版本应保存落败的修改：%q err=%v", lost, err)
	}

	// 其他账号看不到这条记录的修订
	other := a.register("syncer03b", "secret123", "install-c")
	a.expect(a.call(http.MethodGet, "/api/v1/records/"+id+"/revisions", nil, other.access), http.StatusNotFound, "RECORD_NOT_FOUND")
	a.expect(a.callWith(http.MethodGet, "/api/v1/revisions/"+conflictID, nil, other.access, a.handshake(other).headers()), http.StatusNotFound, "REVISION_NOT_FOUND")
}

func TestSyncDeleteProducesTombstone(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("syncer04")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	id := newID()
	k := a.hlc(0, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{
		id: id, fields: map[string]any{"date": "2026-10-09", "content": "要删除的日志"}, clocks: map[string]string{"date": k, "content": k},
	})), http.StatusOK, "")
	a.expect(a.push(d1, c1, map[string]any{"entity": "worklog", "id": id, "deleted": true}), http.StatusOK, "")
	recs := a.pull(d2, c2, 0).records()
	if len(recs) != 1 || recs[0]["deleted"] != true || len(recs[0]["fields"].(map[string]any)) != 0 {
		t.Fatalf("应只下发墓碑且不含字段：%v", recs)
	}
	// 删除前的内容进入修订历史
	list := a.call(http.MethodGet, "/api/v1/records/"+id+"/revisions", nil, d2.access)
	items, _ := list.Body["data"].([]any)
	if len(items) == 0 || items[0].(map[string]any)["reason"] != "delete" {
		t.Fatalf("应保存删除前的版本：%v", items)
	}
}

func TestSyncRequiresE2ESessionForSensitiveFields(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("syncer05")
	c1 := a.handshake(d1)
	id := newID()
	k := a.hlc(0, nodeA)
	change := c1.encode(worklogChange{id: id, fields: map[string]any{"date": "2026-10-09", "content": "x"}, clocks: map[string]string{"date": k, "content": k}})

	a.expect(a.call(http.MethodPost, "/api/v1/sync/push", map[string]any{"changes": []any{change}}, d1.access), http.StatusConflict, e2e.CodeSessionInvalid)
	// 其他设备拿到会话 ID 也用不了
	a.expect(a.push(d2, c1, change), http.StatusConflict, e2e.CodeSessionInvalid)
	a.expect(a.push(d1, c1, change), http.StatusOK, "")
	a.expect(a.call(http.MethodGet, "/api/v1/sync/pull?since=0", nil, d2.access), http.StatusConflict, e2e.CodeSessionInvalid)

	// 明文的敏感字段被拒绝
	plain := map[string]any{"entity": "worklog", "id": newID(), "fields": map[string]any{"date": "2026-10-09", "content": 123}, "clocks": map[string]string{"date": k, "content": k}}
	if res := a.push(d1, c1, plain).results()[0]; res["status"] != "rejected" {
		t.Fatalf("应拒绝：%v", res)
	}
	// 用错误的 AAD（挪到其他记录）加密的内容被拒绝
	moved := c1.encode(worklogChange{id: newID(), fields: map[string]any{"date": "2026-10-09"}, clocks: map[string]string{"date": k}})
	moved["fields"].(map[string]any)["content"] = c1.seal("worklog", id, "content", e2e.KindValue, "挪用的密文")
	moved["clocks"].(map[string]string)["content"] = k
	res := a.push(d1, c1, moved).results()[0]
	if res["status"] != "rejected" || res["error"].(map[string]any)["code"] != "E2E_DECRYPT_FAILED" {
		t.Fatalf("应拒绝挪用的密文：%v", res)
	}
}

func TestSyncRejectsInvalidChangesIndividually(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("syncer06")
	c1 := a.handshake(d1)
	k := a.hlc(0, nodeA)
	good := c1.encode(worklogChange{id: newID(), fields: map[string]any{"date": "2026-10-09"}, clocks: map[string]string{"date": k}})
	unknown := map[string]any{"entity": "diary", "id": newID(), "fields": map[string]any{}, "clocks": map[string]string{}}
	skewed := c1.encode(worklogChange{id: newID(), fields: map[string]any{"date": "2026-10-09"}, clocks: map[string]string{"date": a.hlc(10*60*1000, nodeA)}})
	missingDate := c1.encode(worklogChange{id: newID(), fields: map[string]any{"content": "无日期"}, clocks: map[string]string{"content": k}})
	r := a.push(d1, c1, good, unknown, skewed, missingDate)
	a.expect(r, http.StatusOK, "")
	want := []struct{ status, code string }{{"applied", ""}, {"rejected", "UNKNOWN_ENTITY"}, {"rejected", "CLOCK_SKEW"}, {"rejected", "VALIDATION_FAILED"}}
	for i, res := range r.results() {
		code := ""
		if e, ok := res["error"].(map[string]any); ok {
			code, _ = e["code"].(string)
		}
		if res["status"] != want[i].status || code != want[i].code {
			t.Errorf("第 %d 条：%v，期望 %v", i, res, want[i])
		}
	}
	if num(r.data(), "cursor") != 1 {
		t.Fatalf("只有一条被采纳：%v", r.data())
	}

	// 超过单批上限
	many := make([]map[string]any, 101)
	for i := range many {
		many[i] = good
	}
	a.expect(a.push(d1, c1, many...), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
}

func TestSyncIDCollisionAcrossAccounts(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("syncer07")
	other := a.register("syncer07b", "secret123", "install-c")
	c1, co := a.handshake(d1), a.handshake(other)
	id := newID()
	k := a.hlc(0, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{id: id, fields: map[string]any{"date": "2026-10-09"}, clocks: map[string]string{"date": k}})), http.StatusOK, "")
	res := a.push(other, co, co.encode(worklogChange{id: id, fields: map[string]any{"date": "2026-10-10"}, clocks: map[string]string{"date": a.hlc(1, nodeB)}})).results()[0]
	if res["status"] != "rejected" || res["error"].(map[string]any)["code"] != "ID_CONFLICT" {
		t.Fatalf("不能写入其他账号的记录：%v", res)
	}
	if recs := a.pull(other, co, 0).records(); len(recs) != 0 {
		t.Fatalf("其他账号不应拉到：%v", recs)
	}
}

func TestSyncAck(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("syncer08")
	c1 := a.handshake(d1)
	k := a.hlc(0, nodeA)
	a.expect(a.push(d1, c1, c1.encode(worklogChange{id: newID(), fields: map[string]any{"date": "2026-10-09"}, clocks: map[string]string{"date": k}})), http.StatusOK, "")
	a.expect(a.call(http.MethodPost, "/api/v1/sync/ack", map[string]any{"seq": 2}, d1.access), http.StatusUnprocessableEntity, "ACK_AHEAD_OF_SERVER")
	a.expect(a.call(http.MethodPost, "/api/v1/sync/ack", map[string]any{"seq": 1}, d1.access), http.StatusOK, "")
	var acked int64
	if err := a.pool.QueryRow(context.Background(), "SELECT last_ack_seq FROM devices WHERE id = $1", d1.deviceID).Scan(&acked); err != nil || acked != 1 {
		t.Fatalf("acked=%d err=%v", acked, err)
	}
	// 回退的确认不会降低已记录的序号
	a.expect(a.call(http.MethodPost, "/api/v1/sync/ack", map[string]any{"seq": 0}, d1.access), http.StatusOK, "")
	_ = a.pool.QueryRow(context.Background(), "SELECT last_ack_seq FROM devices WHERE id = $1", d1.deviceID).Scan(&acked)
	if acked != 1 {
		t.Fatalf("acked=%d", acked)
	}
}
