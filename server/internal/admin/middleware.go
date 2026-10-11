package admin

import (
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// RoutePrefix 为管理接口的路由前缀。
const RoutePrefix = "/api/admin/"

// IsAdminRoute 报告路由是否为管理接口。
func IsAdminRoute(route string) bool { return strings.HasPrefix(route, RoutePrefix) }

// passwordChangeRoutes 为必须修改初始密码时仍可访问的接口。
var passwordChangeRoutes = map[string]bool{
	"GET /api/admin/v1/me":          true,
	"PUT /api/admin/v1/me/password": true,
}

// Middleware 校验管理接口的管理员令牌（isPublic 返回 true 的路由除外）。必须修改初始密码的管理员
// 只能查看自己、修改密码或退出。
func Middleware(svc *Service, isPublic func(method, route string) bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		route := c.FullPath()
		if isPublic(c.Request.Method, route) {
			c.Next()
			return
		}
		p, err := svc.Authenticate(c.Request.Context(), c.GetHeader("Authorization"))
		if err != nil {
			httpx.WriteError(c, err)
			return
		}
		if p.MustChangePassword && !passwordChangeRoutes[c.Request.Method+" "+route] {
			httpx.WriteError(c, errPasswordChange)
			return
		}
		c.Request = c.Request.WithContext(WithPrincipal(c.Request.Context(), p))
		c.Next()
	}
}

// ErrAdminOnUserRoute 为管理员令牌访问用户接口时的错误：管理员看不到任何用户内容。
var ErrAdminOnUserRoute = httpx.NewError(403, CodeForbidden, "管理员账号不能访问用户数据")
