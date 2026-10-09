package realtime

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

type checker struct{ err atomic.Pointer[error] }

func (c *checker) CheckSession(context.Context, auth.Principal) error {
	if p := c.err.Load(); p != nil {
		return *p
	}
	return nil
}

type fixture struct {
	hub   *Hub
	srv   *httptest.Server
	user  uuid.UUID
	check *checker
	mr    *miniredis.Miniredis
}

func newFixture(t *testing.T, opts Options) *fixture {
	t.Helper()
	gin.SetMode(gin.TestMode)
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	hub := NewHub(rdb, slog.New(slog.NewTextHandler(io.Discard, nil)))
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go hub.Run(ctx)
	f := &fixture{hub: hub, user: uuid.New(), check: &checker{}, mr: mr}
	opts.Check = f.check
	opts.Cursor = func(context.Context, uuid.UUID) (int64, error) { return 7, nil }
	r := gin.New()
	r.GET("/ws", func(c *gin.Context) {
		p := auth.Principal{UserID: f.user, DeviceID: uuid.New()}
		c.Request = c.Request.WithContext(auth.WithPrincipal(c.Request.Context(), p))
	}, hub.Handler(opts))
	f.srv = httptest.NewServer(r)
	t.Cleanup(f.srv.Close)
	// 等订阅建立，避免发布早于订阅
	waitFor(t, func() bool { return mr.PubSubNumPat() > 0 })
	return f
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("等待超时")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func (f *fixture) dial(t *testing.T) *websocket.Conn {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, resp, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(f.srv.URL, "http")+"/ws", nil)
	if resp != nil && resp.Body != nil {
		_ = resp.Body.Close()
	}
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.CloseNow() })
	return conn
}

func read(t *testing.T, conn *websocket.Conn) Event {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var ev Event
	if err := wsjson.Read(ctx, conn, &ev); err != nil {
		t.Fatal(err)
	}
	return ev
}

func TestHelloAndChangedNotification(t *testing.T) {
	f := newFixture(t, Options{})
	conn := f.dial(t)
	if ev := read(t, conn); ev.Type != EventHello || ev.Seq != 7 {
		t.Fatalf("hello=%+v", ev)
	}
	waitFor(t, func() bool { f.hub.mu.RLock(); defer f.hub.mu.RUnlock(); return len(f.hub.conns[f.user]) == 1 })
	origin := uuid.New()
	f.hub.Publish(context.Background(), f.user, 9, origin)
	ev := read(t, conn)
	if ev.Type != EventChanged || ev.Seq != 9 || ev.Origin == nil || *ev.Origin != origin {
		t.Fatalf("changed=%+v", ev)
	}
	// 其他账号的通知不会送达
	f.hub.Publish(context.Background(), uuid.New(), 10, origin)
	f.hub.Publish(context.Background(), f.user, 11, origin)
	if ev := read(t, conn); ev.Seq != 11 {
		t.Fatalf("应只收到本账号的通知：%+v", ev)
	}
}

func TestSubscriberCoalesces(t *testing.T) {
	s := newSubscriber()
	s.notify(message{Seq: 3})
	s.notify(message{Seq: 5})
	s.notify(message{Seq: 4}) // 迟到的旧序号不覆盖新的
	m, ok := s.take()
	if !ok || m.Seq != 5 {
		t.Fatalf("m=%+v", m)
	}
	if _, ok := s.take(); ok {
		t.Fatal("取出后应为空")
	}
}

func TestRevokedSessionClosesConnection(t *testing.T) {
	f := newFixture(t, Options{CheckInterval: 50 * time.Millisecond})
	conn := f.dial(t)
	read(t, conn)
	// 数据库暂时不可用时保持连接
	unavailable := error(httpx.NewError(http.StatusServiceUnavailable, httpx.CodeUnavailable, "x"))
	f.check.err.Store(&unavailable)
	time.Sleep(150 * time.Millisecond)
	revokedErr := error(httpx.Unauthorized("设备已下线"))
	f.check.err.Store(&revokedErr)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, _, err := conn.Read(ctx)
	if websocket.CloseStatus(err) != CloseSessionRevoked {
		t.Fatalf("应以 4401 关闭，err=%v", err)
	}
}

func TestTooManyConnections(t *testing.T) {
	f := newFixture(t, Options{})
	for range maxConnsPerUser {
		read(t, f.dial(t))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, resp, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(f.srv.URL, "http")+"/ws", nil)
	if resp != nil && resp.Body != nil {
		_ = resp.Body.Close()
	}
	if err == nil || resp == nil || resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("超过连接上限应返回 429，err=%v", err)
	}
}

func TestShutdownClosesWithGoingAway(t *testing.T) {
	f := newFixture(t, Options{})
	conn := f.dial(t)
	read(t, conn)
	f.hub.Shutdown()
	f.hub.Shutdown() // 可重复调用
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, _, err := conn.Read(ctx)
	if websocket.CloseStatus(err) != websocket.StatusGoingAway {
		t.Fatalf("应以 1001 关闭，err=%v", err)
	}
}

func TestCursorErrorRejectsUpgrade(t *testing.T) {
	gin.SetMode(gin.TestMode)
	hub := NewHub(redis.NewClient(&redis.Options{Addr: "127.0.0.1:0"}), slog.New(slog.NewTextHandler(io.Discard, nil)))
	r := gin.New()
	r.GET("/ws", func(c *gin.Context) {
		c.Request = c.Request.WithContext(auth.WithPrincipal(c.Request.Context(), auth.Principal{UserID: uuid.New()}))
	}, hub.Handler(Options{Check: &checker{}, Cursor: func(context.Context, uuid.UUID) (int64, error) {
		return 0, errors.New("db down")
	}}))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/ws", nil))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("code=%d", w.Code)
	}
	// 未经认证中间件时按未登录处理
	r2 := gin.New()
	r2.GET("/ws", hub.Handler(Options{Check: &checker{}, Cursor: nil}))
	w = httptest.NewRecorder()
	r2.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/ws", nil))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("code=%d", w.Code)
	}
}

func TestPublishFailureIsLogged(t *testing.T) {
	hub := NewHub(redis.NewClient(&redis.Options{Addr: "127.0.0.1:1", MaxRetries: -1, DialTimeout: 100 * time.Millisecond}),
		slog.New(slog.NewTextHandler(io.Discard, nil)))
	hub.Publish(context.Background(), uuid.New(), 1, uuid.New()) // 不应 panic 或阻塞
	hub.dispatch("jk:sync:user:not-a-uuid", "{}")
	hub.dispatch("jk:sync:user:"+uuid.NewString(), "not json")
}
