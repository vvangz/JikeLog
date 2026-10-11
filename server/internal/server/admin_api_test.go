package server

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/admin"
)

const adminPassword = "Admin12345"

// adminSession 为管理员登录结果：Access Token 与 Refresh Cookie。
type adminSession struct {
	token, cookie string
}

// createAdmin 直接创建管理员（等同于命令行 jikelog-admin create）。
func (a *testApp) createAdmin(username, role string) {
	a.t.Helper()
	if _, err := a.app.Admins.CreateAdmin(context.Background(), nil, username, role, adminPassword, admin.Meta{}); err != nil {
		a.t.Fatal(err)
	}
}

func refreshCookie(r apiResp) string {
	for _, c := range r.Header.Values("Set-Cookie") {
		if strings.HasPrefix(c, admin.RefreshCookie+"=") {
			return strings.SplitN(c, ";", 2)[0]
		}
	}
	return ""
}

func (a *testApp) adminLogin(username, password string) apiResp {
	a.t.Helper()
	return a.call(http.MethodPost, "/api/admin/v1/auth/login", map[string]any{"username": username, "password": password}, "")
}

func (a *testApp) adminSignIn(username, password string) adminSession {
	a.t.Helper()
	r := a.adminLogin(username, password)
	a.expect(r, http.StatusOK, "")
	return adminSession{token: r.str("data", "accessToken"), cookie: refreshCookie(r)}
}

func (a *testApp) adminCall(method, path string, body any, s adminSession) apiResp {
	a.t.Helper()
	return a.call(method, path, body, s.token)
}

// adminCookieCall 调用刷新与退出接口：带 Cookie 与防跨站请求头。
func (a *testApp) adminCookieCall(path, cookie string, csrf bool) apiResp {
	a.t.Helper()
	h := map[string]string{"Cookie": cookie}
	if csrf {
		h["X-JikeLog-Admin"] = "1"
	}
	return a.callWith(http.MethodPost, path, nil, "", h)
}

func TestAdminLoginSessionAndLockout(t *testing.T) {
	a := newTestApp(t)
	a.createAdmin("root01", admin.RoleSuperAdmin)

	r := a.adminLogin("root01", adminPassword)
	a.expect(r, http.StatusOK, "")
	if r.str("data", "admin", "role") != "super_admin" || r.data()["admin"].(map[string]any)["mustChangePassword"] != false {
		t.Fatalf("登录结果：%v", r.data())
	}
	setCookie := strings.Join(r.Header.Values("Set-Cookie"), "\n")
	for _, attr := range []string{"HttpOnly", "SameSite=Strict", "Path=/api/admin/v1/auth"} {
		if !strings.Contains(setCookie, attr) {
			t.Fatalf("Refresh Cookie 应包含 %s：%s", attr, setCookie)
		}
	}
	s := adminSession{token: r.str("data", "accessToken"), cookie: refreshCookie(r)}
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/me", nil, s), http.StatusOK, "")

	// 刷新：必须带防跨站请求头；Refresh Token 轮换，旧的不再可用
	a.expect(a.adminCookieCall("/api/admin/v1/auth/refresh", s.cookie, false), http.StatusBadRequest, "")
	r2 := a.adminCookieCall("/api/admin/v1/auth/refresh", s.cookie, true)
	a.expect(r2, http.StatusOK, "")
	next := refreshCookie(r2)
	if next == "" || next == s.cookie {
		t.Fatal("刷新后应轮换 Refresh Token")
	}
	a.expect(a.adminCookieCall("/api/admin/v1/auth/refresh", s.cookie, true), http.StatusUnauthorized, "UNAUTHORIZED")

	// 退出后 Access Token 与 Refresh Token 都失效
	out := a.adminCookieCall("/api/admin/v1/auth/logout", next, true)
	a.expect(out, http.StatusOK, "")
	if !strings.Contains(strings.Join(out.Header.Values("Set-Cookie"), ""), "Max-Age=0") {
		t.Fatal("退出时应删除 Cookie")
	}
	a.expect(a.call(http.MethodGet, "/api/admin/v1/me", nil, r2.str("data", "accessToken")), http.StatusUnauthorized, "UNAUTHORIZED")
	a.expect(a.adminCookieCall("/api/admin/v1/auth/refresh", next, true), http.StatusUnauthorized, "UNAUTHORIZED")

	// 用户名不存在与密码错误的提示相同；连续 5 次失败锁定 15 分钟
	a.expect(a.adminLogin("nobody", adminPassword), http.StatusUnauthorized, admin.CodeInvalidCredentials)
	for i := 0; i < 4; i++ {
		a.expect(a.adminLogin("root01", "wrong-password-1"), http.StatusUnauthorized, admin.CodeInvalidCredentials)
	}
	a.expect(a.adminLogin("root01", "wrong-password-1"), http.StatusLocked, admin.CodeLocked)
	a.expect(a.adminLogin("root01", adminPassword), http.StatusLocked, admin.CodeLocked)
	a.clock.Advance(16 * time.Minute)
	a.expect(a.adminLogin("root01", adminPassword), http.StatusOK, "")

	// 同一 IP 15 分钟内最多尝试 20 次
	a.ip = "198.51.100.77"
	for i := 0; i < 20; i++ {
		a.adminLogin("nobody", adminPassword)
	}
	a.expect(a.adminLogin("root01", adminPassword), http.StatusTooManyRequests, "RATE_LIMITED")
}

func TestAdminTokenCannotReachUserRoutes(t *testing.T) {
	a := newTestApp(t)
	a.createAdmin("root02", admin.RoleSuperAdmin)
	s := a.adminSignIn("root02", adminPassword)
	user := a.register("plainuser", "secret123", "install-a")

	// 逐一检查所有用户接口：管理员令牌一律 403
	param := regexp.MustCompile(`:[A-Za-z]+`)
	checked := 0
	for _, rt := range a.h.(*gin.Engine).Routes() {
		if admin.IsAdminRoute(rt.Path) || isPublicRoute(rt.Method, rt.Path) || rt.Method == http.MethodHead {
			continue
		}
		path := param.ReplaceAllString(rt.Path, "0192a000-0000-7000-8000-000000000001")
		r := a.call(rt.Method, path, map[string]any{}, s.token)
		if r.Status != http.StatusForbidden || r.code() != admin.CodeForbidden {
			t.Errorf("%s %s 应拒绝管理员令牌：%d %v", rt.Method, rt.Path, r.Status, r.Body)
		}
		checked++
	}
	if checked < 25 {
		t.Fatalf("检查的用户接口太少：%d", checked)
	}

	// 用户令牌不能访问管理接口
	a.expect(a.call(http.MethodGet, "/api/admin/v1/dashboard", nil, user.access), http.StatusUnauthorized, "UNAUTHORIZED")
	a.expect(a.call(http.MethodGet, "/api/admin/v1/users", nil, ""), http.StatusUnauthorized, "UNAUTHORIZED")
}

func TestAdminDashboardUsersAndAudit(t *testing.T) {
	a := newTestApp(t)
	a.createAdmin("root03", admin.RoleSuperAdmin)
	s := a.adminSignIn("root03", adminPassword)
	u1 := a.register("alice01", "secret123", "install-a")
	a.bindPhone(u1.access, "13812345678")
	a.register("bob0001", "secret123", "install-b")
	a.expect(a.call(http.MethodPut, "/api/v1/me/settings", map[string]any{
		"themeMode": "dark", "fontScale": 1.2, "defaultReminders": []int{15, 0}, "weekStart": 7,
	}, u1.access), http.StatusOK, "")
	c1 := a.handshake(u1)
	a.newWorklog(u1, c1)

	d := a.adminCall(http.MethodGet, "/api/admin/v1/dashboard", nil, s)
	a.expect(d, http.StatusOK, "")
	data := d.data()
	if num(data, "totalUsers") != 2 || num(data, "newUsersToday") != 2 || num(data, "activeToday") != 2 {
		t.Fatalf("仪表盘：%v", data)
	}
	daily := data["newUsersDaily"].([]any)
	if len(daily) != 30 || num(daily[29].(map[string]any), "count") != 2 {
		t.Fatalf("新增趋势：%v", daily)
	}
	if p := data["platforms"].([]any); len(p) != 1 || p[0].(map[string]any)["platform"] != "android" {
		t.Fatalf("平台分布：%v", p)
	}

	list := a.adminCall(http.MethodGet, "/api/admin/v1/users?q=5678&pageSize=1", nil, s)
	a.expect(list, http.StatusOK, "")
	users := list.Body["data"].([]any)
	if len(users) != 1 || users[0].(map[string]any)["username"] != "alice01" ||
		users[0].(map[string]any)["phoneMasked"] != "+86 138****5678" {
		t.Fatalf("按手机号末尾搜索：%v", users)
	}
	if num(list.Body["meta"].(map[string]any), "total") != 1 {
		t.Fatalf("分页：%v", list.Body["meta"])
	}
	all := a.adminCall(http.MethodGet, "/api/admin/v1/users?q=%25", nil, s)
	if n := len(all.Body["data"].([]any)); n != 0 {
		t.Fatalf("通配符按字面匹配：%d", n)
	}

	detail := a.adminCall(http.MethodGet, "/api/admin/v1/users/"+u1.userID, nil, s)
	a.expect(detail, http.StatusOK, "")
	dd := detail.data()
	st := dd["settings"].(map[string]any)
	if st["themeMode"] != "dark" || num(st, "weekStart") != 7 {
		t.Fatalf("设置：%v", st)
	}
	dev := dd["devices"].([]any)[0].(map[string]any)
	if dev["model"] != "Pixel 9" || dev["signedIn"] != true {
		t.Fatalf("设备：%v", dev)
	}
	if num(dd["sync"].(map[string]any), "serverSeq") < 1 || dd["sync"].(map[string]any)["lastSyncAt"] == nil {
		t.Fatalf("同步状态：%v", dd["sync"])
	}
	raw, _ := json.Marshal(dd)
	for _, leak := range []string{"13812345678", "content", "location", "pushToken", "lastIp", "secret"} {
		if strings.Contains(string(raw), leak) {
			t.Fatalf("用户详情不应包含 %q：%s", leak, raw)
		}
	}
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/users/0192a000-0000-7000-8000-00000000ffff", nil, s), http.StatusNotFound, admin.CodeNotFound)

	// 审计日志：登录、查看仪表盘、列表与详情都有记录，可按操作筛选
	logs := a.adminCall(http.MethodGet, "/api/admin/v1/audit-logs?action=view_user", nil, s)
	a.expect(logs, http.StatusOK, "")
	items := logs.Body["data"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["targetId"] != u1.userID || items[0].(map[string]any)["username"] != "root03" {
		t.Fatalf("查看用户的审计：%v", items)
	}
	all = a.adminCall(http.MethodGet, "/api/admin/v1/audit-logs?pageSize=100", nil, s)
	actions := map[string]int{}
	for _, it := range all.Body["data"].([]any) {
		actions[it.(map[string]any)["action"].(string)]++
	}
	if actions["login"] != 1 || actions["view_dashboard"] != 1 || actions["list_users"] != 2 || actions["view_user"] != 1 {
		t.Fatalf("审计操作：%v", actions)
	}
	future := a.clock.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	if n := len(a.adminCall(http.MethodGet, "/api/admin/v1/audit-logs?from="+future, nil, s).Body["data"].([]any)); n != 0 {
		t.Fatalf("按时间筛选：%d", n)
	}
}

func TestAdminAccountManagement(t *testing.T) {
	a := newTestApp(t)
	a.createAdmin("root04", admin.RoleSuperAdmin)
	root := a.adminSignIn("root04", adminPassword)

	// 新建只读管理员：用户名重复、弱密码被拒绝
	a.expect(a.adminCall(http.MethodPost, "/api/admin/v1/admins", map[string]any{"username": "root04", "role": "viewer", "password": "Viewer12345"}, root), http.StatusConflict, admin.CodeUsernameTaken)
	a.expect(a.adminCall(http.MethodPost, "/api/admin/v1/admins", map[string]any{"username": "viewer1", "role": "viewer", "password": "onlyletters"}, root), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	created := a.adminCall(http.MethodPost, "/api/admin/v1/admins", map[string]any{"username": "viewer1", "role": "viewer", "password": "Viewer12345"}, root)
	a.expect(created, http.StatusCreated, "")
	viewerID := created.str("data", "id")

	// 第一次登录必须先改密码
	v := a.adminSignIn("viewer1", "Viewer12345")
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/dashboard", nil, v), http.StatusForbidden, admin.CodePasswordChange)
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/me", nil, v), http.StatusOK, "")
	a.expect(a.adminCall(http.MethodPut, "/api/admin/v1/me/password", map[string]any{"currentPassword": "wrong", "newPassword": "Viewer67890"}, v), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(a.adminCall(http.MethodPut, "/api/admin/v1/me/password", map[string]any{"currentPassword": "Viewer12345", "newPassword": "Viewer67890"}, v), http.StatusOK, "")
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/dashboard", nil, v), http.StatusOK, "")

	// 只读管理员不能管理管理员
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/admins", nil, v), http.StatusForbidden, admin.CodeForbidden)
	a.expect(a.adminCall(http.MethodPost, "/api/admin/v1/admins", map[string]any{"username": "viewer2", "role": "viewer", "password": "Viewer12345"}, v), http.StatusForbidden, admin.CodeForbidden)

	// 不能修改自己；不能停用最后一个超级管理员
	a.expect(a.adminCall(http.MethodPatch, "/api/admin/v1/admins/"+a.adminID(root), map[string]any{"disabled": true}, root), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	promoted := a.adminCall(http.MethodPatch, "/api/admin/v1/admins/"+viewerID, map[string]any{"role": "super_admin"}, root)
	a.expect(promoted, http.StatusOK, "")
	v = a.adminSignIn("viewer1", "Viewer67890")
	a.expect(a.adminCall(http.MethodPatch, "/api/admin/v1/admins/"+a.adminID(root), map[string]any{"role": "viewer"}, v), http.StatusOK, "")
	a.expect(a.adminCall(http.MethodPatch, "/api/admin/v1/admins/"+viewerID, map[string]any{"disabled": true}, root), http.StatusForbidden, admin.CodeForbidden)
	a.expect(a.adminCall(http.MethodPatch, "/api/admin/v1/admins/"+a.adminID(root), map[string]any{"role": "super_admin"}, v), http.StatusOK, "")
	root = a.adminSignIn("root04", adminPassword)

	// 停用后会话立即失效、不能登录
	a.expect(a.adminCall(http.MethodPatch, "/api/admin/v1/admins/"+viewerID, map[string]any{"disabled": true}, root), http.StatusOK, "")
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/me", nil, v), http.StatusUnauthorized, "UNAUTHORIZED")
	a.expect(a.adminLogin("viewer1", "Viewer67890"), http.StatusForbidden, admin.CodeDisabled)

	// 重置密码：对方会话失效，下次登录必须改密码
	a.expect(a.adminCall(http.MethodPatch, "/api/admin/v1/admins/"+viewerID, map[string]any{"disabled": false}, root), http.StatusOK, "")
	v = a.adminSignIn("viewer1", "Viewer67890")
	a.expect(a.adminCall(http.MethodPost, "/api/admin/v1/admins/"+viewerID+"/password", map[string]any{"password": "Reset123456"}, root), http.StatusOK, "")
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/me", nil, v), http.StatusUnauthorized, "UNAUTHORIZED")
	again := a.adminLogin("viewer1", "Reset123456")
	a.expect(again, http.StatusOK, "")
	if again.data()["admin"].(map[string]any)["mustChangePassword"] != true {
		t.Fatal("被重置密码后必须修改密码")
	}
	a.expect(a.adminCall(http.MethodPost, "/api/admin/v1/admins/"+a.adminID(root)+"/password", map[string]any{"password": "Reset123456"}, root), http.StatusUnprocessableEntity, "VALIDATION_FAILED")

	list := a.adminCall(http.MethodGet, "/api/admin/v1/admins", nil, root)
	if n := len(list.Body["data"].([]any)); n != 2 {
		t.Fatalf("管理员列表：%d", n)
	}
	logs := a.adminCall(http.MethodGet, "/api/admin/v1/audit-logs?action=update_admin", nil, root)
	if n := len(logs.Body["data"].([]any)); n != 5 {
		t.Fatalf("修改管理员的审计：%d", n)
	}

	// 修改自己的密码：其他会话失效，当前会话保留
	other := a.adminSignIn("root04", adminPassword)
	a.expect(a.adminCall(http.MethodPut, "/api/admin/v1/me/password", map[string]any{"currentPassword": adminPassword, "newPassword": "Changed12345"}, root), http.StatusOK, "")
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/me", nil, root), http.StatusOK, "")
	a.expect(a.adminCall(http.MethodGet, "/api/admin/v1/me", nil, other), http.StatusUnauthorized, "UNAUTHORIZED")

	// 过期会话的清理
	a.clock.Advance(48 * time.Hour)
	if err := a.app.Admins.Cleanup(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func (a *testApp) adminID(s adminSession) string {
	a.t.Helper()
	return a.adminCall(http.MethodGet, "/api/admin/v1/me", nil, s).str("data", "id")
}

func TestMaskPhone(t *testing.T) {
	for in, want := range map[string]string{
		"+8613812345678": "+86 138****5678",
		"+12025550123":   "+12 ****0123",
		"+12345":         "+*****",
	} {
		if got := admin.MaskPhone(in); got != want {
			t.Errorf("MaskPhone(%q)=%q want %q", in, got, want)
		}
	}
}
