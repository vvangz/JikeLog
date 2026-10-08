package auth

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
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

var (
	discard     = slog.New(slog.NewTextHandler(io.Discard, nil))
	testHashKey = []byte("test-sms-hash-key-test-sms-hash-key")
)

func TestSMSCodesSendAndVerify(t *testing.T) {
	rdb, mr := newRedis(t)
	sender := &MockSender{Logger: discard}
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), sender, discard, testHashKey)
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
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), failingSender{}, discard, testHashKey)
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
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), &MockSender{}, discard, testHashKey)
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
	codes := NewSMSCodes(rdb, ratelimit.New(rdb), &MockSender{}, discard, testHashKey)
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

func TestRefreshReplay(t *testing.T) {
	rdb, mr := newRedis(t)
	r := NewRefreshReplay(rdb)
	ctx := context.Background()
	pair := TokenPair{AccessToken: "a", RefreshToken: "r", AccessExpiresAt: time.Now().UTC().Truncate(time.Second)}

	if _, ok, err := r.Load(ctx, "presented"); ok || err != nil {
		t.Fatalf("未缓存时 Load = %v, %v", ok, err)
	}
	if err := r.Save(ctx, "presented", pair); err != nil {
		t.Fatal(err)
	}
	got, ok, err := r.Load(ctx, "presented")
	if err != nil || !ok || got.RefreshToken != "r" || !got.AccessExpiresAt.Equal(pair.AccessExpiresAt) {
		t.Fatalf("Load = %+v %v %v", got, ok, err)
	}
	for _, k := range mr.Keys() {
		if v, _ := mr.Get(k); strings.Contains(v, `"r"`) || strings.Contains(v, "RefreshToken") {
			t.Error("缓存内容应加密")
		}
	}
	if _, ok, _ := r.Load(ctx, "other"); ok {
		t.Error("其他令牌不应读到缓存")
	}
	// 篡改密文或用错误的令牌解密都视为不存在
	key := mr.Keys()[0]
	_ = mr.Set(key, "short")
	if _, ok, err := r.Load(ctx, "presented"); ok || err != nil {
		t.Errorf("损坏的缓存应视为不存在: %v %v", ok, err)
	}
	_ = r.Save(ctx, "presented", pair)
	mr.FastForward(refreshGrace + time.Second)
	if _, ok, _ := r.Load(ctx, "presented"); ok {
		t.Error("超过宽限期后缓存应过期")
	}
	mr.Close()
	if err := r.Save(ctx, "p", pair); err == nil {
		t.Error("Redis 故障 Save 应返回错误")
	}
	if _, _, err := r.Load(ctx, "p"); err == nil {
		t.Error("Redis 故障 Load 应返回错误")
	}
}

func TestIPKey(t *testing.T) {
	cases := map[string]string{
		"203.0.113.9":          "203.0.113.9",
		"::ffff:203.0.113.9":   "203.0.113.9",
		"2001:db8:1:2:3:4:5:6": "2001:db8:1:2::/64",
		"2001:db8:1:2:ffff::1": "2001:db8:1:2::/64",
		"unknown":              "unknown",
	}
	for in, want := range cases {
		if got := ipKey(in); got != want {
			t.Errorf("ipKey(%q) = %q, want %q", in, got, want)
		}
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
