package account

import (
	"context"
	"fmt"
	"net/http"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

var (
	errPhoneTaken = httpx.NewError(http.StatusConflict, auth.CodePhoneTaken, "该手机号已绑定其他账号")
	errSamePhone  = httpx.Validation(map[string]string{"phone": "与当前绑定的手机号相同"})
	errNeedPhone  = httpx.Validation(map[string]string{"phone": "请输入要绑定的手机号"})
	errNeedOldOTP = httpx.Validation(map[string]string{"currentCode": "换绑需要当前手机号的验证码"})
)

// SendSMS 发送账号操作验证码：bind_phone 发往待绑定的新号码，verify_current 发往当前号码。
// 新号码已被其他账号绑定时同样返回成功但不发送，且照常占用频率额度，不泄露号码是否已注册。
func (s *Service) SendSMS(ctx context.Context, p auth.Principal, purpose auth.Purpose, phone, captcha string) error {
	u, err := s.currentUser(ctx, p)
	if err != nil {
		return err
	}
	ip := httpx.ClientIPFrom(ctx)
	if err := s.auth.VerifyCaptcha(ctx, captcha, ip); err != nil {
		return err
	}
	switch purpose {
	case auth.PurposeVerifyCurrent:
		if u.Phone == nil {
			return errPhoneNotBound
		}
		return s.auth.SendSMS(ctx, *u.Phone, purpose, ip)
	case auth.PurposeBindPhone:
		if phone == "" {
			return errNeedPhone
		}
		if u.Phone != nil && *u.Phone == phone {
			return errSamePhone
		}
		if err := s.auth.CheckSMSRate(ctx, phone, ip); err != nil {
			return err
		}
		taken, err := s.phoneTakenByOther(ctx, u, phone)
		if err != nil || taken {
			return err
		}
		return s.auth.SendCode(ctx, phone, purpose)
	default:
		return httpx.Validation(map[string]string{"purpose": "不支持的验证码用途"})
	}
}

func (s *Service) phoneTakenByOther(ctx context.Context, u dbgen.User, phone string) (bool, error) {
	other, err := s.tx.Queries().GetUserByPhone(ctx, phone)
	if db.IsNotFound(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("查询手机号失败: %w", err)
	}
	return other.ID != u.ID, nil
}

// BindPhone 绑定或换绑手机号：需要当前密码与新号码的验证码，换绑时还需当前号码的验证码。
// 先校验验证码（证明持有新号码）再写入；号码被占用由唯一约束兜底。
func (s *Service) BindPhone(ctx context.Context, p auth.Principal, in BindPhoneInput) (dbgen.User, error) {
	u, err := s.currentUser(ctx, p)
	if err != nil {
		return dbgen.User{}, err
	}
	if u.Phone != nil && *u.Phone == in.Phone {
		return dbgen.User{}, errSamePhone
	}
	if u.Phone != nil && in.CurrentCode == "" {
		return dbgen.User{}, errNeedOldOTP
	}
	if err := s.verifyIdentity(ctx, u, &in.Password, nil); err != nil {
		return dbgen.User{}, err
	}
	if err := s.auth.VerifySMS(ctx, auth.PurposeBindPhone, in.Phone, in.Code); err != nil {
		return dbgen.User{}, err
	}
	if u.Phone != nil {
		if err := s.auth.VerifySMS(ctx, auth.PurposeVerifyCurrent, *u.Phone, in.CurrentCode); err != nil {
			return dbgen.User{}, err
		}
	}
	if err := s.tx.Queries().UpdateUserPhone(ctx, dbgen.UpdateUserPhoneParams{ID: u.ID, Phone: &in.Phone}); err != nil {
		if db.IsUniqueViolation(err, "users_phone_key") {
			return dbgen.User{}, errPhoneTaken
		}
		return dbgen.User{}, fmt.Errorf("绑定手机号失败: %w", err)
	}
	u.Phone = &in.Phone
	return u, nil
}

// BindPhoneInput 为绑定手机号的已校验参数。
type BindPhoneInput struct {
	Phone       string
	Code        string
	Password    string
	CurrentCode string
}
