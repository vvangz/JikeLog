package httpx

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/apigen"
)

// SecurityHeaders 为所有 API 响应添加安全头：禁止 MIME 嗅探、禁止缓存、禁止被嵌入页面、不发送 Referer。
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Cache-Control", "no-store")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		c.Next()
	}
}

// Recovery 捕获 panic，记录堆栈并返回 500 信封，不向客户端泄露内部信息。
func Recovery(logger *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if r := recover(); r != nil {
				if r == http.ErrAbortHandler { //nolint:errorlint // 哨兵值比较
					panic(r) // 交给 net/http 中止连接，不视为错误
				}
				logger.ErrorContext(c, "panic recovered",
					"request_id", RequestIDFrom(c), "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
				Fail(c, http.StatusInternalServerError, CodeInternal, MsgInternal)
			}
		}()
		c.Next()
	}
}

// AccessLog 记录访问日志。只记录路径不记录查询串，避免手机号、验证码等敏感参数落盘。
func AccessLog(logger *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		status := c.Writer.Status()
		level := slog.LevelInfo
		if status >= http.StatusInternalServerError {
			level = slog.LevelError
		}
		logger.Log(c, level, "http request",
			"method", c.Request.Method,
			"path", c.Request.URL.Path,
			"status", status,
			"latency_ms", time.Since(start).Milliseconds(),
			"bytes", c.Writer.Size(),
			"client_ip", c.ClientIP(),
			"request_id", RequestIDFrom(c),
		)
	}
}

// StrictOptions 让生成的严格处理器在出错时也返回统一信封。
func StrictOptions(logger *slog.Logger) apigen.StrictGinServerOptions {
	internal := func(kind string) func(*gin.Context, error) {
		return func(c *gin.Context, err error) {
			logger.ErrorContext(c, kind, "request_id", RequestIDFrom(c), "error", err)
			Fail(c, http.StatusInternalServerError, CodeInternal, MsgInternal)
		}
	}
	return apigen.StrictGinServerOptions{
		RequestErrorHandlerFunc: func(c *gin.Context, err error) {
			if errors.As(err, new(*http.MaxBytesError)) {
				Fail(c, http.StatusRequestEntityTooLarge, CodePayloadTooLarge, MsgPayloadTooLarge)
				return
			}
			logger.InfoContext(c, "bad request", "request_id", RequestIDFrom(c), "error", err)
			Fail(c, http.StatusBadRequest, CodeBadRequest, MsgBadRequest)
		},
		HandlerErrorFunc: func(c *gin.Context, err error) {
			if !WriteError(c, err) {
				logger.ErrorContext(c, "handler error", "request_id", RequestIDFrom(c), "error", err)
			}
		},
		ResponseErrorHandlerFunc: internal("response error"),
	}
}

// BodyLimit 限制请求体大小，超出时解析请求体会失败并返回 413。
// overrides 为个别路由（Gin 路由模式）的单独上限，如批量推送接口。
func BodyLimit(defaultMax int64, overrides map[string]int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		maxBytes := defaultMax
		if v, ok := overrides[c.FullPath()]; ok {
			maxBytes = v
		}
		if c.Request.ContentLength > maxBytes {
			Fail(c, http.StatusRequestEntityTooLarge, CodePayloadTooLarge, MsgPayloadTooLarge)
			return
		}
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		c.Next()
	}
}

// CORS 只对白名单中的来源返回跨域头；预检请求直接以 204 响应。白名单为空时不做任何处理。
func CORS(origins []string) gin.HandlerFunc {
	allowed := make(map[string]struct{}, len(origins))
	for _, o := range origins {
		allowed[o] = struct{}{}
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if _, ok := allowed[origin]; !ok || origin == "" {
			c.Next()
			return
		}
		h := c.Writer.Header()
		h.Set("Access-Control-Allow-Origin", origin)
		h.Add("Vary", "Origin")
		h.Set("Access-Control-Expose-Headers", HeaderRequestID+", Retry-After")
		if c.Request.Method == http.MethodOptions && c.GetHeader("Access-Control-Request-Method") != "" {
			h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE")
			h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type, "+HeaderRequestID)
			h.Set("Access-Control-Max-Age", "600")
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

// RequestContext 返回请求本身的 context。生成的处理器以 *gin.Context 作为 context 传入，
// 而 gin.Context 会在处理器返回后被复用；凡是可能派生出后台协程的调用（如对外 HTTP 请求），
// 都必须改用请求的 context，否则会与下一个请求产生数据竞争。
func RequestContext(ctx context.Context) context.Context {
	if c, ok := ctx.(*gin.Context); ok && c.Request != nil {
		return c.Request.Context()
	}
	return ctx
}
