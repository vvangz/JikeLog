package auth

import (
	"context"
	"strings"
	"testing"

	"github.com/vvangz/JikeLog/server/internal/apigen"
)

func TestNormalizePhone(t *testing.T) {
	ok := map[string]string{
		"13812345678":       "+8613812345678",
		"+8613812345678":    "+8613812345678",
		" 138 1234 5678 ":   "+8613812345678",
		"+86 138-1234-5678": "+8613812345678",
		"19912345678":       "+8619912345678",
	}
	for in, want := range ok {
		if got, valid := NormalizePhone(in); !valid || got != want {
			t.Errorf("NormalizePhone(%q) = %q, %v; want %q", in, got, valid, want)
		}
	}
	for _, in := range []string{"", "12812345678", "1381234567", "138123456789", "+1 2025550123", "abc", "+8512345678901"} {
		if _, valid := NormalizePhone(in); valid {
			t.Errorf("NormalizePhone(%q) 应无效", in)
		}
	}
}

func TestMaskPhone(t *testing.T) {
	if got := MaskPhone("+8613812345678"); got != "138****5678" {
		t.Errorf("MaskPhone = %q", got)
	}
	if got := MaskPhone("+86123"); got != "****" {
		t.Errorf("过短号码 MaskPhone = %q", got)
	}
}

func TestCheckPassword(t *testing.T) {
	good := []string{"secret123", "密码abc123", strings.Repeat("a1", 32)}
	bad := []string{"short1", "onlyletters", "12345678", strings.Repeat("a1", 33), "secret12\x00"}
	for _, pw := range good {
		f := FieldErrors{}
		CheckPassword(f, "p", pw)
		if f.Err() != nil {
			t.Errorf("密码 %q 应合法: %v", pw, f)
		}
	}
	for _, pw := range bad {
		f := FieldErrors{}
		CheckPassword(f, "p", pw)
		if f.Err() == nil {
			t.Errorf("密码 %q 应被拒绝", pw)
		}
	}
}

func TestCheckNicknameAndDevice(t *testing.T) {
	f := FieldErrors{}
	if got := CheckNickname(f, "n", nil); got != "" || len(f) != 0 {
		t.Error("nil 昵称应返回空串")
	}
	bad := "a\x07b"
	CheckNickname(f, "n", &bad)
	if _, ok := f["n"]; !ok {
		t.Error("昵称含控制字符应被拒绝")
	}

	long := strings.Repeat("型", 80) + "\x00"
	f = FieldErrors{}
	meta := CheckDevice(f, apigen.DeviceInfo{InstallationId: "install-1", Platform: apigen.DeviceInfoPlatformAndroid, Model: &long})
	if len(f) != 0 {
		t.Errorf("展示字段过长不应报错: %v", f)
	}
	if n := len([]rune(meta.Model)); n != maxDeviceFieldLen || strings.ContainsRune(meta.Model, 0) {
		t.Errorf("Model 应被截断并去掉控制字符，长度 %d", n)
	}
	f.Add("x", "first")
	f.Add("x", "second")
	if f["x"] != "first" {
		t.Error("同一字段应保留第一条错误")
	}
	f = FieldErrors{}
	CheckSMSCode(f, "c", "12345a")
	if f.Err() == nil {
		t.Error("非数字验证码应被拒绝")
	}
}

func TestNoopCaptchaAndMockSender(t *testing.T) {
	if ok, err := (NoopCaptcha{}).Verify(context.Background(), "", ""); !ok || err != nil {
		t.Error("NoopCaptcha 应总是通过")
	}
	m := &MockSender{}
	if m.LastCode("+86") != "" {
		t.Error("未发送时应返回空串")
	}
	_ = m.SendCode(context.Background(), "+8613800000000", "123456", PurposeLogin)
	if m.LastCode("+8613800000000") != "123456" {
		t.Error("LastCode 应返回最近一次验证码")
	}
}
