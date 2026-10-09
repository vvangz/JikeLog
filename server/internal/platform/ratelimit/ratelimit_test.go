package ratelimit

import (
	"context"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func newLimiter(t *testing.T) (*Limiter, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	return New(rdb), mr
}

func TestHitWithinAndOverLimit(t *testing.T) {
	l, mr := newLimiter(t)
	ctx := context.Background()
	for i := 1; i <= 3; i++ {
		r, err := l.Hit(ctx, "k", 3, time.Minute)
		if err != nil || !r.Allowed || r.Count != int64(i) {
			t.Fatalf("第 %d 次 = %+v, %v", i, r, err)
		}
		if r.RetryAfter <= 0 || r.RetryAfter > time.Minute {
			t.Errorf("RetryAfter = %v", r.RetryAfter)
		}
	}
	r, _ := l.Hit(ctx, "k", 3, time.Minute)
	if r.Allowed {
		t.Error("第 4 次应超限")
	}
	if !mr.Exists("jk:rl:k") {
		t.Error("键应带 jk:rl: 前缀")
	}

	mr.FastForward(time.Minute + time.Second)
	if r, _ := l.Hit(ctx, "k", 3, time.Minute); !r.Allowed || r.Count != 1 {
		t.Errorf("窗口过期后应重新计数: %+v", r)
	}
}

func TestHitRepairsMissingTTL(t *testing.T) {
	l, mr := newLimiter(t)
	_ = mr.Set("jk:rl:k", "5") // 无过期时间的残留键
	r, err := l.Hit(context.Background(), "k", 10, time.Minute)
	if err != nil || r.Count != 6 {
		t.Fatalf("Hit() = %+v, %v", r, err)
	}
	if ttl := mr.TTL("jk:rl:k"); ttl <= 0 {
		t.Errorf("应补设过期时间, TTL = %v", ttl)
	}
}

func TestPeekAndReset(t *testing.T) {
	l, _ := newLimiter(t)
	ctx := context.Background()
	if r, err := l.Peek(ctx, "k", 2); err != nil || !r.Allowed || r.Count != 0 {
		t.Fatalf("空计数 Peek = %+v, %v", r, err)
	}
	_, _ = l.Hit(ctx, "k", 2, time.Minute)
	_, _ = l.Hit(ctx, "k", 2, time.Minute)
	r, _ := l.Peek(ctx, "k", 2)
	if r.Allowed || r.Count != 2 || r.RetryAfter <= 0 {
		t.Errorf("达到上限 Peek = %+v", r)
	}
	if err := l.Reset(ctx, "k"); err != nil {
		t.Fatal(err)
	}
	if r, _ := l.Peek(ctx, "k", 2); !r.Allowed {
		t.Error("Reset 后应允许")
	}
}

func TestErrorsWhenRedisDown(t *testing.T) {
	l, mr := newLimiter(t)
	mr.Close()
	ctx := context.Background()
	if _, err := l.Hit(ctx, "k", 1, time.Second); err == nil {
		t.Error("Hit 应返回错误")
	}
	if _, err := l.Peek(ctx, "k", 1); err == nil {
		t.Error("Peek 应返回错误")
	}
	if err := l.Reset(ctx, "k"); err == nil {
		t.Error("Reset 应返回错误")
	}
}
