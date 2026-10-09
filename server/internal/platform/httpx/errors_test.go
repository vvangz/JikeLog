package httpx

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestWriteError(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tests := []struct {
		name       string
		err        error
		status     int
		code       string
		retryAfter string
	}{
		{"业务错误", NewError(http.StatusConflict, "USERNAME_TAKEN", "用户名已被占用"), 409, "USERNAME_TAKEN", ""},
		{"包装后的业务错误", errors.Join(errors.New("ctx"), Unauthorized("请先登录")), 401, CodeUnauthorized, ""},
		{"限流向上取整", TooManyRequests(CodeRateLimited, "慢点", 1500*time.Millisecond), 429, CodeRateLimited, "2"},
		{"内部错误不泄露", errors.New("pq: password=secret"), 500, CodeInternal, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(rec)
			c.Request = httptest.NewRequest(http.MethodGet, "/", nil)
			isApp := WriteError(c, tt.err)
			if isApp != (tt.status != 500) {
				t.Errorf("WriteError() = %v", isApp)
			}
			if rec.Code != tt.status || rec.Header().Get("Retry-After") != tt.retryAfter {
				t.Errorf("status=%d Retry-After=%q", rec.Code, rec.Header().Get("Retry-After"))
			}
			var env struct {
				Error struct {
					Code    string         `json:"code"`
					Details map[string]any `json:"details"`
				} `json:"error"`
			}
			_ = json.Unmarshal(rec.Body.Bytes(), &env)
			if env.Error.Code != tt.code || strings.Contains(rec.Body.String(), "secret") {
				t.Errorf("body = %s", rec.Body.String())
			}
			if tt.retryAfter != "" && env.Error.Details["retryAfterSeconds"] != float64(2) {
				t.Errorf("details = %v", env.Error.Details)
			}
		})
	}
	if NewError(400, "X", "y").Error() != "X: y" {
		t.Error("Error() 格式不对")
	}
	v := Validation(map[string]string{"a": "b"})
	if v.Status != http.StatusUnprocessableEntity || v.Details["fields"] == nil {
		t.Errorf("Validation = %+v", v)
	}
}

func TestBodyLimit(t *testing.T) {
	r := gin.New()
	r.Use(BodyLimit(10))
	r.POST("/", func(c *gin.Context) {
		var v map[string]any
		if err := c.ShouldBindJSON(&v); err != nil {
			c.Status(http.StatusBadRequest)
			return
		}
		c.Status(http.StatusOK)
	})
	do := func(body string, chunked bool) int {
		req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body))
		if chunked {
			req.ContentLength = -1
		}
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		return rec.Code
	}
	if do(`{"a":1}`, false) != http.StatusOK {
		t.Error("小请求应通过")
	}
	if do(`{"a":"0123456789"}`, false) != http.StatusRequestEntityTooLarge {
		t.Error("声明长度超限应直接返回 413")
	}
	if do(`{"a":"0123456789"}`, true) != http.StatusBadRequest {
		t.Error("未声明长度时读取超限应失败")
	}
}

func TestCORSAndClientIP(t *testing.T) {
	r := gin.New()
	r.ContextWithFallback = true // 与生产路由一致：*gin.Context 取值时回退到请求 context
	r.Use(CORS([]string{"https://admin.example.com"}), ClientIP())
	var ip string
	r.GET("/", func(c *gin.Context) { ip = ClientIPFrom(c); c.Status(http.StatusOK) })

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Origin", "https://admin.example.com")
	req.RemoteAddr = "203.0.113.9:1234"
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	if rec.Header().Get("Access-Control-Allow-Origin") != "https://admin.example.com" ||
		!strings.Contains(rec.Header().Get("Access-Control-Expose-Headers"), HeaderRequestID) {
		t.Errorf("CORS 头 = %v", rec.Header())
	}
	if ip != "203.0.113.9" {
		t.Errorf("ClientIPFrom = %q", ip)
	}
	if ClientIPFrom(context.Background()) != "unknown" || ClientIPFrom(WithClientIP(context.Background(), "1.2.3.4")) != "1.2.3.4" {
		t.Error("ClientIPFrom 回退值不对")
	}
}
