package auth

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/vvangz/JikeLog/server/internal/platform/aliyun"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// rewriteTransport 把发往阿里云的请求转到本地测试服务器，并记录原始 Host 与表单。
type rewriteTransport struct {
	target *url.URL
	host   string
	form   url.Values
}

func (rt *rewriteTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	rt.host = r.URL.Host
	body, _ := io.ReadAll(r.Body)
	rt.form, _ = url.ParseQuery(string(body))
	r2 := r.Clone(r.Context())
	r2.URL.Scheme, r2.URL.Host = rt.target.Scheme, rt.target.Host
	r2.Body = http.NoBody
	r2.ContentLength = 0
	return http.DefaultTransport.RoundTrip(r2)
}

func fakeAliyun(t *testing.T, status int, body string) (*aliyun.Client, *rewriteTransport) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}))
	t.Cleanup(srv.Close)
	u, _ := url.Parse(srv.URL)
	rt := &rewriteTransport{target: u}
	return aliyun.NewClient(aliyun.Credentials{AccessKeyID: "id", AccessKeySecret: "secret"}, &http.Client{Transport: rt}), rt
}

var testSMSConfig = AliyunSMSConfig{SignName: "测试签名", Templates: map[Purpose]string{PurposeLogin: "100001"}}

func TestAliyunSenderSendsCode(t *testing.T) {
	api, rt := fakeAliyun(t, http.StatusOK, `{"Code":"OK","Success":true}`)
	s := NewAliyunSender(api, testSMSConfig, discard)
	if err := s.SendCode(context.Background(), "+8613800000000", "123456", PurposeLogin); err != nil {
		t.Fatal(err)
	}
	if rt.host != dypnsHost {
		t.Errorf("host = %q", rt.host)
	}
	want := map[string]string{
		"PhoneNumber":   "13800000000",
		"SignName":      "测试签名",
		"TemplateCode":  "100001",
		"TemplateParam": `{"code":"123456","min":"5"}`,
	}
	for k, v := range want {
		if got := rt.form.Get(k); got != v {
			t.Errorf("%s = %q, want %q", k, got, v)
		}
	}
}

func TestAliyunSenderErrors(t *testing.T) {
	cases := []struct {
		name     string
		status   int
		body     string
		phone    string
		purpose  Purpose
		wantCode string // 为空表示应为普通错误（非 httpx.Error）
	}{
		{"daily limit", 400, `{"Code":"BUSINESS_LIMIT_CONTROL"}`, "+8613800000000", PurposeLogin, CodeSMSRateLimited},
		{"daily limit isv prefix", 400, `{"Code":"isv.BUSINESS_LIMIT_CONTROL"}`, "+8613800000000", PurposeLogin, CodeSMSRateLimited},
		{"frequency in 200", 200, `{"Code":"FREQUENCY_FAIL","Success":false}`, "+8613800000000", PurposeLogin, CodeSMSRateLimited},
		{"bad phone", 400, `{"Code":"MOBILE_NUMBER_ILLEGAL"}`, "+8613800000000", PurposeLogin, httpx.CodeValidationFailed},
		{"foreign phone", 200, `{"Code":"OK"}`, "+12025550100", PurposeLogin, httpx.CodeValidationFailed},
		{"no permission", 403, `{"Code":"Forbidden.NoPermission","Message":"denied"}`, "+8613800000000", PurposeLogin, ""},
		{"unknown purpose", 200, `{"Code":"OK"}`, "+8613800000000", PurposeBindPhone, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			api, _ := fakeAliyun(t, tc.status, tc.body)
			err := NewAliyunSender(api, testSMSConfig, discard).SendCode(context.Background(), tc.phone, "123456", tc.purpose)
			if err == nil {
				t.Fatal("应返回错误")
			}
			var appErr *httpx.Error
			isApp := errors.As(err, &appErr)
			if tc.wantCode == "" && isApp {
				t.Fatalf("err = %v，不应作为业务错误返回给客户端", err)
			}
			if tc.wantCode != "" && (!isApp || appErr.Code != tc.wantCode) {
				t.Fatalf("err = %v, want code %s", err, tc.wantCode)
			}
		})
	}
}

func TestSMSCodesSendKeepsCooldownOnProviderLimit(t *testing.T) {
	rdb, mr := newRedis(t)
	api, _ := fakeAliyun(t, 400, `{"Code":"BUSINESS_LIMIT_CONTROL"}`)
	codes := NewSMSCodes(rdb, nil, NewAliyunSender(api, testSMSConfig, discard), discard, testHashKey)
	phone := "+8613800000000"
	if err := rdb.Set(context.Background(), cooldownKey(phone), 1, SMSCooldown).Err(); err != nil {
		t.Fatal(err)
	}
	err := codes.Send(context.Background(), PurposeLogin, phone)
	var appErr *httpx.Error
	if !errors.As(err, &appErr) || appErr.Status != http.StatusTooManyRequests {
		t.Fatalf("Send() = %v, want 429", err)
	}
	if !mr.Exists(cooldownKey(phone)) {
		t.Error("通道频控时应保留冷却期")
	}
	if mr.Exists(codeKey(PurposeLogin, phone)) {
		t.Error("发送失败时应删除验证码")
	}
}

func TestAliyunCaptchaVerify(t *testing.T) {
	cases := []struct {
		name    string
		status  int
		body    string
		param   string
		want    bool
		wantErr bool
	}{
		{"passed", 200, `{"Result":{"VerifyResult":true,"VerifyCode":"T001"}}`, "p", true, false},
		{"rejected", 200, `{"Result":{"VerifyResult":false,"VerifyCode":"F001"}}`, "p", false, false},
		{"empty param skips call", 500, ``, "", false, false},
		{"server error fails open", 503, `{"Code":"ServiceUnavailable"}`, "p", true, false},
		{"throttled fails closed", 429, `{"Code":"Throttling"}`, "p", false, true},
		{"permission error fails closed", 403, `{"Code":"Forbidden.RAMUserAccessDenied"}`, "p", false, true},
		{"undecodable body fails closed", 200, `<html>captive portal</html>`, "p", false, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			api, rt := fakeAliyun(t, tc.status, tc.body)
			got, err := NewAliyunCaptcha(api, "scene-1", discard).Verify(context.Background(), tc.param, "1.1.1.1")
			if got != tc.want || (err != nil) != tc.wantErr {
				t.Fatalf("Verify() = %v, %v; want %v, err=%v", got, err, tc.want, tc.wantErr)
			}
			if tc.param != "" && (rt.host != captchaHost || rt.form.Get("SceneId") != "scene-1" || rt.form.Get("CaptchaVerifyParam") != "p") {
				t.Errorf("request host=%q form=%v", rt.host, rt.form)
			}
		})
	}
}

func TestAliyunCaptchaNetworkErrorFailsOpen(t *testing.T) {
	srv := httptest.NewServer(http.NotFoundHandler())
	u, _ := url.Parse(srv.URL)
	srv.Close() // 连接被拒绝
	api := aliyun.NewClient(aliyun.Credentials{}, &http.Client{Transport: &rewriteTransport{target: u}})
	got, err := NewAliyunCaptcha(api, "s", discard).Verify(context.Background(), "p", "")
	if !got || err != nil {
		t.Fatalf("Verify() = %v, %v; want true, nil", got, err)
	}
}

func TestAliyunCaptchaCancelledContext(t *testing.T) {
	api, _ := fakeAliyun(t, http.StatusOK, `{"Result":{"VerifyResult":true}}`)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	got, err := NewAliyunCaptcha(api, "s", discard).Verify(ctx, "p", "")
	if got || !errors.Is(err, context.Canceled) {
		t.Fatalf("Verify() = %v, %v; want false, context.Canceled", got, err)
	}
}

func TestAliyunCaptchaFailOpenBudget(t *testing.T) {
	api, _ := fakeAliyun(t, http.StatusServiceUnavailable, `{"Code":"ServiceUnavailable"}`)
	c := NewAliyunCaptcha(api, "s", discard)
	now := time.Date(2026, 10, 26, 8, 0, 0, 0, time.UTC)
	c.now = func() time.Time { return now }
	for i := range captchaFailOpenPerMinute {
		if ok, err := c.Verify(context.Background(), "p", ""); !ok || err != nil {
			t.Fatalf("第 %d 次应放行：%v, %v", i+1, ok, err)
		}
	}
	if ok, _ := c.Verify(context.Background(), "p", ""); ok {
		t.Fatal("超出每分钟放行上限后应拒绝")
	}
	now = now.Add(time.Minute)
	if ok, _ := c.Verify(context.Background(), "p", ""); !ok {
		t.Fatal("下一分钟应重新放行")
	}
}
