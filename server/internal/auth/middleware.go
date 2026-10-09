package auth

import (
	"context"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

type principalKey struct{}

// WithPrincipal 返回携带调用方身份的 context。
func WithPrincipal(ctx context.Context, p Principal) context.Context {
	return context.WithValue(ctx, principalKey{}, p)
}

// PrincipalFrom 取出调用方身份。
func PrincipalFrom(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(principalKey{}).(Principal)
	return p, ok
}

// MustPrincipal 取出调用方身份；不存在说明路由未经过认证中间件，按未登录处理。
func MustPrincipal(ctx context.Context) (Principal, error) {
	p, ok := PrincipalFrom(ctx)
	if !ok {
		return Principal{}, httpx.Unauthorized("请先登录")
	}
	return p, nil
}

// Middleware 默认要求登录：除 isPublic 返回 true 的路由外，所有已注册路由都必须携带有效令牌。
// 未匹配到路由的请求（404/405）直接放行，交给相应处理器。
func Middleware(svc *Service, isPublic func(method, route string) bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		route := c.FullPath()
		if route == "" || isPublic(c.Request.Method, route) {
			c.Next()
			return
		}
		p, err := svc.Authenticate(c, c.GetHeader("Authorization"))
		if err != nil {
			httpx.WriteError(c, err)
			return
		}
		c.Request = c.Request.WithContext(WithPrincipal(c.Request.Context(), p))
		c.Next()
	}
}
