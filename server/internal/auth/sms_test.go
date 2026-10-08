package auth

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

type failingSender struct{}

func (failingSender) SendCode(context.Context, string, string, Purpose) error {
	return errors.New("gateway down")
}

func newRedis(t *testing.T) (*redis.Client, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	return rdb, mr
}

var discard = slog.New(slog.NewTextHandler(io.Discard, nil))

func TestSMSCodesSendAndVerify(t *testing.T) {
	rdb, mr := newRedis(t)
	sender := &MockSender{Logger: discard}
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), sender, discard)
	ctx := context.Background()
	phone := "+8613800000000"

	if err := codes.CheckRate(ctx, phone, "1.1.1.1"); err != nil {
		t.Fatal(err)
	}
	if err := codes.Send(ctx, PurposeLogin, phone); err != nil {
		t.Fatal(err)
	}
	code := sender.LastCode(phone)
	if !mr.Exists("jk:sms:code:login:" + phone) {
		t.Fatal("验证码应保存在 Redis")
	}
	if v := mr.HGet("jk:sms:code:login:"+phone, "hash"); v == code || v == "" {
		t.Error("Redis 中只应保存验证码哈希")
	}
	if err := codes.Verify(ctx, PurposeResetPassword, phone, code); !errors.Is(err, ErrSMSCodeInvalid) {
		t.Error("不同用途的验证码不能通用")
	}
	if err := codes.Verify(ctx, PurposeLogin, phone, code); err != nil {
		t.Fatalf("Verify() = %v", err)
	}
	if err := codes.Verify(ctx, PurposeLogin, phone, code); !errors.Is(err, ErrSMSCodeInvalid) {
		t.Error("验证码只能使用一次")
	}

	_ = codes.Send(ctx, PurposeLogin, phone)
	mr.FastForward(SMSCodeTTL + time.Second)
	if err := codes.Verify(ctx, PurposeLogin, phone, sender.LastCode(phone)); !errors.Is(err, ErrSMSCodeInvalid) {
		t.Error("过期验证码应失效")
	}
}

func TestSMSCodesSendFailureReleasesCooldown(t *testing.T) {
	rdb, mr := newRedis(t)
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), failingSender{}, discard)
	ctx := context.Background()
	phone := "+8613800000001"
	_ = codes.CheckRate(ctx, phone, "1.1.1.1")
	err := codes.Send(ctx, PurposeLogin, phone)
	var appErr *httpx.Error
	if !errors.As(err, &appErr) || appErr.Status != http.StatusServiceUnavailable || appErr.Code != CodeSMSSendFailed {
		t.Fatalf("Send() = %v, want 503 SMS_SEND_FAILED", err)
	}
	if mr.Exists("jk:sms:cd:"+phone) || mr.Exists("jk:sms:code:login:"+phone) {
		t.Error("发送失败应释放冷却并删除验证码")
	}
	if err := codes.CheckRate(ctx, phone, "1.1.1.1"); err != nil {
		t.Errorf("发送失败后应可立即重试: %v", err)
	}
}

func TestSMSCodesDailyLimit(t *testing.T) {
	rdb, mr := newRedis(t)
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), &MockSender{}, discard)
	ctx := context.Background()
	phone := "+8613800000002"
	for i := range smsDailyPerPhone {
		if err := codes.CheckRate(ctx, phone, "ip-"+string(rune('a'+i))); err != nil {
			t.Fatalf("第 %d 次: %v", i+1, err)
		}
		mr.FastForward(SMSCooldown)
	}
	err := codes.CheckRate(ctx, phone, "ip-z")
	var appErr *httpx.Error
	if !errors.As(err, &appErr) || appErr.Code != CodeSMSRateLimited {
		t.Fatalf("超过每日上限应返回 SMS_RATE_LIMITED, got %v", err)
	}
}

func TestSMSCodesRedisDown(t *testing.T) {
	rdb, mr := newRedis(t)
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), &MockSender{}, discard)
	mr.Close()
	ctx := context.Background()
	if err := codes.CheckRate(ctx, "+8613800000003", "ip"); err == nil {
		t.Error("CheckRate 应返回错误")
	}
	if err := codes.Send(ctx, PurposeLogin, "+8613800000003"); err == nil {
		t.Error("Send 应返回错误")
	}
	if err := codes.Verify(ctx, PurposeLogin, "+8613800000003", "123456"); err == nil || errors.Is(err, ErrSMSCodeInvalid) {
		t.Error("Redis 故障不应被当作验证码错误")
	}
}

func TestRevocations(t *testing.T) {
	rdb, mr := newRedis(t)
	r := NewRevocations(rdb, 15*time.Minute)
	ctx := context.Background()
	dev := uuid.New()
	at := time.Now()

	if err := r.MarkRevoked(ctx, nil, at); err != nil {
		t.Fatal(err)
	}
	if revoked, _ := r.IsRevoked(ctx, Principal{DeviceID: dev, IssuedAt: at}); revoked {
		t.Error("未标记的设备不应视为下线")
	}
	if err := r.MarkRevoked(ctx, []uuid.UUID{dev}, at); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		issued time.Time
		want   bool
	}{{at.Add(-time.Second), true}, {at, true}, {at.Add(time.Millisecond), false}} {
		if got, _ := r.IsRevoked(ctx, Principal{DeviceID: dev, IssuedAt: tc.issued}); got != tc.want {
			t.Errorf("签发于 %v 的令牌 revoked = %v, want %v", tc.issued.Sub(at), got, tc.want)
		}
	}
	if ttl := mr.TTL("jk:rev:" + dev.String()); ttl < 15*time.Minute {
		t.Errorf("下线标记 TTL = %v，应不短于 Access Token 有效期", ttl)
	}

	_ = mr.Set("jk:rev:"+dev.String(), "garbage")
	if got, _ := r.IsRevoked(ctx, Principal{DeviceID: dev, IssuedAt: at.Add(time.Hour)}); !got {
		t.Error("标记损坏时应按已下线处理")
	}
	mr.Close()
	if _, err := r.IsRevoked(ctx, Principal{DeviceID: dev}); err == nil {
		t.Error("Redis 故障应返回错误")
	}
	if err := r.MarkRevoked(ctx, []uuid.UUID{dev}, at); err == nil {
		t.Error("Redis 故障应返回错误")
	}
}

func TestRegistrationTickets(t *testing.T) {
	rdb, mr := newRedis(t)
	tk := NewRegistrationTickets(rdb)
	ctx := context.Background()
	ticket, err := tk.Issue(ctx, "+8613800000004")
	if err != nil {
		t.Fatal(err)
	}
	phone, ok, err := tk.Peek(ctx, ticket)
	if err != nil || !ok || phone != "+8613800000004" {
		t.Fatalf("Peek() = %q %v %v", phone, ok, err)
	}
	if err := tk.Consume(ctx, ticket); err != nil {
		t.Fatal(err)
	}
	if _, ok, _ := tk.Peek(ctx, ticket); ok {
		t.Error("消费后凭证应失效")
	}
	t2, _ := tk.Issue(ctx, "+8613800000004")
	mr.FastForward(RegistrationTicketTTL + time.Second)
	if _, ok, _ := tk.Peek(ctx, t2); ok {
		t.Error("过期凭证应失效")
	}
	mr.Close()
	if _, err := tk.Issue(ctx, "+86"); err == nil {
		t.Error("Redis 故障 Issue 应返回错误")
	}
	if _, _, err := tk.Peek(ctx, "x"); err == nil {
		t.Error("Redis 故障 Peek 应返回错误")
	}
	if err := tk.Consume(ctx, "x"); err == nil {
		t.Error("Redis 故障 Consume 应返回错误")
	}
}
