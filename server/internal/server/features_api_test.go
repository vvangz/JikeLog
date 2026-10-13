package server

import (
	"net/http"
	"testing"

	"github.com/vvangz/JikeLog/server/internal/auth"
)

func TestSystemInfoFeatures(t *testing.T) {
	a := newTestApp(t)
	r := a.call(http.MethodGet, "/api/v1/system/info", nil, "")
	a.expect(r, http.StatusOK, "")
	f := r.data()["features"].(map[string]any)
	if f["sms"] != true || f["push"] != false {
		t.Fatalf("开发环境的功能：%v", f)
	}
}

func TestSMSDisabled(t *testing.T) {
	a := newTestAppWith(t, map[string]string{"JIKELOG_SMS_PROVIDER": "disabled"})
	r := a.call(http.MethodGet, "/api/v1/system/info", nil, "")
	if r.data()["features"].(map[string]any)["sms"] != false {
		t.Fatalf("短信未开通：%v", r.data())
	}
	// 发送验证码返回 503，冷却被释放（再次请求得到同样的结果而不是 429）
	for i := 0; i < 2; i++ {
		a.expect(a.call(http.MethodPost, "/api/v1/auth/sms/send", map[string]any{"phone": "13900000001", "purpose": "login"}, ""), http.StatusServiceUnavailable, auth.CodeSMSDisabled)
	}
	// 用户名和密码照常注册、登录
	s := a.register("nosms01", "secret123", "install-a")
	a.expect(a.call(http.MethodPost, "/api/v1/me/sms/send", map[string]any{"purpose": "bind_phone", "phone": "13900000002"}, s.access), http.StatusServiceUnavailable, auth.CodeSMSDisabled)
}
