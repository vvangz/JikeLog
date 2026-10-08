package server

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestUpdateMe(t *testing.T) {
	a := newTestApp(t)
	s := a.register("judy", "secret123", "install-001")
	r := a.call(http.MethodPatch, "/api/v1/me", map[string]any{"nickname": "  朱迪  "}, s.access)
	a.expect(r, http.StatusOK, "")
	if r.str("data", "nickname") != "朱迪" {
		t.Errorf("昵称应去掉首尾空白: %q", r.str("data", "nickname"))
	}
	a.expect(a.call(http.MethodPatch, "/api/v1/me", map[string]any{"nickname": strings.Repeat("长", 21)}, s.access), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
}

func TestChangePasswordRevokesOtherDevices(t *testing.T) {
	a := newTestApp(t)
	s := a.register("kate", "secret123", "install-001")
	other := sessionFrom(a.login("kate", "secret123", "install-002"))
	change := func(body map[string]any) apiResp {
		return a.call(http.MethodPut, "/api/v1/me/password", body, s.access)
	}

	a.expect(change(map[string]any{"newPassword": "newsecret456"}), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(change(map[string]any{"currentPassword": "wrong-pass1", "newPassword": "newsecret456"}), http.StatusBadRequest, "INVALID_CREDENTIALS")
	a.expect(change(map[string]any{"smsCode": "123456", "newPassword": "newsecret456"}), http.StatusBadRequest, "PHONE_NOT_BOUND")
	a.expect(change(map[string]any{"currentPassword": "secret123", "newPassword": "newsecret456"}), http.StatusOK, "")

	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, s.access), http.StatusOK, "")
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, other.access), http.StatusUnauthorized, "UNAUTHORIZED")
	a.expect(a.login("kate", "newsecret456", "install-003"), http.StatusOK, "")

	// 身份校验连续失败会被临时限制
	for range 5 {
		a.expect(change(map[string]any{"currentPassword": "wrong-pass1", "newPassword": "another789x"}), http.StatusBadRequest, "INVALID_CREDENTIALS")
	}
	a.expect(change(map[string]any{"currentPassword": "newsecret456", "newPassword": "another789x"}), http.StatusTooManyRequests, "RATE_LIMITED")
}

func TestChangePasswordWithSMS(t *testing.T) {
	a := newTestApp(t)
	s := a.register("liam", "secret123", "install-001")
	a.bindPhone(s.access, "13500000000")
	a.sendSMS("", "verify_current", s.access)
	code := a.sms.LastCode("+8613500000000")
	a.expect(a.call(http.MethodPut, "/api/v1/me/password", map[string]any{"smsCode": code, "newPassword": "newsecret456"}, s.access), http.StatusOK, "")
	a.expect(a.login("liam", "newsecret456", "install-002"), http.StatusOK, "")
}

func TestBindAndChangePhone(t *testing.T) {
	a := newTestApp(t)
	s := a.register("mike", "secret123", "install-001")
	other := a.register("nina", "secret123", "install-002")
	a.bindPhone(other.access, "13400000000")
	bind := func(body map[string]any) apiResp {
		return a.call(http.MethodPut, "/api/v1/me/phone", body, s.access)
	}

	// 已被占用的号码：同样返回成功但不发送，无法借此探测号码是否注册
	before := a.sms.LastCode("+8613400000000")
	a.expect(a.call(http.MethodPost, "/api/v1/me/sms/send", map[string]any{"purpose": "bind_phone", "phone": "13400000000"}, s.access), http.StatusOK, "")
	if a.sms.LastCode("+8613400000000") != before {
		t.Error("已被占用的号码不应收到验证码")
	}
	a.expect(bind(map[string]any{"phone": "13400000000", "code": "123456", "currentPassword": "secret123"}), http.StatusBadRequest, "SMS_CODE_INVALID")
	a.expect(a.call(http.MethodPost, "/api/v1/me/sms/send", map[string]any{"purpose": "bind_phone"}, s.access), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(a.call(http.MethodPost, "/api/v1/me/sms/send", map[string]any{"purpose": "verify_current"}, s.access), http.StatusBadRequest, "PHONE_NOT_BOUND")

	a.clock.Advance(time.Minute)
	code := a.sendSMS("13400000001", "bind_phone", s.access)
	a.expect(bind(map[string]any{"phone": "13400000001", "code": code}), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(bind(map[string]any{"phone": "13400000001", "code": code, "currentPassword": "wrong-pass1"}), http.StatusBadRequest, "INVALID_CREDENTIALS")
	bound := bind(map[string]any{"phone": "13400000001", "code": code, "currentPassword": "secret123"})
	a.expect(bound, http.StatusOK, "")
	if bound.str("data", "phoneMasked") != "134****0001" {
		t.Errorf("phoneMasked = %q", bound.str("data", "phoneMasked"))
	}
	a.expect(a.call(http.MethodPost, "/api/v1/me/sms/send", map[string]any{"purpose": "bind_phone", "phone": "13400000001"}, s.access), http.StatusUnprocessableEntity, "VALIDATION_FAILED")

	// 换绑：需要当前密码、新号码与当前号码的验证码
	newCode := a.sendSMS("13400000002", "bind_phone", s.access)
	a.expect(bind(map[string]any{"phone": "13400000002", "code": newCode, "currentPassword": "secret123"}), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.sendSMS("", "verify_current", s.access)
	oldCode := a.sms.LastCode("+8613400000001")
	changed := bind(map[string]any{"phone": "13400000002", "code": newCode, "currentCode": oldCode, "currentPassword": "secret123"})
	a.expect(changed, http.StatusOK, "")
	if changed.str("data", "phoneMasked") != "134****0002" {
		t.Errorf("换绑后 phoneMasked = %q", changed.str("data", "phoneMasked"))
	}
	// 旧号码已释放，可被其他账号绑定
	third := a.register("oscar", "secret123", "install-003")
	a.bindPhone(third.access, "13400000001")
}

func TestDevicesListAndRevoke(t *testing.T) {
	a := newTestApp(t)
	s := a.register("paul", "secret123", "install-001")
	other := sessionFrom(a.login("paul", "secret123", "install-002"))
	stranger := a.register("quinn", "secret123", "install-003")

	list := a.call(http.MethodGet, "/api/v1/me/devices", nil, s.access)
	a.expect(list, http.StatusOK, "")
	devices, _ := list.Body["data"].([]any)
	if len(devices) != 2 {
		t.Fatalf("设备数 = %d, want 2", len(devices))
	}
	current := 0
	for _, d := range devices {
		if d.(map[string]any)["current"] == true {
			current++
		}
	}
	if current != 1 {
		t.Errorf("应恰好有 1 台当前设备，got %d", current)
	}

	revoke := func(id, tok string) apiResp {
		return a.call(http.MethodDelete, "/api/v1/me/devices/"+id, nil, tok)
	}
	a.expect(revoke(s.deviceID, s.access), http.StatusBadRequest, "CANNOT_REVOKE_CURRENT_DEVICE")
	a.expect(revoke(stranger.deviceID, s.access), http.StatusNotFound, "DEVICE_NOT_FOUND") // 不能下线别人的设备
	a.expect(revoke("not-a-uuid", s.access), http.StatusBadRequest, "BAD_REQUEST")
	a.expect(revoke(other.deviceID, s.access), http.StatusOK, "")
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, other.access), http.StatusUnauthorized, "UNAUTHORIZED")
	a.expect(a.call(http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refreshToken": other.refresh}, ""), http.StatusUnauthorized, "REFRESH_INVALID")
	a.expect(revoke(other.deviceID, s.access), http.StatusNotFound, "DEVICE_NOT_FOUND")
}

func TestSettings(t *testing.T) {
	a := newTestApp(t)
	s := a.register("rose", "secret123", "install-001")
	put := func(body map[string]any) apiResp {
		return a.call(http.MethodPut, "/api/v1/me/settings", body, s.access)
	}
	r := put(map[string]any{"themeMode": "dark", "fontScale": 1.2, "defaultReminders": []int{15, 0, 15, 60}, "weekStart": 7})
	a.expect(r, http.StatusOK, "")
	got := r.data()
	if got["themeMode"] != "dark" || got["weekStart"] != float64(7) {
		t.Errorf("settings = %v", got)
	}
	if rem, _ := got["defaultReminders"].([]any); len(rem) != 3 || rem[0] != float64(0) || rem[2] != float64(60) {
		t.Errorf("提醒应去重并升序: %v", got["defaultReminders"])
	}
	again := a.call(http.MethodGet, "/api/v1/me/settings", nil, s.access)
	if again.str("data", "themeMode") != "dark" {
		t.Error("设置未持久化")
	}
	bad := put(map[string]any{"themeMode": "pink", "fontScale": 3, "defaultReminders": []int{-1, 1, 2, 3, 4, 5}, "weekStart": 3})
	a.expect(bad, http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	fields, _ := bad.Body["error"].(map[string]any)["details"].(map[string]any)["fields"].(map[string]any)
	if len(fields) != 4 {
		t.Errorf("应返回 4 个字段错误: %v", fields)
	}
}

func TestDeleteAccount(t *testing.T) {
	a := newTestApp(t)
	s := a.register("sam_1", "secret123", "install-001")
	other := sessionFrom(a.login("sam_1", "secret123", "install-002"))
	a.bindPhone(s.access, "13300000000")

	del := func(body map[string]any) apiResp {
		return a.call(http.MethodPost, "/api/v1/me/deletion", body, s.access)
	}
	a.expect(del(map[string]any{}), http.StatusUnprocessableEntity, "VALIDATION_FAILED")
	a.expect(del(map[string]any{"currentPassword": "wrong-pass1"}), http.StatusBadRequest, "INVALID_CREDENTIALS")
	a.expect(del(map[string]any{"currentPassword": "secret123"}), http.StatusOK, "")

	for _, tok := range []string{s.access, other.access} {
		a.expect(a.call(http.MethodGet, "/api/v1/me", nil, tok), http.StatusUnauthorized, "UNAUTHORIZED")
	}
	// 用户名与手机号都已释放
	again := a.register("sam_1", "secret123", "install-001")
	a.bindPhone(again.access, "13300000000")
}

func TestBodyLimitAndCORS(t *testing.T) {
	a := newTestApp(t)
	big := map[string]any{"username": strings.Repeat("x", 2<<20), "password": "p", "device": device("install-001")}
	a.expect(a.call(http.MethodPost, "/api/v1/auth/register", big, ""), http.StatusRequestEntityTooLarge, "PAYLOAD_TOO_LARGE")

	pre := httptest.NewRequest(http.MethodOptions, "/api/v1/me", nil)
	pre.Header.Set("Origin", "http://localhost:5173")
	pre.Header.Set("Access-Control-Request-Method", "GET")
	rec := httptest.NewRecorder()
	a.h.ServeHTTP(rec, pre)
	if rec.Code != http.StatusNoContent || rec.Header().Get("Access-Control-Allow-Origin") != "http://localhost:5173" {
		t.Errorf("预检 = %d %v", rec.Code, rec.Header())
	}
	evil := httptest.NewRequest(http.MethodGet, "/api/v1/system/info", nil)
	evil.Header.Set("Origin", "https://evil.example.com")
	rec = httptest.NewRecorder()
	a.h.ServeHTTP(rec, evil)
	if rec.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Error("非白名单来源不应获得 CORS 头")
	}
}

func TestReadyzChecksDependencies(t *testing.T) {
	a := newTestApp(t)
	a.expect(a.call(http.MethodGet, "/readyz", nil, ""), http.StatusOK, "")
	a.mr.Close()
	a.clock.mu.Lock()                              // miniredis 已关闭，不再推进其时间
	a.clock.now = a.clock.now.Add(2 * time.Second) // 越过就绪结果缓存
	a.clock.mu.Unlock()
	r := a.call(http.MethodGet, "/readyz", nil, "")
	a.expect(r, http.StatusServiceUnavailable, "DEPENDENCY_UNAVAILABLE")
}

// 下线状态保存在数据库中：Redis 故障或数据丢失不影响已登录请求，也不会让已下线的令牌复活。
func TestRevocationDoesNotDependOnRedis(t *testing.T) {
	a := newTestApp(t)
	s := a.register("tina", "secret123", "install-001")
	other := sessionFrom(a.login("tina", "secret123", "install-002"))
	a.mr.Close()
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, s.access), http.StatusOK, "")
	a.expect(a.call(http.MethodDelete, "/api/v1/me/devices/"+other.deviceID, nil, s.access), http.StatusOK, "")
	a.expect(a.call(http.MethodGet, "/api/v1/me", nil, other.access), http.StatusUnauthorized, "UNAUTHORIZED")
}

func TestNewAppRejectsUnsupportedProviders(t *testing.T) {
	for _, env := range []map[string]string{
		{"JIKELOG_SMS_PROVIDER": "aliyun"},
		{"JIKELOG_CAPTCHA_PROVIDER": "aliyun"},
	} {
		if _, err := NewApp(context.Background(), Options{Config: testConfig(t, env)}); err == nil {
			t.Errorf("尚未接入的通道 %v 应拒绝启动", env)
		}
	}
}
