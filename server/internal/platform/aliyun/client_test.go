package aliyun

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// 官方文档"V3 请求体与签名机制"中的固定参数示例。
func TestAuthorizationMatchesOfficialExample(t *testing.T) {
	headers := map[string]string{
		"host":                  "ecs.cn-shanghai.aliyuncs.com",
		"x-acs-action":          "RunInstances",
		"x-acs-version":         "2014-05-26",
		"x-acs-date":            "2023-10-26T10:22:32Z",
		"x-acs-signature-nonce": "3156853299f313e23d1673dc12e1703d",
		"x-acs-content-sha256":  sha256Hex(nil),
	}
	query := encodeRFC3986(url.Values{
		"RegionId": {"cn-shanghai"},
		"ImageId":  {"win2019_1809_x64_dtc_zh-cn_40G_alibase_20230811.vhd"},
	})
	got := authorization(Credentials{AccessKeyID: "YourAccessKeyId", AccessKeySecret: "YourAccessKeySecret"},
		http.MethodPost, "/", query, headers, nil)
	want := "ACS3-HMAC-SHA256 Credential=YourAccessKeyId," +
		"SignedHeaders=host;x-acs-action;x-acs-content-sha256;x-acs-date;x-acs-signature-nonce;x-acs-version," +
		"Signature=06563a9e1b43f5dfe96b81484da74bceab24a1d853912eee15083a6f0f3283c0"
	if got != want {
		t.Fatalf("authorization =\n%s\nwant\n%s", got, want)
	}
}

func TestPercentEncode(t *testing.T) {
	cases := map[string]string{
		"a b":     "a%20b",
		"a*b":     "a%2Ab",
		"a~b-_.":  "a~b-_.",
		`{"c":1}`: "%7B%22c%22%3A1%7D",
		"恒创":      "%E6%81%92%E5%88%9B",
	}
	for in, want := range cases {
		if got := percentEncode(in); got != want {
			t.Errorf("percentEncode(%q) = %q, want %q", in, got, want)
		}
	}
}

func newTestClient(t *testing.T, h http.HandlerFunc) (*Client, string) {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	c := NewClient(Credentials{AccessKeyID: "id", AccessKeySecret: "secret"}, srv.Client())
	c.scheme = "http"
	c.now = func() time.Time { return time.Date(2026, 10, 26, 8, 0, 0, 0, time.UTC) }
	return c, strings.TrimPrefix(srv.URL, "http://")
}

func TestCallSendsSignedForm(t *testing.T) {
	c, host := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("x-acs-action") != "Ping" || r.Header.Get("x-acs-version") != "2020-01-01" {
			t.Errorf("action/version headers = %q/%q", r.Header.Get("x-acs-action"), r.Header.Get("x-acs-version"))
		}
		if r.Header.Get("x-acs-date") != "2026-10-26T08:00:00Z" {
			t.Errorf("x-acs-date = %q", r.Header.Get("x-acs-date"))
		}
		if !strings.HasPrefix(r.Header.Get("Authorization"), "ACS3-HMAC-SHA256 Credential=id,SignedHeaders=content-type;host;") {
			t.Errorf("Authorization = %q", r.Header.Get("Authorization"))
		}
		body, _ := io.ReadAll(r.Body)
		if string(body) != "A=1&B=x%20y" {
			t.Errorf("body = %q", body)
		}
		if r.Header.Get("x-acs-content-sha256") != sha256Hex(body) {
			t.Error("x-acs-content-sha256 与请求体不一致")
		}
		_, _ = io.WriteString(w, `{"Code":"OK"}`)
	})
	var out struct{ Code string }
	err := c.Call(context.Background(), Request{Host: host, Action: "Ping", Version: "2020-01-01",
		Params: url.Values{"B": {"x y"}, "A": {"1"}}}, &out)
	if err != nil || out.Code != "OK" {
		t.Fatalf("Call = %v, out = %+v", err, out)
	}
}

func TestCallReturnsAPIError(t *testing.T) {
	c, host := newTestClient(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
		_, _ = io.WriteString(w, `{"Code":"Forbidden.RAMUserAccessDenied","Message":"denied","RequestId":"r1"}`)
	})
	err := c.Call(context.Background(), Request{Host: host, Action: "Ping", Version: "v"}, &struct{}{})
	var ae *APIError
	if !errors.As(err, &ae) || ae.Code != "Forbidden.RAMUserAccessDenied" || ae.RequestID != "r1" || ae.ServerSide() || IsTransport(err) {
		t.Fatalf("err = %#v", err)
	}
}

func TestCallKeepsRawBodyWithoutCode(t *testing.T) {
	c, host := newTestClient(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = io.WriteString(w, "<html>bad gateway</html>")
	})
	err := c.Call(context.Background(), Request{Host: host, Action: "Ping", Version: "v"}, &struct{}{})
	var ae *APIError
	if !errors.As(err, &ae) || !ae.ServerSide() || !strings.Contains(ae.Message, "bad gateway") {
		t.Fatalf("err = %#v", err)
	}
}

func TestCallTransportError(t *testing.T) {
	c, host := newTestClient(t, func(http.ResponseWriter, *http.Request) {})
	c.client = &http.Client{Transport: failingTransport{}}
	err := c.Call(context.Background(), Request{Host: host, Action: "Ping", Version: "v"}, &struct{}{})
	if !IsTransport(err) {
		t.Fatalf("err = %v, want transport error", err)
	}
	var ae *APIError
	if errors.As(err, &ae) {
		t.Fatal("网络错误不应是 APIError")
	}
}

type failingTransport struct{}

func (failingTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, errors.New("connection refused")
}

func TestAPIErrorServerSide(t *testing.T) {
	for status, want := range map[int]bool{500: true, 503: true, 429: false, 400: false, 403: false} {
		if got := (&APIError{HTTPStatus: status}).ServerSide(); got != want {
			t.Errorf("ServerSide(%d) = %v, want %v", status, got, want)
		}
	}
}
