package account

import (
	"context"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// Handler 实现 account 标签下的接口。所有接口都需要登录（由认证中间件保证）。
type Handler struct {
	svc *Service
}

// NewHandler 创建 Handler。
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

var errEmptyBody = httpx.Validation(map[string]string{"body": "请求体不能为空"})

// maxSecretBytes 限制待校验密码的长度，避免超长输入消耗哈希计算资源。
const maxSecretBytes = 512

func checkSecret(f auth.FieldErrors, field string, v *string) {
	if v != nil && len(*v) > maxSecretBytes {
		f.Add(field, "内容过长")
	}
}

func userEnvelope(ctx context.Context, u apigen.User) apigen.UserEnvelope {
	base := httpx.Base(ctx, nil)
	return apigen.UserEnvelope{Success: base.Success, RequestId: base.RequestId, Data: u}
}

func settingsEnvelope(ctx context.Context, st apigen.Settings) apigen.SettingsEnvelope {
	base := httpx.Base(ctx, nil)
	return apigen.SettingsEnvelope{Success: base.Success, RequestId: base.RequestId, Data: st}
}

// GetMe 实现 GET /api/v1/me。
func (h *Handler) GetMe(ctx context.Context, _ apigen.GetMeRequestObject) (apigen.GetMeResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	u, err := h.svc.currentUser(ctx, p)
	if err != nil {
		return nil, err
	}
	return apigen.GetMe200JSONResponse(userEnvelope(ctx, auth.ToUser(u))), nil
}

// UpdateMe 实现 PATCH /api/v1/me。
func (h *Handler) UpdateMe(ctx context.Context, req apigen.UpdateMeRequestObject) (apigen.UpdateMeResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	f := auth.FieldErrors{}
	nick := auth.CheckNickname(f, "nickname", &req.Body.Nickname)
	if err := f.Err(); err != nil {
		return nil, err
	}
	u, err := h.svc.UpdateNickname(ctx, p, nick)
	if err != nil {
		return nil, err
	}
	return apigen.UpdateMe200JSONResponse(userEnvelope(ctx, auth.ToUser(u))), nil
}

// SendAccountSms 实现 POST /api/v1/me/sms/send。
func (h *Handler) SendAccountSms(ctx context.Context, req apigen.SendAccountSmsRequestObject) (apigen.SendAccountSmsResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := auth.FieldErrors{}
	phone := ""
	if b.Phone != nil && *b.Phone != "" {
		phone = auth.CheckPhone(f, "phone", *b.Phone)
	}
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
	if err := h.svc.SendSMS(ctx, p, auth.Purpose(b.Purpose), phone, captcha); err != nil {
		return nil, err
	}
	return apigen.SendAccountSms200JSONResponse(auth.SMSSentEnvelope(ctx)), nil
}

// ChangePassword 实现 PUT /api/v1/me/password。
func (h *Handler) ChangePassword(ctx context.Context, req apigen.ChangePasswordRequestObject) (apigen.ChangePasswordResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := auth.FieldErrors{}
	auth.CheckPassword(f, "newPassword", b.NewPassword)
	checkSecret(f, "currentPassword", b.CurrentPassword)
	if b.SmsCode != nil && *b.SmsCode != "" {
		auth.CheckSMSCode(f, "smsCode", *b.SmsCode)
	}
	if err := f.Err(); err != nil {
		return nil, err
	}
	if err := h.svc.ChangePassword(ctx, p, b.CurrentPassword, b.SmsCode, b.NewPassword); err != nil {
		return nil, err
	}
	return apigen.ChangePassword200JSONResponse(auth.AckEnvelope(ctx)), nil
}

// BindPhone 实现 PUT /api/v1/me/phone。
func (h *Handler) BindPhone(ctx context.Context, req apigen.BindPhoneRequestObject) (apigen.BindPhoneResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	b := req.Body
	if b == nil {
		return nil, errEmptyBody
	}
	f := auth.FieldErrors{}
	in := BindPhoneInput{Phone: auth.CheckPhone(f, "phone", b.Phone), Code: b.Code, Password: b.CurrentPassword}
	auth.CheckSMSCode(f, "code", b.Code)
	if b.CurrentPassword == "" || len(b.CurrentPassword) > maxSecretBytes {
		f.Add("currentPassword", "请输入当前密码")
	}
	if b.CurrentCode != nil && *b.CurrentCode != "" {
		auth.CheckSMSCode(f, "currentCode", *b.CurrentCode)
		in.CurrentCode = *b.CurrentCode
	}
	if err := f.Err(); err != nil {
		return nil, err
	}
	u, err := h.svc.BindPhone(ctx, p, in)
	if err != nil {
		return nil, err
	}
	return apigen.BindPhone200JSONResponse(userEnvelope(ctx, auth.ToUser(u))), nil
}

// DeleteAccount 实现 POST /api/v1/me/deletion。
func (h *Handler) DeleteAccount(ctx context.Context, req apigen.DeleteAccountRequestObject) (apigen.DeleteAccountResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	f := auth.FieldErrors{}
	checkSecret(f, "currentPassword", req.Body.CurrentPassword)
	if err := f.Err(); err != nil {
		return nil, err
	}
	if err := h.svc.DeleteAccount(ctx, p, req.Body.CurrentPassword, req.Body.SmsCode); err != nil {
		return nil, err
	}
	return apigen.DeleteAccount200JSONResponse(auth.AckEnvelope(ctx)), nil
}

// ListDevices 实现 GET /api/v1/me/devices。
func (h *Handler) ListDevices(ctx context.Context, _ apigen.ListDevicesRequestObject) (apigen.ListDevicesResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	devices, err := h.svc.ListDevices(ctx, p)
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.ListDevices200JSONResponse{Success: base.Success, RequestId: base.RequestId, Data: devices}, nil
}

// RevokeDevice 实现 DELETE /api/v1/me/devices/{deviceId}。
func (h *Handler) RevokeDevice(ctx context.Context, req apigen.RevokeDeviceRequestObject) (apigen.RevokeDeviceResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if err := h.svc.RevokeDevice(ctx, p, req.DeviceId); err != nil {
		return nil, err
	}
	return apigen.RevokeDevice200JSONResponse(auth.AckEnvelope(ctx)), nil
}

// GetSettings 实现 GET /api/v1/me/settings。
func (h *Handler) GetSettings(ctx context.Context, _ apigen.GetSettingsRequestObject) (apigen.GetSettingsResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	st, err := h.svc.GetSettings(ctx, p)
	if err != nil {
		return nil, err
	}
	return apigen.GetSettings200JSONResponse(settingsEnvelope(ctx, ToSettings(st))), nil
}

// UpdateSettings 实现 PUT /api/v1/me/settings。
func (h *Handler) UpdateSettings(ctx context.Context, req apigen.UpdateSettingsRequestObject) (apigen.UpdateSettingsResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	st, err := h.svc.UpdateSettings(ctx, p, *req.Body)
	if err != nil {
		return nil, err
	}
	return apigen.UpdateSettings200JSONResponse(settingsEnvelope(ctx, ToSettings(st))), nil
}
