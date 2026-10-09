package server

import (
	"fmt"
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"go.yaml.in/yaml/v3"
)

func TestRegisterAndGetMe(t *testing.T) {
	a := newTestApp(t)
	s := a.register("Zhang_San", "secret123", "install-001")
	if s.access == "" || s.refresh == "" || s.deviceID == "" {
		t.Fatalf("会话不完整: %+v", s)
	}
	me := a.call(http.MethodGet, "/api/v1/me", nil, s.access)
	a.expect(me, http.StatusOK, "")
	if me.str("data", "username") != "Zhang_San" || me.data()["hasPhone"] != false {
		t.Errorf("me = %v", me.data())
	}
	st := a.call(http.MethodGet, "/api/v1/me/settings", nil, s.access)
	a.expect(st, http.StatusOK, "")
	if st.str("data", "themeMode") != "system" {
		t.Errorf("注册应创建默认设置: %v", st.data())
	}
}

func TestRegisterValidationAndConflict(t *testing.T) {
	a := newTestApp(t)
	a.register("alice", "secret123", "install-001")

	dup := a.call(http.MethodPost, "/api/v1/auth/register", map[string]any{
		"username": "ALICE", "password": "secret123", "device": device("install-002"),
	}, "")
	a.expect(dup, http.StatusConflict, "USERNAME_TAKEN")

	bad := a.call(http.MethodPost, "/api/v1/auth/register", map[string]any{
		"username": "1a", "password": "short", "nickname": strings.Repeat("长", 21),
		"device": map[string]any{"installationId": "x", "platform": "symbian"},
	}, "")
	a.expect(bad, http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	details, _ := bad.Body["error"].(map[string]any)["details"].(map[string]any)
	fields, _ := details["fields"].(map[string]any)
	for _, f := range []string{"username", "password", "nickname", "device.installationId", "device.platform"} {
		if _, ok := fields[f]; !ok {
			t.Errorf("缺少字段错误 %s: %v", f, fields)
		}
	}
	a.expect(a.call(http.MethodPost, "/api/v1/auth/register", nil, ""), http.StatusBadRequest, "BAD_REQUEST")
	weak := a.call(http.MethodPost, "/api/v1/auth/register", map[string]any{
		"username": "bobby", "password": "onlyletters", "device": device("install-003"),
	}, "")
	a.expect(weak, http.StatusUnprocessableEntity, "VALIDATION_FAILED")
}

func TestPasswordLoginAndLockout(t *testing.T) {
	a := newTestApp(t)
	a.register("carol", "secret123", "install-001")

	ok := a.login("CAROL", "secret123", "install-002")
	a.expect(ok, http.StatusOK, "")
	a.expect(a.login("nobody", "secret123", "install-002"), http.StatusUnauthorized, "INVALID_CREDENTIALS")

	for range 5 {
		a.expect(a.login("carol", "wrong-pass1", "install-002"), http.StatusUnauthorized, "INVALID_CREDENTIALS")
	}
	locked := a.login("carol", "secret123", "install-002")
	a.expect(locked, http.StatusTooManyRequests, "ACCOUNT_LOCKED")
	if locked.Header.Get("Retry-After") == "" {
		t.Error("锁定响应应带 Retry-After")
	}
	// 锁定只针对该网络：本人换一个网络仍可登录
	a.ip = "198.51.100.77"
	a.expect(a.login("carol", "secret123", "install-002"), http.StatusOK, "")
	a.ip = "198.51.100.1"
	a.clock.Advance(16 * time.Minute)
	a.expect(a.login("carol", "secret123", "install-002"), http.StatusOK, "")
}

func TestLockoutAcrossNetworks(t *testing.T) {
	a := newTestApp(t)
	a.register("dora", "secret123", "install-001")
	for i := range 20 {
		a.ip = fmt.Sprintf("203.0.113.%d", i+1)
		a.expect(a.login("dora", "wrong-pass1", "install-002"), http.StatusUnauthorized, "INVALID_CREDENTIALS")
	}
	a.ip = "203.0.113.200"
	a.expect(a.login("dora", "secret123", "install-002"), http.StatusTooManyRequests, "ACCOUNT_LOCKED")
}

func TestLoginRateLimitedPerIP(t *testing.T) {
	a := newTestApp(t)
	for i := range 100 {
		a.expect(a.login(fmt.Sprintf("user%03d", i), "secret123", "install-001"), http.StatusUnauthorized, "")
	}
	a.expect(a.login("someone", "secret123", "install-001"), http.StatusTooManyRequests, "RATE_LIMITED")
	a.ip = "198.51.100.2"
	a.expect(a.login("someone", "secret123", "install-001"), http.StatusUnauthorized, "INVALID_CREDENTIALS")
}

// pathParam 匹配 Gin 路由中的路径参数（如 :deviceId）。
var pathParam = regexp.MustCompile(`:[A-Za-z]+`)

func TestDefaultDenyRequiresToken(t *testing.T) {
	a := newTestApp(t)
	engine := a.h.(*gin.Engine)
	for _, rt := range engine.Routes() {
		if isPublicRoute(rt.Method, rt.Path) {
			continue
		}
		path := pathParam.ReplaceAllString(rt.Path, "0192a000-0000-7000-8000-000000000000")
		r := a.call(rt.Method, path, map[string]any{}, "")
		if r.Status != http.StatusUnauthorized || r.code() != "UNAUTHORIZED" {
			t.Errorf("%s %s 未登录时 = %d %s，want 401", rt.Method, rt.Path, r.Status, r.code())
		}
		r = a.call(rt.Method, path, map[string]any{}, "not-a-jwt")
		if r.Status != http.StatusUnauthorized {
			t.Errorf("%s %s 令牌无效时 = %d，want 401", rt.Method, rt.Path, r.Status)
		}
	}
}

// TestPublicRoutesMatchSpec 保证认证白名单与契约中 security: [] 的接口完全一致。
func TestPublicRoutesMatchSpec(t *testing.T) {
	raw, err := os.ReadFile("../../api/openapi.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var spec struct {
		Paths map[string]map[string]struct {
			Security *[]map[string][]string `yaml:"security"`
		} `yaml:"paths"`
	}
	if err := yaml.Unmarshal(raw, &spec); err != nil {
		t.Fatal(err)
	}
	var fromSpec []string
	for path, ops := range spec.Paths {
		for method, op := range ops {
			if op.Security != nil && len(*op.Security) == 0 {
				route := strings.NewReplacer("{", ":", "}", "").Replace(path)
				fromSpec = append(fromSpec, strings.ToUpper(method)+" "+route)
			}
		}
	}
	var fromCode []string
	for k := range publicRoutes {
		if !strings.HasPrefix(k, "HEAD ") { // HEAD 探针为额外注册，契约中不单独列出
			fromCode = append(fromCode, k)
		}
	}
	slices.Sort(fromSpec)
	slices.Sort(fromCode)
	if !slices.Equal(fromSpec, fromCode) {
		t.Errorf("公开路由与契约不一致\n契约: %v\n代码: %v", fromSpec, fromCode)
	}
}

func TestSMSLoginRegistrationFlow(t *testing.T) {
	a := newTestApp(t)
	code := a.sendSMS("13800138000", "login", "")
	if len(code) != 6 {
		t.Fatalf("验证码 = %q", code)
	}
	r := a.call(http.MethodPost, "/api/v1/auth/login/sms", map[string]any{"phone": "+86 138-0013-8000", "code": code, "device": device("install-001")}, "")
	a.expect(r, http.StatusOK, "")
	if r.str("data", "status") != "registration_required" || r.str("data", "phoneMasked") != "138****8000" {
		t.Fatalf("新号码应要求完善注册: %v", r.data())
	}
	ticket := r.str("data", "registrationTicket")

	reg := func(username string) apiResp {
		return a.call(http.MethodPost, "/api/v1/auth/register/sms", map[string]any{
			"registrationTicket": ticket, "username": username, "password": "secret123", "device": device("install-001"),
		}, "")
	}
	a.register("taken_name", "secret123", "install-009")
	a.expect(reg("taken_name"), http.StatusConflict, "USERNAME_TAKEN") // 可纠正的错误不作废凭证
	done := reg("dave")
	a.expect(done, http.StatusCreated, "")
	if done.data()["user"].(map[string]any)["hasPhone"] != true {
		t.Error("完善注册后应已绑定手机号")
	}
	a.expect(reg("dave2"), http.StatusBadRequest, "REGISTRATION_TICKET_INVALID") // 凭证只能用一次

	code = a.sendSMS("13800138000", "login", "")
	again := a.call(http.MethodPost, "/api/v1/auth/login/sms", map[string]any{"phone": "13800138000", "code": code, "device": device("install-002")}, "")
	a.expect(again, http.StatusOK, "")
	if again.str("data", "status") != "authenticated" || sessionFrom(again).access == "" {
		t.Errorf("已注册号码应直接登录: %v", again.data())
	}
}

func TestSMSRateLimitAndAttempts(t *testing.T) {
	a := newTestApp(t)
	send := func(phone string) apiResp {
		return a.call(http.MethodPost, "/api/v1/auth/sms/send", map[string]any{"phone": phone, "purpose": "login"}, "")
	}
	a.expect(send("13900000001"), http.StatusOK, "")
	cool := send("13900000001")
	a.expect(cool, http.StatusTooManyRequests, "SMS_RATE_LIMITED")
	if cool.Header.Get("Retry-After") == "" {
		t.Error("冷却响应应带 Retry-After")
	}
	a.expect(send("12345"), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(a.call(http.MethodPost, "/api/v1/auth/sms/send", map[string]any{"phone": "13900000001", "purpose": "hack"}, ""), http.StatusUnprocessableEntity, "VALIDATION_FAILED")

	code := a.sms.LastCode("+8613900000001")
	wrong := "000000"
	if code == wrong {
		wrong = "111111"
	}
	login := func(c string) apiResp {
		return a.call(http.MethodPost, "/api/v1/auth/login/sms", map[string]any{"phone": "13900000001", "code": c, "device": device("install-001")}, "")
	}
	for range 5 {
		a.expect(login(wrong), http.StatusBadRequest, "SMS_CODE_INVALID")
	}
	a.expect(login(code), http.StatusBadRequest, "SMS_CODE_INVALID") // 尝试次数用尽后正确验证码也失效

	// 同一 IP 每小时最多 20 条（已用 2 条：首次发送与被冷却拒绝的那次）
	for i := range 18 {
		a.expect(send(fmt.Sprintf("137%08d", i)), http.StatusOK, "")
	}
	a.expect(send("13799999999"), http.StatusTooManyRequests, "SMS_RATE_LIMITED")
}

func TestRefreshRotationGraceAndReuse(t *testing.T) {
	a := newTestApp(t)
	s := a.register("erin", "secret123", "install-001")
	refresh := func(tok string) apiResp {
		return a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": tok}, "")
	}
	r1 := refresh(s.refresh)
	a.expect(r1, http.StatusOK, "")
	newRefresh := r1.str("data", "refreshToken")
	if newRefresh == s.refresh {
		t.Fatal("刷新后应轮换 Refresh Token")
	}
	// 宽限期内重放旧令牌（客户端没收到上次响应）：返回同一结果，客户端保留哪次响应都有效
	a.clock.Advance(10 * time.Second)
	r2 := refresh(s.refresh)
	a.expect(r2, http.StatusOK, "")
	latest := r2.str("data", "refreshToken")
	if latest != newRefresh {
		t.Fatal("宽限期内重复刷新应返回同一枚令牌")
	}
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, r2.str("data", "accessToken")), http.StatusOK, "")

	// 超过宽限期再用旧令牌：视为泄露，设备下线
	a.clock.Advance(time.Minute)
	a.expect(refresh(s.refresh), http.StatusUnauthorized, "REFRESH_INVALID")
	a.expect(refresh(latest), http.StatusUnauthorized, "REFRESH_INVALID")
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, r2.str("data", "accessToken")), http.StatusUnauthorized, "UNAUTHORIZED")

	a.expect(refresh("garbage"), http.StatusUnauthorized, "REFRESH_INVALID")
	a.expect(refresh(""), http.StatusUnauthorized, "REFRESH_INVALID")
}

func TestConcurrentRefreshIsIdempotent(t *testing.T) {
	a := newTestApp(t)
	s := a.register("eric", "secret123", "install-001")
	const n = 4
	results := make([]apiResp, n)
	var wg sync.WaitGroup
	for i := range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results[i] = a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": s.refresh}, "")
		}()
	}
	wg.Wait()
	first := results[0].str("data", "refreshToken")
	for _, r := range results {
		if r.Status != http.StatusOK || r.str("data", "refreshToken") != first {
			t.Fatalf("并发刷新结果不一致: %d %v", r.Status, r.Body)
		}
	}
	a.clock.Advance(time.Second)
	a.expect(a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": first}, ""), http.StatusOK, "")
}

func TestRefreshWhenReplayCacheLost(t *testing.T) {
	a := newTestApp(t)
	s := a.register("enzo", "secret123", "install-001")
	a.expect(a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": s.refresh}, ""), http.StatusOK, "")
	for _, k := range a.mr.Keys() {
		if strings.HasPrefix(k, "jk:rr:") {
			a.mr.Del(k)
		}
	}
	// 缓存丢失时退化为再换发一次，用户不会被登出
	r := a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": s.refresh}, "")
	a.expect(r, http.StatusOK, "")
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, r.str("data", "accessToken")), http.StatusOK, "")
}

func TestRefreshTokenExpires(t *testing.T) {
	a := newTestApp(t)
	s := a.register("frank", "secret123", "install-001")
	a.clock.Advance(31 * 24 * time.Hour)
	a.expect(a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": s.refresh}, ""), http.StatusUnauthorized, "REFRESH_INVALID")
}

func TestAccessTokenExpires(t *testing.T) {
	a := newTestApp(t)
	s := a.register("gina", "secret123", "install-001")
	a.clock.Advance(16 * time.Minute)
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, s.access), http.StatusUnauthorized, "UNAUTHORIZED")
}

func TestLogoutAndRelogin(t *testing.T) {
	a := newTestApp(t)
	s := a.register("henry", "secret123", "install-001")
	a.expect(a.call(http.MethodPost, "/api/v1/auth/logout", nil, s.access), http.StatusOK, "")
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, s.access), http.StatusUnauthorized, "UNAUTHORIZED")
	a.expect(a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": s.refresh}, ""), http.StatusUnauthorized, "REFRESH_INVALID")

	// 同一安装实例重新登录：复用设备记录，新令牌立即可用（下线标记为毫秒精度，同一秒内重新登录也不受影响）
	a.clock.Advance(time.Millisecond)
	again := sessionFrom(a.login("henry", "secret123", "install-001"))
	if again.deviceID != s.deviceID {
		t.Errorf("同一安装实例应复用设备 ID: %s != %s", again.deviceID, s.deviceID)
	}
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, again.access), http.StatusOK, "")
}

func TestResetPassword(t *testing.T) {
	a := newTestApp(t)
	s := a.register("ivy_1", "secret123", "install-001")
	a.bindPhone(s.access, "13600000000")
	other := sessionFrom(a.login("ivy_1", "secret123", "install-002"))

	// 未注册号码：同样返回成功，但不发送
	a.expect(a.call(http.MethodPost, "/api/v1/auth/sms/send", map[string]any{"phone": "13600000009", "purpose": "reset_password"}, ""), http.StatusOK, "")
	if a.sms.LastCode("+8613600000009") != "" {
		t.Error("未注册号码不应发送找回密码验证码")
	}
	code := a.sendSMS("13600000000", "reset_password", "")
	reset := func(c, pw string) apiResp {
		return a.call(http.MethodPost, "/api/v1/auth/password/reset", map[string]any{"phone": "13600000000", "code": c, "newPassword": pw}, "")
	}
	a.expect(reset(code, "weak"), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(reset(code, "newsecret456"), http.StatusOK, "")
	a.expect(reset(code, "newsecret789"), http.StatusBadRequest, "SMS_CODE_INVALID") // 验证码已消费

	for _, tok := range []string{s.access, other.access} {
		a.expect(a.call(http.MethodGet, "/api/v1/me", nil, tok), http.StatusUnauthorized, "UNAUTHORIZED")
	}
	a.expect(a.login("ivy_1", "secret123", "install-001"), http.StatusUnauthorized, "INVALID_CREDENTIALS")
	a.expect(a.login("ivy_1", "newsecret456", "install-001"), http.StatusOK, "")
}
