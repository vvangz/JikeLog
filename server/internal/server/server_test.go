package server

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"maps"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/system"
)

// testConfig 返回通过校验的测试配置，extra 覆盖默认值。
func testConfig(t *testing.T, extra map[string]string) config.Config {
	t.Helper()
	env := map[string]string{
		"JIKELOG_ENV":             "test",
		"JIKELOG_DB_URL":          "postgres://u:p@127.0.0.1:5432/db",
		"JIKELOG_REDIS_URL":       "redis://127.0.0.1:6379/0",
		"JIKELOG_AUTH_JWT_SECRET": "test-secret-test-secret-test-secret",
	}
	maps.Copy(env, extra)
	cfg, err := config.LoadFrom(env)
	if err != nil {
		t.Fatal(err)
	}
	return cfg
}

// testAuthService 返回只用于认证中间件的 auth.Service（不访问数据库）。
func testAuthService(t *testing.T, cfg config.Config) *auth.Service {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	svc, err := auth.NewService(context.Background(), auth.Deps{
		Hasher:  auth.NewHasher(auth.Argon2Params{MemoryKiB: 64, Time: 1, Threads: 1}),
		Tokens:  auth.NewTokenManager(cfg.Auth.JWTSecret, "", cfg.Auth.AccessTTL, nil),
		Revoked: auth.NewRevocations(rdb, cfg.Auth.AccessTTL),
	})
	if err != nil {
		t.Fatal(err)
	}
	return svc
}

// newBareRouter 只挂载系统接口，用于不依赖数据库的路由层测试。
func newBareRouter(t *testing.T, cfg config.Config) *gin.Engine {
	t.Helper()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	api := NewAPI(Handlers{System: system.NewHandler(system.Config{Name: "jikelog-api", Logger: logger})})
	r, err := NewRouter(cfg, logger, api, testAuthService(t, cfg))
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func testRouter(t *testing.T) http.Handler {
	t.Helper()
	return newBareRouter(t, testConfig(t, nil))
}

func TestRoutes(t *testing.T) {
	r := testRouter(t)
	tests := []struct {
		method, path string
		status       int
		code         string
	}{
		{http.MethodGet, "/healthz", 200, ""},
		{http.MethodGet, "/readyz", 200, ""},
		{http.MethodGet, "/api/v1/system/info", 200, ""},
		{http.MethodGet, "/api/v1/nope", 404, httpx.CodeNotFound},
		{http.MethodPost, "/healthz", 405, httpx.CodeMethodNotAllowed},
	}
	for _, tt := range tests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			rec := httptest.NewRecorder()
			r.ServeHTTP(rec, httptest.NewRequest(tt.method, tt.path, nil))
			if rec.Code != tt.status {
				t.Fatalf("status = %d, want %d, body=%s", rec.Code, tt.status, rec.Body.String())
			}
			if rec.Header().Get(httpx.HeaderRequestID) == "" {
				t.Error("缺少 X-Request-ID 响应头")
			}
			if rec.Header().Get("X-Content-Type-Options") != "nosniff" {
				t.Error("缺少安全响应头")
			}
			var env struct {
				Success   bool                   `json:"success"`
				RequestID string                 `json:"requestId"`
				Error     *struct{ Code string } `json:"error"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
				t.Fatalf("响应不是 JSON 信封: %v", err)
			}
			if env.RequestID != rec.Header().Get(httpx.HeaderRequestID) {
				t.Errorf("信封 requestId=%q 与响应头不一致", env.RequestID)
			}
			if tt.code != "" && (env.Error == nil || env.Error.Code != tt.code) {
				t.Errorf("error = %+v, want code %s", env.Error, tt.code)
			}
		})
	}
}

func TestServeShutsDownGracefully(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	cfg := testConfig(t, nil)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Serve(ctx, ln, testRouter(t), cfg.HTTP, slog.New(slog.NewTextHandler(io.Discard, nil)))
	}()

	resp, err := http.Get("http://" + ln.Addr().String() + "/healthz")
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", resp.StatusCode)
	}

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Serve() error = %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Serve() 未在 5s 内退出")
	}
}

func TestNewRouterRejectsInvalidTrustedProxy(t *testing.T) {
	// 绕过配置校验直接构造，验证路由层的兜底检查
	cfg := config.Config{HTTP: config.HTTP{TrustedProxies: []string{"not-an-ip"}}}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	if _, err := NewRouter(cfg, logger, NewAPI(Handlers{System: system.NewHandler(system.Config{})}), nil); err == nil {
		t.Fatal("非法代理地址应返回错误")
	}
}

func TestListenAndServe(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	cfg := testConfig(t, map[string]string{"JIKELOG_HTTP_ADDR": "127.0.0.1:0"})

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := ListenAndServe(ctx, http.NotFoundHandler(), cfg.HTTP, logger); err != nil {
		t.Fatalf("ListenAndServe() error = %v", err)
	}

	bad := cfg.HTTP
	bad.Addr = "256.0.0.1:99999"
	if err := ListenAndServe(context.Background(), http.NotFoundHandler(), bad, logger); err == nil {
		t.Fatal("非法监听地址应返回错误")
	}
}

func TestServeReturnsErrorWhenListenerFails(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	_ = ln.Close()
	cfg := testConfig(t, nil)
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	if err := Serve(context.Background(), ln, http.NotFoundHandler(), cfg.HTTP, logger); err == nil {
		t.Fatal("监听器已关闭时 Serve 应返回错误")
	}
}

func TestNewHTTPServerLimitsHeaderSize(t *testing.T) {
	cfg := testConfig(t, nil)
	srv := newHTTPServer(http.NotFoundHandler(), cfg.HTTP, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if srv.MaxHeaderBytes != maxHeaderBytes || maxHeaderBytes > 64<<10 {
		t.Errorf("MaxHeaderBytes = %d, want %d (≤64KB)", srv.MaxHeaderBytes, maxHeaderBytes)
	}
	if srv.ReadHeaderTimeout <= 0 || srv.ReadHeaderTimeout > cfg.HTTP.ReadTimeout {
		t.Errorf("ReadHeaderTimeout = %v", srv.ReadHeaderTimeout)
	}
}

func TestHealthProbesSupportHEAD(t *testing.T) {
	r := testRouter(t)
	for _, path := range []string{"/healthz", "/readyz"} {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodHead, path, nil))
		if rec.Code != http.StatusOK {
			t.Errorf("HEAD %s = %d, want 200（阿里云 CLB 健康检查默认使用 HEAD）", path, rec.Code)
		}
	}
}

func TestRequestCancellationReachesHandlers(t *testing.T) {
	r := newBareRouter(t, testConfig(t, nil))
	publicRoutes["GET /probe-ctx"] = struct{}{} // 测试专用路由，跳过认证
	t.Cleanup(func() { delete(publicRoutes, "GET /probe-ctx") })
	var handlerErr error
	r.GET("/probe-ctx", func(c *gin.Context) {
		var ctx context.Context = c
		handlerErr = ctx.Err()
		c.Status(http.StatusNoContent)
	})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	r.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/probe-ctx", nil).WithContext(ctx))
	if !errors.Is(handlerErr, context.Canceled) {
		t.Fatalf("处理器 ctx.Err() = %v，请求取消未传递到处理器", handlerErr)
	}
}
