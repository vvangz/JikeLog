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
		if err := s.checkPhoneAvailable(ctx, u, phone); err != nil {
			return err
		}
		return s.auth.SendSMS(ctx, phone, purpose, ip)
	default:
		return httpx.Validation(map[string]string{"purpose": "不支持的验证码用途"})
	}
}

func (s *Service) checkPhoneAvailable(ctx context.Context, u dbgen.User, phone string) error {
	if u.Phone != nil && *u.Phone == phone {
		return errSamePhone
	}
	other, err := s.tx.Queries().GetUserByPhone(ctx, phone)
	if db.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("查询手机号失败: %w", err)
	}
	if other.ID != u.ID {
		return errPhoneTaken
	}
	return nil
}

// BindPhone 绑定或换绑手机号：新号码的验证码必需，换绑时还需当前号码的验证码。
func (s *Service) BindPhone(ctx context.Context, p auth.Principal, phone, code string, currentCode *string) (dbgen.User, error) {
	u, err := s.currentUser(ctx, p)
	if err != nil {
		return dbgen.User{}, err
	}
	if err := s.checkPhoneAvailable(ctx, u, phone); err != nil {
		return dbgen.User{}, err
	}
	if u.Phone != nil {
		if currentCode == nil || *currentCode == "" {
			return dbgen.User{}, errNeedOldOTP
		}
		if err := s.auth.VerifySMS(ctx, auth.PurposeVerifyCurrent, *u.Phone, *currentCode); err != nil {
			return dbgen.User{}, err
		}
	}
	if err := s.auth.VerifySMS(ctx, auth.PurposeBindPhone, phone, code); err != nil {
		return dbgen.User{}, err
	}
	if err := s.tx.Queries().UpdateUserPhone(ctx, dbgen.UpdateUserPhoneParams{ID: u.ID, Phone: &phone}); err != nil {
		if db.IsUniqueViolation(err, "users_phone_key") {
			return dbgen.User{}, errPhoneTaken
		}
		return dbgen.User{}, fmt.Errorf("绑定手机号失败: %w", err)
	}
	u.Phone = &phone
	return u, nil
}
