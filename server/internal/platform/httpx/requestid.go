// Package httpx 提供 HTTP 层公共能力：请求 ID、统一响应信封、错误恢复、访问日志。
package httpx

import (
	"context"
	"regexp"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// HeaderRequestID 为请求 ID 的请求/响应头名称。
const HeaderRequestID = "X-Request-ID"

// requestIDKey 使用字符串键，使 *gin.Context 作为 context.Context 传入严格处理器时也能取到。
const requestIDKey = "jikelog.requestId"

// 仅接受安全字符的外部请求 ID，防止日志注入与响应头污染。
var safeRequestID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// RequestID 为每个请求分配请求 ID：沿用合法的上游 X-Request-ID，否则生成 UUIDv7。
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.GetHeader(HeaderRequestID)
		if !safeRequestID.MatchString(id) {
			id = newRequestID()
		}
		c.Set(requestIDKey, id)
		c.Request = c.Request.WithContext(context.WithValue(c.Request.Context(), requestIDKey, id)) //nolint:staticcheck // 与 gin.Context 共用字符串键
		c.Header(HeaderRequestID, id)
		c.Next()
	}
}

// RequestIDFrom 从 context 中取出请求 ID，不存在时返回空串。
func RequestIDFrom(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	id, _ := ctx.Value(requestIDKey).(string)
	return id
}

func newRequestID() string {
	id, err := uuid.NewV7()
	if err != nil {
		return uuid.NewString()
	}
	return id.String()
}
