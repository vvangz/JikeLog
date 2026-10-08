package server

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/system"
)

func testRouter(t *testing.T) http.Handler {
	t.Helper()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	cfg, err := config.LoadFrom(map[string]string{"JIKELOG_ENV": "test"})
	if err != nil {
		t.Fatal(err)
	}
	api := NewAPI(system.NewHandler(system.Config{Name: "jikelog-api", Logger: logger}))
	r, err := NewRouter(cfg, logger, api)
	if err != nil {
		t.Fatal(err)
	}
	return r
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
	cfg, _ := config.LoadFrom(map[string]string{"JIKELOG_ENV": "test"})
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
	if _, err := NewRouter(cfg, logger, NewAPI(system.NewHandler(system.Config{}))); err == nil {
		t.Fatal("非法代理地址应返回错误")
	}
}

func TestListenAndServe(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	cfg, _ := config.LoadFrom(map[string]string{"JIKELOG_HTTP_ADDR": "127.0.0.1:0"})

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
	cfg, _ := config.LoadFrom(map[string]string{})
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	if err := Serve(context.Background(), ln, http.NotFoundHandler(), cfg.HTTP, logger); err == nil {
		t.Fatal("监听器已关闭时 Serve 应返回错误")
	}
}

func TestNewHTTPServerLimitsHeaderSize(t *testing.T) {
	cfg, _ := config.LoadFrom(map[string]string{})
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
	cfg, _ := config.LoadFrom(map[string]string{})
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	r, err := NewRouter(cfg, logger, NewAPI(system.NewHandler(system.Config{})))
	if err != nil {
		t.Fatal(err)
	}
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
