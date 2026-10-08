package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/platform/cache"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

// Purpose 为验证码用途；不同用途的验证码互不通用。
type Purpose string

// 验证码用途。
const (
	PurposeLogin         Purpose = "login"
	PurposeResetPassword Purpose = "reset_password"
	PurposeBindPhone     Purpose = "bind_phone"
	PurposeVerifyCurrent Purpose = "verify_current"
)

// 验证码策略。
const (
	SMSCodeTTL       = 5 * time.Minute
	SMSCooldown      = 60 * time.Second
	smsMaxAttempts   = 5
	smsDailyPerPhone = 10
	smsHourlyPerIP   = 20
)

// 短信相关错误码。
const (
	CodeSMSRateLimited = "SMS_RATE_LIMITED"
	CodeSMSCodeInvalid = "SMS_CODE_INVALID"
	CodeSMSSendFailed  = "SMS_SEND_FAILED"
)

// ErrSMSCodeInvalid 表示验证码错误、过期或尝试次数过多（不区分原因，避免被用来探测）。
var ErrSMSCodeInvalid = httpx.NewError(http.StatusBadRequest, CodeSMSCodeInvalid, "验证码错误或已过期")

// SMSSender 发送短信验证码。生产实现为阿里云短信（v0.9.0），开发与测试使用 MockSender。
type SMSSender interface {
	SendCode(ctx context.Context, phone, code string, purpose Purpose) error
}

// MockSender 不真正发送短信，只把验证码写入日志，并记住每个号码最近一次的验证码供测试读取。
type MockSender struct {
	Logger *slog.Logger
	mu     sync.Mutex
	last   map[string]string
}

// SendCode 实现 SMSSender。
func (m *MockSender) SendCode(ctx context.Context, phone, code string, purpose Purpose) error {
	m.mu.Lock()
	if m.last == nil {
		m.last = map[string]string{}
	}
	m.last[phone] = code
	m.mu.Unlock()
	if m.Logger != nil {
		m.Logger.InfoContext(ctx, "mock sms sent（仅开发环境）", "phone", MaskPhone(phone), "purpose", string(purpose), "code", code)
	}
	return nil
}

// LastCode 返回发给该号码的最近一次验证码。
func (m *MockSender) LastCode(phone string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.last[phone]
}

// SMSCodes 生成、发送与校验短信验证码，并执行频率限制。验证码只以哈希形式存放在 Redis 中。
type SMSCodes struct {
	rdb     redis.Cmdable
	limiter *ratelimit.Limiter
	sender  SMSSender
	logger  *slog.Logger
}

// NewSMSCodes 创建 SMSCodes。
func NewSMSCodes(rdb redis.Cmdable, limiter *ratelimit.Limiter, sender SMSSender, logger *slog.Logger) *SMSCodes {
	return &SMSCodes{rdb: rdb, limiter: limiter, sender: sender, logger: logger}
}

func codeKey(p Purpose, phone string) string {
	return cache.KeyPrefix + "sms:code:" + string(p) + ":" + phone
}
func cooldownKey(phone string) string { return cache.KeyPrefix + "sms:cd:" + phone }

func hashCode(p Purpose, phone, code string) string {
	sum := sha256.Sum256([]byte(string(p) + "|" + phone + "|" + code))
	return hex.EncodeToString(sum[:])
}

// CheckRate 执行发送前的频率检查（冷却、单号每日上限、单 IP 每小时上限）并占用冷却期。
// 与 Send 分开，是为了让"手机号未注册时不实际发送"的分支也受同样的限制，从而无法通过响应差异探测号码。
func (s *SMSCodes) CheckRate(ctx context.Context, phone, ip string) error {
	ok, err := s.rdb.SetNX(ctx, cooldownKey(phone), 1, SMSCooldown).Result()
	if err != nil {
		return fmt.Errorf("检查短信冷却失败: %w", err)
	}
	if !ok {
		ttl, err := s.rdb.PTTL(ctx, cooldownKey(phone)).Result()
		if err != nil || ttl <= 0 {
			ttl = SMSCooldown
		}
		return httpx.TooManyRequests(CodeSMSRateLimited, "验证码发送过于频繁，请稍后再试", ttl)
	}
	checks := []struct {
		key    string
		limit  int64
		window time.Duration
		msg    string
	}{
		{"sms:ip:" + ip, smsHourlyPerIP, time.Hour, "当前网络发送验证码过于频繁，请稍后再试"},
		{"sms:day:" + phone, smsDailyPerPhone, 24 * time.Hour, "该手机号今日验证码发送次数已达上限"},
	}
	for _, c := range checks {
		r, err := s.limiter.Hit(ctx, c.key, c.limit, c.window)
		if err != nil {
			return err
		}
		if !r.Allowed {
			return httpx.TooManyRequests(CodeSMSRateLimited, c.msg, r.RetryAfter)
		}
	}
	return nil
}

// Send 生成验证码、保存哈希并发送。调用前必须先通过 CheckRate。
func (s *SMSCodes) Send(ctx context.Context, p Purpose, phone string) error {
	code, err := randomCode()
	if err != nil {
		return err
	}
	key := codeKey(p, phone)
	pipe := s.rdb.TxPipeline()
	pipe.Del(ctx, key)
	pipe.HSet(ctx, key, "hash", hashCode(p, phone, code), "attempts", 0)
	pipe.PExpire(ctx, key, SMSCodeTTL)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("保存验证码失败: %w", err)
	}
	if err := s.sender.SendCode(ctx, phone, code, p); err != nil {
		s.logger.ErrorContext(ctx, "sms send failed", "phone", MaskPhone(phone), "purpose", string(p), "error", err)
		// 发送失败时释放冷却，允许用户立即重试
		_ = s.rdb.Del(ctx, key, cooldownKey(phone)).Err()
		return httpx.NewError(http.StatusServiceUnavailable, CodeSMSSendFailed, "验证码发送失败，请稍后重试")
	}
	return nil
}

// 校验成功或尝试次数用尽时删除验证码；失败时累加尝试次数。
// 返回 1 = 正确，0 = 错误，-1 = 不存在或已作废。
var verifyScript = redis.NewScript(`
local h = redis.call('HGET', KEYS[1], 'hash')
if not h then return -1 end
if h == ARGV[1] then
  redis.call('DEL', KEYS[1])
  return 1
end
local n = redis.call('HINCRBY', KEYS[1], 'attempts', 1)
if n >= tonumber(ARGV[2]) then redis.call('DEL', KEYS[1]) end
return 0
`)

// Verify 校验并消费验证码：正确时返回 nil，验证码随即失效；否则返回 ErrSMSCodeInvalid。
func (s *SMSCodes) Verify(ctx context.Context, p Purpose, phone, code string) error {
	res, err := verifyScript.Run(ctx, s.rdb, []string{codeKey(p, phone)}, hashCode(p, phone, code), smsMaxAttempts).Int()
	if err != nil {
		return fmt.Errorf("校验验证码失败: %w", err)
	}
	if res != 1 {
		return ErrSMSCodeInvalid
	}
	return nil
}

func randomCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", fmt.Errorf("生成验证码失败: %w", err)
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}
