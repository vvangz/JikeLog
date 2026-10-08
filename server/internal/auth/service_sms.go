package auth

import (
	"context"
	"fmt"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

// SMSLoginResult 为短信登录结果：要么已登录，要么需要用注册凭证完善注册。
type SMSLoginResult struct {
	Session            *Session
	RegistrationTicket string
	Phone              string
}

// VerifyCaptcha 校验人机验证结果。
func (s *Service) VerifyCaptcha(ctx context.Context, param, ip string) error {
	ok, err := s.d.Captcha.Verify(ctx, param, ip)
	if err != nil {
		return fmt.Errorf("人机验证失败: %w", err)
	}
	if !ok {
		return errCaptchaFailed
	}
	return nil
}

// SendAuthSMS 发送登录或找回密码验证码。找回密码时号码未注册也返回成功但不发送，
// 且同样占用频率额度，使调用方无法据此判断号码是否已注册。
func (s *Service) SendAuthSMS(ctx context.Context, phone string, purpose Purpose, captcha, ip string) error {
	if err := s.VerifyCaptcha(ctx, captcha, ip); err != nil {
		return err
	}
	if err := s.d.SMS.CheckRate(ctx, phone, ip); err != nil {
		return err
	}
	if purpose == PurposeResetPassword {
		_, err := s.d.Tx.Queries().GetUserByPhone(ctx, phone)
		if db.IsNotFound(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("查询用户失败: %w", err)
		}
	}
	return s.d.SMS.Send(ctx, purpose, phone)
}

// SendSMS 发送验证码（不做人机验证，供已登录场景使用）。
func (s *Service) SendSMS(ctx context.Context, phone string, purpose Purpose, ip string) error {
	if err := s.d.SMS.CheckRate(ctx, phone, ip); err != nil {
		return err
	}
	return s.d.SMS.Send(ctx, purpose, phone)
}

// VerifySMS 校验并消费验证码。
func (s *Service) VerifySMS(ctx context.Context, purpose Purpose, phone, code string) error {
	return s.d.SMS.Verify(ctx, purpose, phone, code)
}

// LoginSMS 用手机号验证码登录；号码未绑定账号时签发注册凭证。
func (s *Service) LoginSMS(ctx context.Context, phone, code string, dev DeviceMeta, ip string) (SMSLoginResult, error) {
	if err := s.limitLoginIP(ctx, ip); err != nil {
		return SMSLoginResult{}, err
	}
	if err := s.d.SMS.Verify(ctx, PurposeLogin, phone, code); err != nil {
		return SMSLoginResult{}, err
	}
	user, err := s.d.Tx.Queries().GetUserByPhone(ctx, phone)
	if db.IsNotFound(err) {
		ticket, err := s.d.Tickets.Issue(ctx, phone)
		if err != nil {
			return SMSLoginResult{}, err
		}
		return SMSLoginResult{RegistrationTicket: ticket, Phone: phone}, nil
	}
	if err != nil {
		return SMSLoginResult{}, fmt.Errorf("查询用户失败: %w", err)
	}
	// 短信登录成功说明本人持有手机，解除密码错误导致的锁定
	_ = s.d.Limiter.Reset(ctx, loginFailKey(user.Username))
	var sess Session
	err = s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		sess, err = s.openSession(ctx, q, user, dev, ip)
		return err
	})
	if err != nil {
		return SMSLoginResult{}, err
	}
	return SMSLoginResult{Session: &sess}, nil
}

// CompleteSMSRegistration 用注册凭证创建绑定该手机号的账号。凭证只在账号创建成功后作废，
// 用户名被占用等可纠正的错误不会浪费凭证。
func (s *Service) CompleteSMSRegistration(ctx context.Context, ticket string, nu NewUser, dev DeviceMeta, ip string) (Session, error) {
	phone, ok, err := s.d.Tickets.Peek(ctx, ticket)
	if err != nil {
		return Session{}, err
	}
	if !ok {
		return Session{}, errTicketInvalid
	}
	nu.Phone = &phone
	sess, err := s.createAccount(ctx, nu, dev, ip)
	if err != nil {
		return Session{}, err
	}
	if err := s.d.Tickets.Consume(ctx, ticket); err != nil {
		s.d.Logger.WarnContext(ctx, "consume registration ticket failed", "error", err)
	}
	return sess, nil
}

// ResetPassword 用手机验证码重置密码，并让该账号所有设备下线。
func (s *Service) ResetPassword(ctx context.Context, phone, code, newPassword string) error {
	if err := s.d.SMS.Verify(ctx, PurposeResetPassword, phone, code); err != nil {
		return err
	}
	user, err := s.d.Tx.Queries().GetUserByPhone(ctx, phone)
	if db.IsNotFound(err) {
		return ErrSMSCodeInvalid
	}
	if err != nil {
		return fmt.Errorf("查询用户失败: %w", err)
	}
	if err := s.SetPassword(ctx, user.ID, newPassword, nil); err != nil {
		return err
	}
	_ = s.d.Limiter.Reset(ctx, loginFailKey(user.Username))
	return nil
}
