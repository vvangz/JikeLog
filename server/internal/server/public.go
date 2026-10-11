package server

// publicRoutes 为无需登录即可访问的路由（"方法 Gin 路由模式"）。认证默认拒绝：
// 新增接口若未列在这里就必须登录。该表与 openapi.yaml 中标注 security: [] 的接口保持一致，由测试校验。
var publicRoutes = map[string]struct{}{
	"GET /healthz":                     {},
	"HEAD /healthz":                    {},
	"GET /readyz":                      {},
	"HEAD /readyz":                     {},
	"GET /api/v1/system/info":          {},
	"POST /api/v1/auth/register":       {},
	"POST /api/v1/auth/login/password": {},
	"POST /api/v1/auth/sms/send":       {},
	"POST /api/v1/auth/login/sms":      {},
	"POST /api/v1/auth/register/sms":   {},
	"POST /api/v1/auth/refresh":        {},
	"POST /api/v1/auth/password/reset": {},
	// 管理后台：登录、刷新、退出（刷新与退出凭 HttpOnly Cookie 与自定义请求头）
	"POST /api/admin/v1/auth/login":   {},
	"POST /api/admin/v1/auth/refresh": {},
	"POST /api/admin/v1/auth/logout":  {},
}

func isPublicRoute(method, route string) bool {
	_, ok := publicRoutes[method+" "+route]
	return ok
}
