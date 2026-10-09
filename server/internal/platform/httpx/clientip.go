package httpx

import (
	"context"

	"github.com/gin-gonic/gin"
)

type clientIPKey struct{}

// ClientIP 把客户端 IP（已按可信代理配置解析）放入请求 context，供业务层做限流与审计，
// 使业务代码不依赖 *gin.Context。
func ClientIP() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Request = c.Request.WithContext(context.WithValue(c.Request.Context(), clientIPKey{}, c.ClientIP()))
		c.Next()
	}
}

// ClientIPFrom 返回请求的客户端 IP，不存在时返回 "unknown"。
func ClientIPFrom(ctx context.Context) string {
	if ip, ok := ctx.Value(clientIPKey{}).(string); ok && ip != "" {
		return ip
	}
	return "unknown"
}

// WithClientIP 返回带客户端 IP 的 context，便于测试。
func WithClientIP(ctx context.Context, ip string) context.Context {
	return context.WithValue(ctx, clientIPKey{}, ip)
}
