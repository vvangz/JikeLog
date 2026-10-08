package httpx

import (
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
			logger.InfoContext(c, "bad request", "request_id", RequestIDFrom(c), "error", err)
			Fail(c, http.StatusBadRequest, CodeBadRequest, MsgBadRequest)
		},
		HandlerErrorFunc:         internal("handler error"),
		ResponseErrorHandlerFunc: internal("response error"),
	}
}
