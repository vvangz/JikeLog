package httpx

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func discardLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

type envelope struct {
	Success   bool   `json:"success"`
	RequestID string `json:"requestId"`
	Error     *struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func decode(t *testing.T, rec *httptest.ResponseRecorder) envelope {
	t.Helper()
	var env envelope
	if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
		t.Fatalf("响应不是 JSON 信封: %v, body=%s", err, rec.Body.String())
	}
	return env
}

func newEngine(handlers ...gin.HandlerFunc) *gin.Engine {
	r := gin.New()
	r.Use(RequestID(), Recovery(discardLogger()))
	r.GET("/t", handlers...)
	return r
}

func serve(r http.Handler, req *http.Request) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func TestRequestIDGeneratedWhenMissing(t *testing.T) {
	var seen string
	r := newEngine(func(c *gin.Context) { seen = RequestIDFrom(c); c.Status(http.StatusNoContent) })
	rec := serve(r, httptest.NewRequest(http.MethodGet, "/t", nil))

	got := rec.Header().Get(HeaderRequestID)
	if got == "" || got != seen {
		t.Fatalf("响应头 %q 与上下文 %q 应一致且非空", got, seen)
	}
	if RequestIDFrom(context.Background()) != "" || RequestIDFrom(nil) != "" { //nolint:staticcheck // 验证 nil 安全
		t.Error("无请求 ID 的 context 应返回空串")
	}
}

func TestRequestIDPropagatesValidIncoming(t *testing.T) {
	r := newEngine(func(c *gin.Context) { c.Status(http.StatusNoContent) })
	req := httptest.NewRequest(http.MethodGet, "/t", nil)
	req.Header.Set(HeaderRequestID, "abc-123_XYZ")
	if got := serve(r, req).Header().Get(HeaderRequestID); got != "abc-123_XYZ" {
		t.Errorf("X-Request-ID = %q, want abc-123_XYZ", got)
	}
}

func TestRequestIDReplacesUnsafeIncoming(t *testing.T) {
	r := newEngine(func(c *gin.Context) { c.Status(http.StatusNoContent) })
	for _, bad := range []string{"<script>", strings.Repeat("a", 65), "a b"} {
		req := httptest.NewRequest(http.MethodGet, "/t", nil)
		req.Header.Set(HeaderRequestID, bad)
		if got := serve(r, req).Header().Get(HeaderRequestID); got == bad || got == "" {
			t.Errorf("非法请求 ID %q 应被替换, got %q", bad, got)
		}
	}
}

func TestRecoveryReturnsEnvelope(t *testing.T) {
	r := newEngine(func(*gin.Context) { panic("boom") })
	rec := serve(r, httptest.NewRequest(http.MethodGet, "/t", nil))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	env := decode(t, rec)
	if env.Success || env.Error == nil || env.Error.Code != CodeInternal {
		t.Errorf("envelope = %+v", env)
	}
	if strings.Contains(rec.Body.String(), "boom") {
		t.Error("500 响应不应泄露 panic 内容")
	}
	if env.RequestID == "" {
		t.Error("错误信封应包含 requestId")
	}
}

func TestFailWritesEnvelope(t *testing.T) {
	r := newEngine(func(c *gin.Context) { Fail(c, http.StatusNotFound, CodeNotFound, "资源不存在") })
	rec := serve(r, httptest.NewRequest(http.MethodGet, "/t", nil))
	env := decode(t, rec)
	if rec.Code != http.StatusNotFound || env.Error.Code != CodeNotFound || env.Error.Message != "资源不存在" {
		t.Errorf("status=%d envelope=%+v", rec.Code, env)
	}
}

func TestStrictOptions(t *testing.T) {
	opts := StrictOptions(discardLogger())
	tests := []struct {
		name     string
		call     func(*gin.Context)
		status   int
		code     string
		leakText string
	}{
		{"请求解析失败", func(c *gin.Context) { opts.RequestErrorHandlerFunc(c, errors.New("bad json")) }, 400, CodeBadRequest, ""},
		{"处理器错误", func(c *gin.Context) { opts.HandlerErrorFunc(c, errors.New("db password wrong")) }, 500, CodeInternal, "password"},
		{"响应序列化失败", func(c *gin.Context) { opts.ResponseErrorHandlerFunc(c, errors.New("secret detail")) }, 500, CodeInternal, "secret"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := serve(newEngine(tt.call), httptest.NewRequest(http.MethodGet, "/t", nil))
			env := decode(t, rec)
			if rec.Code != tt.status || env.Error == nil || env.Error.Code != tt.code {
				t.Fatalf("status=%d envelope=%+v", rec.Code, env)
			}
			if tt.leakText != "" && strings.Contains(rec.Body.String(), tt.leakText) {
				t.Errorf("响应泄露内部错误: %s", rec.Body.String())
			}
		})
	}
}

func TestAccessLogWritesRecord(t *testing.T) {
	var sb strings.Builder
	logger := slog.New(slog.NewTextHandler(&sb, nil))
	r := gin.New()
	r.Use(RequestID(), AccessLog(logger))
	r.GET("/t", func(c *gin.Context) { c.Status(http.StatusTeapot) })
	serve(r, httptest.NewRequest(http.MethodGet, "/t?q=1", nil))
	out := sb.String()
	for _, want := range []string{"status=418", "path=/t", "method=GET", "request_id="} {
		if !strings.Contains(out, want) {
			t.Errorf("访问日志缺少 %q: %s", want, out)
		}
	}
	if strings.Contains(out, "q=1") {
		t.Error("访问日志不应记录查询参数（可能含敏感信息）")
	}
}

func TestSecurityHeaders(t *testing.T) {
	r := gin.New()
	r.Use(SecurityHeaders())
	r.GET("/t", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	rec := serve(r, httptest.NewRequest(http.MethodGet, "/t", nil))
	want := map[string]string{
		"X-Content-Type-Options": "nosniff",
		"Cache-Control":          "no-store",
		"X-Frame-Options":        "DENY",
		"Referrer-Policy":        "no-referrer",
	}
	for k, v := range want {
		if got := rec.Header().Get(k); got != v {
			t.Errorf("%s = %q, want %q", k, got, v)
		}
	}
}

func TestRecoveryRepanicsErrAbortHandler(t *testing.T) {
	r := newEngine(func(*gin.Context) { panic(http.ErrAbortHandler) })
	defer func() {
		if rec := recover(); rec != http.ErrAbortHandler { //nolint:errorlint // 需比较哨兵值本身
			t.Fatalf("recover() = %v, want http.ErrAbortHandler", rec)
		}
	}()
	serve(r, httptest.NewRequest(http.MethodGet, "/t", nil))
	t.Fatal("ErrAbortHandler 应继续向上 panic，由 net/http 中止连接")
}
