package auth

import (
	"context"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// Handler 实现 auth 标签下的接口。
type Handler struct {
	svc *Service
}

// NewHandler 创建 Handler。
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// Err 有错误时返回 422 VALIDATION_FAILED，否则返回 nil。
func (f FieldErrors) Err() error {
	if len(f) == 0 {
		return nil
	}
	return httpx.Validation(f)
}

// errEmptyBody 在请求体缺失时返回（生成代码对空请求体不报错）。
var errEmptyBody = httpx.Validation(map[string]string{"body": "请求体不能为空"})

// Register 实现 POST /api/v1/auth/register。
func (h *Handler) Register(ctx context.Context, req apigen.RegisterRequestObject) (apigen.RegisterResponseObject, error) {
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := FieldErrors{}
	CheckUsername(f, "username", b.Username)
	CheckPassword(f, "password", b.Password)
	nick := CheckNickname(f, "nickname", b.Nickname)
	dev := CheckDevice(f, b.Device)
	if err := f.Err(); err != nil {
		return nil, err
	}
	sess, err := h.svc.Register(ctx, NewUser{Username: b.Username, Password: b.Password, Nickname: nick}, dev, httpx.ClientIPFrom(ctx))
	if err != nil {
		return nil, err
	}
	return apigen.Register201JSONResponse(sessionEnvelope(ctx, sess)), nil
}

// LoginWithPassword 实现 POST /api/v1/auth/login/password。
func (h *Handler) LoginWithPassword(ctx context.Context, req apigen.LoginWithPasswordRequestObject) (apigen.LoginWithPasswordResponseObject, error) {
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := FieldErrors{}
	if b.Username == "" || len(b.Username) > 64 {
		f.Add("username", "请输入用户名")
	}
	if b.Password == "" || len(b.Password) > 128 {
		f.Add("password", "请输入密码")
	}
	dev := CheckDevice(f, b.Device)
	if err := f.Err(); err != nil {
		return nil, err
	}
	sess, err := h.svc.LoginPassword(ctx, b.Username, b.Password, dev, httpx.ClientIPFrom(ctx))
	if err != nil {
		return nil, err
	}
	return apigen.LoginWithPassword200JSONResponse(sessionEnvelope(ctx, sess)), nil
}

// SendAuthSms 实现 POST /api/v1/auth/sms/send。
func (h *Handler) SendAuthSms(ctx context.Context, req apigen.SendAuthSmsRequestObject) (apigen.SendAuthSmsResponseObject, error) {
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := FieldErrors{}
	phone := CheckPhone(f, "phone", b.Phone)
	if !b.Purpose.Valid() {
		f.Add("purpose", "不支持的验证码用途")
	}
	if err := f.Err(); err != nil {
		return nil, err
	}
	captcha := ""
	if b.CaptchaVerifyParam != nil {
		captcha = *b.CaptchaVerifyParam
	}
	if err := h.svc.SendAuthSMS(ctx, phone, Purpose(b.Purpose), captcha, httpx.ClientIPFrom(ctx)); err != nil {
		return nil, err
	}
	return apigen.SendAuthSms200JSONResponse(SMSSentEnvelope(ctx)), nil
}

// LoginWithSms 实现 POST /api/v1/auth/login/sms。
func (h *Handler) LoginWithSms(ctx context.Context, req apigen.LoginWithSmsRequestObject) (apigen.LoginWithSmsResponseObject, error) {
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := FieldErrors{}
	phone := CheckPhone(f, "phone", b.Phone)
	CheckSMSCode(f, "code", b.Code)
	dev := CheckDevice(f, b.Device)
	if err := f.Err(); err != nil {
		return nil, err
	}
	res, err := h.svc.LoginSMS(ctx, phone, b.Code, dev, httpx.ClientIPFrom(ctx))
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	out := apigen.LoginWithSms200JSONResponse{Success: base.Success, RequestId: base.RequestId}
	if res.Session != nil {
		s := toAuthSession(*res.Session)
		out.Data = apigen.SmsLoginResult{Status: apigen.SmsLoginResultStatusAuthenticated, Session: &s}
		return out, nil
	}
	masked := MaskPhone(res.Phone)
	out.Data = apigen.SmsLoginResult{
		Status:             apigen.SmsLoginResultStatusRegistrationRequired,
		RegistrationTicket: &res.RegistrationTicket,
		PhoneMasked:        &masked,
	}
	return out, nil
}

// CompleteSmsRegistration 实现 POST /api/v1/auth/register/sms。
func (h *Handler) CompleteSmsRegistration(ctx context.Context, req apigen.CompleteSmsRegistrationRequestObject) (apigen.CompleteSmsRegistrationResponseObject, error) {
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := FieldErrors{}
	if b.RegistrationTicket == "" || len(b.RegistrationTicket) > 128 {
		f.Add("registrationTicket", "注册凭证无效")
	}
	CheckUsername(f, "username", b.Username)
	CheckPassword(f, "password", b.Password)
	nick := CheckNickname(f, "nickname", b.Nickname)
	dev := CheckDevice(f, b.Device)
	if err := f.Err(); err != nil {
		return nil, err
	}
	nu := NewUser{Username: b.Username, Password: b.Password, Nickname: nick}
	sess, err := h.svc.CompleteSMSRegistration(ctx, b.RegistrationTicket, nu, dev, httpx.ClientIPFrom(ctx))
	if err != nil {
		return nil, err
	}
	return apigen.CompleteSmsRegistration201JSONResponse(sessionEnvelope(ctx, sess)), nil
}

// RefreshToken 实现 POST /api/v1/auth/refresh。
func (h *Handler) RefreshToken(ctx context.Context, req apigen.RefreshTokenRequestObject) (apigen.RefreshTokenResponseObject, error) {
	b := req.Body
	if b == nil || b.RefreshToken == "" || len(b.RefreshToken) > 128 {
		return nil, errRefreshInvalid
	}
	pair, err := h.svc.Refresh(ctx, b.RefreshToken, httpx.ClientIPFrom(ctx))
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.RefreshToken200JSONResponse{Success: base.Success, RequestId: base.RequestId, Data: toTokenPair(pair)}, nil
}

// ResetPassword 实现 POST /api/v1/auth/password/reset。
func (h *Handler) ResetPassword(ctx context.Context, req apigen.ResetPasswordRequestObject) (apigen.ResetPasswordResponseObject, error) {
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := FieldErrors{}
	phone := CheckPhone(f, "phone", b.Phone)
	CheckSMSCode(f, "code", b.Code)
	CheckPassword(f, "newPassword", b.NewPassword)
	if err := f.Err(); err != nil {
		return nil, err
	}
	if err := h.svc.ResetPassword(ctx, phone, b.Code, b.NewPassword); err != nil {
		return nil, err
	}
	return apigen.ResetPassword200JSONResponse(AckEnvelope(ctx)), nil
}

// Logout 实现 POST /api/v1/auth/logout。
func (h *Handler) Logout(ctx context.Context, _ apigen.LogoutRequestObject) (apigen.LogoutResponseObject, error) {
	p, err := MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if err := h.svc.Logout(ctx, p); err != nil {
		return nil, err
	}
	return apigen.Logout200JSONResponse(AckEnvelope(ctx)), nil
}

// AckEnvelope 构造 {ok: true} 信封。
func AckEnvelope(ctx context.Context) apigen.AckEnvelope {
	base := httpx.Base(ctx, nil)
	return apigen.AckEnvelope{Success: base.Success, RequestId: base.RequestId, Data: apigen.Ack{Ok: true}}
}

// SMSSentEnvelope 构造短信已发送信封。
func SMSSentEnvelope(ctx context.Context) apigen.SmsSentEnvelope {
	base := httpx.Base(ctx, nil)
	return apigen.SmsSentEnvelope{Success: base.Success, RequestId: base.RequestId, Data: apigen.SmsSent{
		CooldownSeconds:  int(SMSCooldown.Seconds()),
		ExpiresInSeconds: int(SMSCodeTTL.Seconds()),
	}}
}

// ToUser 把数据库用户转换为接口模型（手机号脱敏）。
func ToUser(u dbgen.User) apigen.User {
	out := apigen.User{Id: u.ID, Username: u.Username, Nickname: u.Nickname, CreatedAt: u.CreatedAt, HasPhone: u.Phone != nil}
	if u.Phone != nil {
		m := MaskPhone(*u.Phone)
		out.PhoneMasked = &m
	}
	return out
}

func toTokenPair(p TokenPair) apigen.TokenPair {
	return apigen.TokenPair{
		TokenType:        apigen.TokenPairTokenTypeBearer,
		AccessToken:      p.AccessToken,
		AccessExpiresAt:  p.AccessExpiresAt,
		RefreshToken:     p.RefreshToken,
		RefreshExpiresAt: p.RefreshExpiresAt,
	}
}

func toAuthSession(s Session) apigen.AuthSession {
	return apigen.AuthSession{User: ToUser(s.User), DeviceId: s.DeviceID, Tokens: toTokenPair(s.Tokens)}
}

func sessionEnvelope(ctx context.Context, s Session) apigen.AuthSessionEnvelope {
	base := httpx.Base(ctx, nil)
	return apigen.AuthSessionEnvelope{Success: base.Success, RequestId: base.RequestId, Data: toAuthSession(s)}
}
