package server

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/vvangz/JikeLog/server/internal/platform/pusher"
)

// fakePusher 记录推送；fail 非空时返回该错误。
type fakePusher struct {
	mu   sync.Mutex
	sent []pusher.Message
	fail error
}

func (f *fakePusher) Push(_ context.Context, m pusher.Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, m)
	return f.fail
}

func (f *fakePusher) take() []pusher.Message {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := f.sent
	f.sent = nil
	return out
}

// memoChange 构造一条备忘录变更：at 为相对当前时间的偏移。
func (a *testApp) memoChange(c e2eClient, id string, at time.Duration, reminders string, extra map[string]any) map[string]any {
	k := a.hlc(0, nodeA)
	fields := map[string]any{"content": "周会", "at": a.clock.Now().Add(at).UnixMilli(), "allDay": 0, "reminders": reminders, "done": 0}
	for f, v := range extra {
		fields[f] = v
	}
	clocks := map[string]string{}
	for f := range fields {
		clocks[f] = k
	}
	return c.encode(worklogChange{entity: "memo", id: id, fields: fields, clocks: clocks})
}

func (a *testApp) registerPush(s session, token string, local bool) {
	a.t.Helper()
	body := map[string]any{"provider": "jpush", "token": token, "timeZone": "Asia/Shanghai", "localReminders": local}
	a.expect(a.call(http.MethodPut, "/api/v1/me/push", body, s.access), http.StatusOK, "")
}

func (a *testApp) ack(s session, seq int64) {
	a.t.Helper()
	a.expect(a.call(http.MethodPost, "/api/v1/sync/ack", map[string]any{"seq": seq}, s.access), http.StatusOK, "")
}

func (a *testApp) tick() int {
	a.t.Helper()
	n, err := a.app.Reminders.Tick(context.Background())
	if err != nil {
		a.t.Fatal(err)
	}
	return n
}

func (a *testApp) pendingReminders(memo string) int {
	a.t.Helper()
	var n int
	if err := a.pool.QueryRow(context.Background(), "SELECT count(*) FROM memo_reminders WHERE memo_id = $1", memo).Scan(&n); err != nil {
		a.t.Fatal(err)
	}
	return n
}

func TestMemoSyncEncryptsContentOnly(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("memo01")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	id := newID()
	r := a.push(d1, c1, a.memoChange(c1, id, time.Hour, "0,15", nil))
	a.expect(r, http.StatusOK, "")
	if r.results()[0]["status"] != "applied" {
		t.Fatalf("result = %v", r.results()[0])
	}
	var stored string
	if err := a.pool.QueryRow(context.Background(), "SELECT fields::text FROM records WHERE id = $1", id).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(stored, "周会") || !strings.Contains(stored, `"0,15"`) {
		t.Fatalf("内容应加密、提醒为明文：%s", stored)
	}
	rec := a.pull(d2, c2, 0).records()[0]
	f := rec["fields"].(map[string]any)
	content, err := c2.open("memo", id, "content", f["content"].(string))
	if err != nil || content != "周会" || f["reminders"] != "0,15" {
		t.Fatalf("content=%q err=%v fields=%v", content, err, f)
	}
	if a.pendingReminders(id) != 2 {
		t.Fatalf("应排定 2 条提醒，实际 %d", a.pendingReminders(id))
	}

	bad := a.push(d1, c1, a.memoChange(c1, newID(), time.Hour, "15,0", nil))
	if bad.results()[0]["status"] != "rejected" {
		t.Fatalf("未排序的提醒应被拒绝：%v", bad.results()[0])
	}
}

func TestMemoEditsReplaceReminders(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo02")
	c1 := a.handshake(d1)
	id := newID()
	a.push(d1, c1, a.memoChange(c1, id, time.Hour, "0,15,30", nil))
	if a.pendingReminders(id) != 3 {
		t.Fatalf("pending = %d", a.pendingReminders(id))
	}
	// 只有尚未到时的提醒会排定
	a.clock.Advance(time.Millisecond)
	a.push(d1, c1, a.memoChange(c1, id, 20*time.Minute, "0,15,30", nil))
	if a.pendingReminders(id) != 2 {
		t.Fatalf("改期后 pending = %d, want 2", a.pendingReminders(id))
	}
	a.clock.Advance(time.Millisecond)
	a.push(d1, c1, a.memoChange(c1, id, time.Hour, "0", map[string]any{"done": 1}))
	if a.pendingReminders(id) != 0 {
		t.Fatal("完成后不再提醒")
	}
	a.clock.Advance(time.Millisecond)
	a.push(d1, c1, a.memoChange(c1, id, time.Hour, "0", map[string]any{"done": 0}))
	a.clock.Advance(time.Millisecond)
	k := a.hlc(0, nodeA)
	a.push(d1, c1, c1.encode(worklogChange{entity: "memo", id: id, clocks: map[string]string{}, baseClocks: map[string]string{"content": k}, deleted: true}))
	if a.pendingReminders(id) != 0 {
		t.Fatal("删除后不再提醒")
	}
}

func TestReminderPushSkipsDevicesWithLocalAlarm(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("memo03")
	c1 := a.handshake(d1)
	a.registerPush(d1, "reg-d1", true)
	a.registerPush(d2, "reg-d2", true)
	id := newID()
	r := a.push(d1, c1, a.memoChange(c1, id, 30*time.Minute, "0,15", nil))
	seq := num(r.Body["data"].(map[string]any), "cursor")
	a.ack(d1, seq) // d1 已同步，本地闹钟会提醒；d2 尚未同步

	if a.tick() != 0 || len(a.pushes.take()) != 0 {
		t.Fatal("未到时间不应推送")
	}
	a.clock.Advance(15*time.Minute + time.Second)
	if a.tick() != 1 {
		t.Fatal("应处理 1 条到期提醒")
	}
	sent := a.pushes.take()
	if len(sent) != 1 || len(sent[0].Tokens) != 1 || sent[0].Tokens[0] != "reg-d2" {
		t.Fatalf("只应推送给尚未同步的设备：%+v", sent)
	}
	if sent[0].Extras["memoId"] != id || strings.Contains(sent[0].Body, "周会") || !strings.Contains(sent[0].Body, "有一条备忘") {
		t.Fatalf("推送不应包含备忘内容：%+v", sent[0])
	}

	a.ack(d2, seq)
	a.clock.Advance(15 * time.Minute)
	if a.tick() != 1 || len(a.pushes.take()) != 0 {
		t.Fatal("两台设备都已同步时由本地闹钟提醒，不推送")
	}
	if a.pendingReminders(id) != 0 {
		t.Fatal("处理过的提醒应删除")
	}
}

func TestReminderPushesDevicesWithoutLocalAlarm(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo04")
	c1 := a.handshake(d1)
	a.registerPush(d1, "reg-d1", false) // 未授予精确闹钟权限
	r := a.push(d1, c1, a.memoChange(c1, newID(), 10*time.Minute, "0", nil))
	a.ack(d1, num(r.Body["data"].(map[string]any), "cursor"))
	a.clock.Advance(10*time.Minute + time.Second)
	a.tick()
	sent := a.pushes.take()
	if len(sent) != 1 || !strings.Contains(sent[0].Body, "到时间了") {
		t.Fatalf("sent = %+v", sent)
	}
}

func TestReminderRetriesThenGivesUp(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo05")
	c1 := a.handshake(d1)
	a.registerPush(d1, "reg-d1", false)
	id := newID()
	a.push(d1, c1, a.memoChange(c1, id, time.Minute, "0", nil))
	a.pushes.fail = pusher.Retryable(errors.New("temporary"))
	a.clock.Advance(time.Minute + time.Second)
	a.tick()
	if a.pendingReminders(id) != 1 {
		t.Fatal("可重试的失败应保留提醒")
	}
	if a.tick() != 0 {
		t.Fatal("领取期限内不应重复领取")
	}
	for range 2 {
		a.clock.Advance(6 * time.Minute) // 领取期限（5 分钟）过后重试
		a.tick()
	}
	if a.pendingReminders(id) != 0 || len(a.pushes.take()) != 3 {
		t.Fatal("尝试 3 次后放弃")
	}
}

func TestReminderDroppedWhenTooLate(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo06")
	c1 := a.handshake(d1)
	a.registerPush(d1, "reg-d1", false)
	id := newID()
	a.push(d1, c1, a.memoChange(c1, id, time.Minute, "0", nil))
	a.clock.Advance(2 * time.Hour)
	a.tick()
	if len(a.pushes.take()) != 0 || a.pendingReminders(id) != 0 {
		t.Fatal("过时的提醒不再推送")
	}
}

func TestPushRegistration(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("push01")
	other := a.register("pushother", "Passw0rd!", "push01-other")
	token := func(device string) *string {
		var tok *string
		if err := a.pool.QueryRow(context.Background(), "SELECT push_token FROM devices WHERE id = $1", device).Scan(&tok); err != nil {
			t.Fatal(err)
		}
		return tok
	}
	a.registerPush(d1, "reg-shared", true)
	// 其他账号仍在使用的设备上的标识不能抢占
	steal := map[string]any{"provider": "jpush", "token": "reg-shared", "timeZone": "Asia/Shanghai", "localReminders": true}
	a.expect(a.call(http.MethodPut, "/api/v1/me/push", steal, other.access), http.StatusConflict, "PUSH_TOKEN_IN_USE")
	if *token(d1.deviceID) != "reg-shared" {
		t.Fatal("被拒绝的登记不能影响原设备")
	}
	// 同一账号的另一台设备（重装 App）可以接管
	a.registerPush(d2, "reg-shared", true)
	if token(d1.deviceID) != nil || *token(d2.deviceID) != "reg-shared" {
		t.Fatal("同一账号内推送标识应转移到最后登记的设备")
	}
	// 原设备退出登录后（同一部手机换了账号），其他账号可以使用
	a.expect(a.call(http.MethodPost, "/api/v1/auth/logout", nil, d2.access), http.StatusOK, "")
	a.registerPush(other, "reg-shared", true)
	if *token(other.deviceID) != "reg-shared" {
		t.Fatal("原设备下线后标识应可转移")
	}
	a.expect(a.call(http.MethodPut, "/api/v1/me/push", map[string]any{"timeZone": "", "localReminders": true}, d1.access), http.StatusOK, "")

	bad := []map[string]any{
		{"provider": "jpush", "timeZone": "Asia/Shanghai", "localReminders": true},
		{"provider": "jpush", "token": "has space", "timeZone": "Asia/Shanghai", "localReminders": true},
		{"provider": "jpush", "token": "ok", "timeZone": "Mars/Base", "localReminders": true},
		{"provider": "apns", "token": "ok", "timeZone": "Asia/Shanghai", "localReminders": true},
	}
	for _, body := range bad {
		r := a.call(http.MethodPut, "/api/v1/me/push", body, d1.access)
		if r.Status != http.StatusBadRequest && r.Status != http.StatusUnprocessableEntity {
			t.Fatalf("%v: status = %d", body, r.Status)
		}
	}

	// 退出登录后不再向该设备推送
	a.expect(a.call(http.MethodPost, "/api/v1/auth/logout", nil, other.access), http.StatusOK, "")
	if token(other.deviceID) != nil {
		t.Fatal("退出登录应清除推送标识")
	}
}

func TestPushRegistrationRateLimited(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("push02")
	body := map[string]any{"timeZone": "Asia/Shanghai", "localReminders": true}
	for range 30 {
		a.expect(a.call(http.MethodPut, "/api/v1/me/push", body, d1.access), http.StatusOK, "")
	}
	a.expect(a.call(http.MethodPut, "/api/v1/me/push", body, d1.access), http.StatusTooManyRequests, "RATE_LIMITED")
}

func TestReminderPushBeyondLocalHorizon(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo07")
	c1 := a.handshake(d1)
	r := a.push(d1, c1, a.memoChange(c1, newID(), 2*time.Hour, "0", nil))
	a.ack(d1, num(r.Body["data"].(map[string]any), "cursor"))
	// 本地闹钟只覆盖到 1 小时后：2 小时后的提醒仍由服务端推送
	horizon := a.clock.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	body := map[string]any{"provider": "jpush", "token": "reg-d1", "timeZone": "Asia/Shanghai", "localReminders": true, "localUntil": horizon}
	a.expect(a.call(http.MethodPut, "/api/v1/me/push", body, d1.access), http.StatusOK, "")
	a.clock.Advance(2*time.Hour + time.Second)
	a.tick()
	if sent := a.pushes.take(); len(sent) != 1 {
		t.Fatalf("超出本地覆盖范围的提醒应推送：%+v", sent)
	}
}

func TestEditAfterDueKeepsPendingReminder(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo08")
	c1 := a.handshake(d1)
	a.registerPush(d1, "reg-d1", false)
	id := newID()
	a.push(d1, c1, a.memoChange(c1, id, time.Minute, "0,30", nil))
	a.clock.Advance(time.Minute + time.Second) // 到时，但调度器还没来得及发送
	k := a.hlc(0, nodeA)
	a.push(d1, c1, c1.encode(worklogChange{entity: "memo", id: id,
		fields: map[string]any{"content": "改了内容"}, clocks: map[string]string{"content": k}}))
	if a.pendingReminders(id) != 1 {
		t.Fatalf("到时未发的提醒应保留，pending = %d", a.pendingReminders(id))
	}
	a.tick()
	if len(a.pushes.take()) != 1 {
		t.Fatal("保留的提醒应发送")
	}
}

func TestReminderInvalidTokenCleared(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo09")
	c1 := a.handshake(d1)
	a.registerPush(d1, "reg-gone", false)
	a.push(d1, c1, a.memoChange(c1, newID(), time.Minute, "0", nil))
	a.pushes.fail = fmt.Errorf("%w: uninstalled", pusher.ErrNoTarget)
	a.clock.Advance(time.Minute + time.Second)
	a.tick()
	var tok *string
	if err := a.pool.QueryRow(context.Background(), "SELECT push_token FROM devices WHERE id = $1", d1.deviceID).Scan(&tok); err != nil || tok != nil {
		t.Fatalf("失效的推送标识应清除：%v %v", tok, err)
	}
}

func TestReminderDroppedAfterTooManyAttempts(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("memo10")
	c1 := a.handshake(d1)
	a.registerPush(d1, "reg-d1", false)
	id := newID()
	a.push(d1, c1, a.memoChange(c1, id, time.Minute, "0", nil))
	// 模拟此前的尝试中途崩溃，没有记录结果
	if _, err := a.pool.Exec(context.Background(), "UPDATE memo_reminders SET attempts = 3 WHERE memo_id = $1", id); err != nil {
		t.Fatal(err)
	}
	a.clock.Advance(time.Minute + time.Second)
	a.tick()
	if len(a.pushes.take()) != 0 || a.pendingReminders(id) != 0 {
		t.Fatal("超过尝试次数的提醒不再发送")
	}
}
