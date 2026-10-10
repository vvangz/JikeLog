package server

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/storage"
	"github.com/vvangz/JikeLog/server/internal/testinfra"
)

// testClock 为可手动推进的时钟，同时推进 miniredis 的过期时间。
type testClock struct {
	mu  sync.Mutex
	now time.Time
	mr  *miniredis.Miniredis
}

func (c *testClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *testClock) Advance(d time.Duration) {
	c.mu.Lock()
	c.now = c.now.Add(d)
	c.mu.Unlock()
	c.mr.FastForward(d)
}

// testApp 为连接真实 PostgreSQL、对象存储与 miniredis 的完整服务。
type testApp struct {
	t     *testing.T
	h     http.Handler
	app   *App
	pool  *pgxpool.Pool
	store *storage.Store
	sms   *auth.MockSender
	mr    *miniredis.Miniredis
	clock *testClock
	// pushes 记录发出的推送
	pushes *fakePusher
	// ip 为请求来源地址，可修改以模拟不同客户端
	ip string
}

func newTestApp(t *testing.T) *testApp {
	t.Helper()
	pool := testinfra.Postgres(t)
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	clk := &testClock{now: time.Now(), mr: mr}
	cfg := testConfig(t, map[string]string{
		"JIKELOG_HTTP_CORS_ORIGINS": "http://localhost:5173",
		// 便于测试配额：单个附件 64KB，总量 100KB
		"JIKELOG_ATTACHMENT_MAX_SIZE": "65536", "JIKELOG_ATTACHMENT_QUOTA": "102400",
	})
	store, err := storage.New(testinfra.ObjectStore(t))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.EnsureBucket(context.Background()); err != nil {
		t.Fatal(err)
	}
	pushes := &fakePusher{}
	app, err := NewApp(context.Background(), Options{
		Name: "jikelog-api", Config: cfg, Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Pool: pool, Redis: rdb, Store: store, Argon2: &auth.Argon2Params{MemoryKiB: 64, Time: 1, Threads: 1}, Now: clk.Now,
		Pusher: pushes,
	})
	if err != nil {
		t.Fatal(err)
	}
	return &testApp{
		t: t, h: app.Handler, app: app, pool: pool, store: store,
		sms: app.SMS.(*auth.MockSender), mr: mr, clock: clk, pushes: pushes, ip: "198.51.100.1",
	}
}

type apiResp struct {
	Status int
	Header http.Header
	Body   map[string]any
}

func (r apiResp) code() string {
	e, _ := r.Body["error"].(map[string]any)
	c, _ := e["code"].(string)
	return c
}

func (r apiResp) data() map[string]any {
	d, _ := r.Body["data"].(map[string]any)
	return d
}

func (r apiResp) str(path ...string) string {
	var cur any = r.Body
	for _, p := range path {
		m, _ := cur.(map[string]any)
		cur = m[p]
	}
	s, _ := cur.(string)
	return s
}

func (a *testApp) call(method, path string, body any, token string) apiResp {
	a.t.Helper()
	return a.callWith(method, path, body, token, nil)
}

// callWith 与 call 相同，并附加请求头。
func (a *testApp) callWith(method, path string, body any, token string, headers map[string]string) apiResp {
	a.t.Helper()
	var rd io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			a.t.Fatal(err)
		}
		rd = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, rd)
	req.RemoteAddr = a.ip + ":40000"
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	a.h.ServeHTTP(rec, req)
	out := apiResp{Status: rec.Code, Header: rec.Header()}
	if rec.Body.Len() > 0 {
		if err := json.Unmarshal(rec.Body.Bytes(), &out.Body); err != nil {
			a.t.Fatalf("%s %s 响应不是 JSON: %s", method, path, rec.Body.String())
		}
	}
	return out
}

// expect 断言状态码（以及可选的错误码），失败时打印响应体。
func (a *testApp) expect(r apiResp, status int, code string) {
	a.t.Helper()
	if r.Status != status || (code != "" && r.code() != code) {
		a.t.Fatalf("status = %d code = %q, want %d %q; body = %v", r.Status, r.code(), status, code, r.Body)
	}
}

func device(installation string) map[string]any {
	return map[string]any{"installationId": installation, "platform": "android", "model": "Pixel 9", "osVersion": "Android 16", "appVersion": "0.2.0"}
}

type session struct {
	userID, deviceID, access, refresh string
}

func sessionFrom(r apiResp) session {
	d := r.data()
	if s, ok := d["session"].(map[string]any); ok { // 短信登录结果
		d = s
	}
	user, _ := d["user"].(map[string]any)
	tokens, _ := d["tokens"].(map[string]any)
	str := func(m map[string]any, k string) string { s, _ := m[k].(string); return s }
	return session{userID: str(user, "id"), deviceID: str(d, "deviceId"), access: str(tokens, "accessToken"), refresh: str(tokens, "refreshToken")}
}

// register 注册一个账号并返回会话。
func (a *testApp) register(username, password, installation string) session {
	a.t.Helper()
	r := a.call(http.MethodPost, "/api/v1/auth/register", map[string]any{
		"username": username, "password": password, "device": device(installation),
	}, "")
	a.expect(r, http.StatusCreated, "")
	return sessionFrom(r)
}

func (a *testApp) login(username, password, installation string) apiResp {
	a.t.Helper()
	return a.call(http.MethodPost, "/api/v1/auth/login/password", map[string]any{
		"username": username, "password": password, "device": device(installation),
	}, "")
}

// sendSMS 请求验证码并返回模拟通道收到的验证码。
func (a *testApp) sendSMS(phone, purpose, token string) string {
	a.t.Helper()
	path, body := "/api/v1/auth/sms/send", map[string]any{"phone": phone, "purpose": purpose}
	if token != "" {
		path = "/api/v1/me/sms/send"
	}
	a.expect(a.call(http.MethodPost, path, body, token), http.StatusOK, "")
	a.clock.Advance(auth.SMSCooldown) // 越过冷却期，便于后续测试再次发送
	return a.sms.LastCode(e164(phone))
}

func e164(phone string) string { return "+86" + strings.TrimPrefix(phone, "+86") }

// bindPhone 为已登录账号（密码为 secret123）绑定手机号。
func (a *testApp) bindPhone(token, phone string) {
	a.t.Helper()
	code := a.sendSMS(phone, "bind_phone", token)
	a.expect(a.call(http.MethodPut, "/api/v1/me/phone", map[string]any{"phone": phone, "code": code, "currentPassword": "secret123"}, token), http.StatusOK, "")
}
