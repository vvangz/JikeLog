package auth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/vvangz/JikeLog/server/internal/platform/aliyun"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// 阿里云接入点。短信认证属于号码认证服务（Dypnsapi），个人实名账号可用系统赠送的签名与模板；
// 验证码 2.0 在中国内地只有上海地域。
const (
	dypnsHost      = "dypnsapi.aliyuncs.com"
	dypnsVersion   = "2017-05-25"
	captchaHost    = "captcha.cn-shanghai.aliyuncs.com"
	captchaVersion = "2023-03-05"
)

// 号码认证服务的错误码。
const (
	dypnsOK            = "OK"
	dypnsDailyLimit    = "BUSINESS_LIMIT_CONTROL"
	dypnsFrequencyFail = "FREQUENCY_FAIL"
	dypnsBadPhone      = "MOBILE_NUMBER_ILLEGAL"
)

var (
	// errSMSProviderLimited 表示触发了短信通道（阿里云或运营商）对该号码的频控。
	errSMSProviderLimited = httpx.TooManyRequests(CodeSMSRateLimited, "该手机号验证码发送过于频繁，请稍后再试", SMSCooldown)
	// errSMSPhoneRejected 表示短信通道拒绝该号码（空号、非中国内地号码等）。
	errSMSPhoneRejected = httpx.Validation(map[string]string{"phone": "该手机号无法接收短信"})
)

// AliyunSMSConfig 为短信认证配置：签名必须是系统赠送签名，模板必须是与之配套的赠送模板。
type AliyunSMSConfig struct {
	SignName  string
	Templates map[Purpose]string
}

// AliyunSender 通过阿里云号码认证服务的短信认证（SendSmsVerifyCode）发送验证码。
// 验证码由本服务生成、以 HMAC 保存并自行校验（SMSCodes），阿里云只负责下发。
type AliyunSender struct {
	api    *aliyun.Client
	cfg    AliyunSMSConfig
	logger *slog.Logger
}

// NewAliyunSender 创建 AliyunSender。
func NewAliyunSender(api *aliyun.Client, cfg AliyunSMSConfig, logger *slog.Logger) *AliyunSender {
	return &AliyunSender{api: api, cfg: cfg, logger: logger}
}

type dypnsResponse struct {
	Code      string
	Message   string
	RequestID string `json:"RequestId"`
	Success   bool
}

// SendCode 实现 SMSSender。
func (a *AliyunSender) SendCode(ctx context.Context, phone, code string, purpose Purpose) error {
	tpl, ok := a.cfg.Templates[purpose]
	if !ok {
		return fmt.Errorf("没有为验证码用途 %q 配置短信模板", purpose)
	}
	local, ok := strings.CutPrefix(phone, "+86")
	if !ok {
		return errSMSPhoneRejected
	}
	param, err := json.Marshal(map[string]string{"code": code, "min": strconv.Itoa(int(SMSCodeTTL.Minutes()))})
	if err != nil {
		return fmt.Errorf("编码短信模板参数失败: %w", err)
	}
	var resp dypnsResponse
	err = a.api.Call(ctx, aliyun.Request{Host: dypnsHost, Action: "SendSmsVerifyCode", Version: dypnsVersion, Params: url.Values{
		"PhoneNumber":   {local},
		"SignName":      {a.cfg.SignName},
		"TemplateCode":  {tpl},
		"TemplateParam": {string(param)},
	}}, &resp)
	if err != nil {
		var apiErr *aliyun.APIError
		if !errors.As(err, &apiErr) {
			return err
		}
		resp = dypnsResponse{Code: apiErr.Code, Message: apiErr.Message, RequestID: apiErr.RequestID}
	}
	// 部分错误码带 isv. 前缀（与普通短信服务一致），两种写法都识别
	switch strings.TrimPrefix(resp.Code, "isv.") {
	case dypnsOK:
		return nil
	case dypnsDailyLimit, dypnsFrequencyFail:
		a.logger.WarnContext(ctx, "sms provider rate limited", "phone", MaskPhone(phone), "code", resp.Code, "requestId", resp.RequestID)
		return errSMSProviderLimited
	case dypnsBadPhone:
		return errSMSPhoneRejected
	default:
		return fmt.Errorf("阿里云短信认证返回 %s：%s（RequestId=%s）", resp.Code, resp.Message, resp.RequestID)
	}
}

// captchaFailOpenPerMinute 为阿里云不可用时每分钟最多放行的次数（全服务合计）。
// 超出后拒绝，防止有人借故障（或故意制造的故障）绕过人机验证大量发送短信。
const captchaFailOpenPerMinute = 20

// AliyunCaptcha 通过阿里云验证码 2.0（VerifyIntelligentCaptcha）校验客户端提交的人机验证结果。
type AliyunCaptcha struct {
	api     *aliyun.Client
	sceneID string
	logger  *slog.Logger
	now     func() time.Time

	mu         sync.Mutex
	openWindow time.Time
	openCount  int
}

// NewAliyunCaptcha 创建 AliyunCaptcha。sceneID 必须与客户端初始化验证码时使用的场景一致。
func NewAliyunCaptcha(api *aliyun.Client, sceneID string, logger *slog.Logger) *AliyunCaptcha {
	return &AliyunCaptcha{api: api, sceneID: sceneID, logger: logger, now: time.Now}
}

type captchaResponse struct {
	Code      string
	Message   string
	RequestID string `json:"RequestId"`
	Result    struct {
		VerifyResult bool
		VerifyCode   string
	}
}

// Verify 实现 CaptchaVerifier。按阿里云的容灾建议，没有得到响应（网络错误、超时）或阿里云服务端出错（5xx）时放行，
// 但每分钟放行次数有上限；其余错误（鉴权失败、限流、响应无法解析）一律不放行，避免配置错误或攻击被静默放行。
func (a *AliyunCaptcha) Verify(ctx context.Context, param, _ string) (bool, error) {
	if param == "" {
		return false, nil
	}
	var resp captchaResponse
	err := a.api.Call(ctx, aliyun.Request{Host: captchaHost, Action: "VerifyIntelligentCaptcha", Version: captchaVersion, Params: url.Values{
		"CaptchaVerifyParam": {param},
		"SceneId":            {a.sceneID},
	}}, &resp)
	if err != nil {
		if ctx.Err() != nil {
			return false, fmt.Errorf("校验人机验证被取消: %w", ctx.Err())
		}
		var apiErr *aliyun.APIError
		unavailable := aliyun.IsTransport(err) || (errors.As(err, &apiErr) && apiErr.ServerSide())
		if !unavailable {
			return false, err
		}
		if !a.allowFailOpen() {
			a.logger.ErrorContext(ctx, "captcha verify unavailable, fail-open budget exhausted", "error", err)
			return false, nil
		}
		a.logger.WarnContext(ctx, "captcha verify unavailable, failing open", "error", err)
		return true, nil
	}
	if !resp.Result.VerifyResult {
		a.logger.InfoContext(ctx, "captcha rejected", "verifyCode", resp.Result.VerifyCode,
			"code", resp.Code, "message", resp.Message, "requestId", resp.RequestID)
	}
	return resp.Result.VerifyResult, nil
}

func (a *AliyunCaptcha) allowFailOpen() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	now := a.now()
	if now.Sub(a.openWindow) >= time.Minute {
		a.openWindow, a.openCount = now, 0
	}
	if a.openCount >= captchaFailOpenPerMinute {
		return false
	}
	a.openCount++
	return true
}
