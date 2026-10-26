package server

import (
	"io"
	"log/slog"
	"testing"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/aliyun"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
)

func TestAliyunProvidersWired(t *testing.T) {
	cfg := testConfig(t, map[string]string{
		"JIKELOG_SMS_PROVIDER":             "aliyun",
		"JIKELOG_CAPTCHA_PROVIDER":         "aliyun",
		"JIKELOG_SMS_SIGN_NAME":            "签名",
		"JIKELOG_CAPTCHA_SCENE_ID":         "scene",
		"JIKELOG_CAPTCHA_PREFIX":           "prefix",
		"JIKELOG_ALIYUN_ACCESS_KEY_ID":     "ak",
		"JIKELOG_ALIYUN_ACCESS_KEY_SECRET": "sk",
	})
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	api := aliyun.NewClient(aliyun.Credentials{}, nil)
	sender, err := newSMSSender(cfg.SMS, api, logger)
	if _, ok := sender.(*auth.AliyunSender); err != nil || !ok {
		t.Fatalf("newSMSSender() = %T, %v", sender, err)
	}
	if _, ok := newCaptcha(cfg.Captcha, api, logger).(*auth.AliyunCaptcha); !ok {
		t.Fatal("JIKELOG_CAPTCHA_PROVIDER=aliyun 应使用阿里云验证码")
	}
	if _, ok := newCaptcha(config.Captcha{Provider: config.CaptchaProviderNone}, api, logger).(auth.NoopCaptcha); !ok {
		t.Fatal("JIKELOG_CAPTCHA_PROVIDER=none 不做人机验证")
	}
}
