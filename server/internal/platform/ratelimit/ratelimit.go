// Package ratelimit 基于 Redis 实现固定窗口计数限流，多个 API 实例共享计数。
package ratelimit

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/platform/cache"
)

// Result 为一次计数后的结果。
type Result struct {
	Allowed bool
	Count   int64
	// RetryAfter 为当前窗口剩余时间；未超限时也会返回，便于调用方展示。
	RetryAfter time.Duration
}

// Client 为 Limiter 需要的 Redis 能力，*redis.Client 满足该接口。
type Client interface {
	redis.Scripter
	Del(ctx context.Context, keys ...string) *redis.IntCmd
}

// Limiter 为固定窗口计数器。
type Limiter struct {
	rdb Client
}

// New 创建 Limiter。
func New(rdb Client) *Limiter { return &Limiter{rdb: rdb} }

// 计数 +1；窗口内第一次计数时设置过期时间。PTTL 缺失时补设，防止键永不过期。
var hitScript = redis.NewScript(`
local c = redis.call('INCR', KEYS[1])
if c == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
local ttl = redis.call('PTTL', KEYS[1])
if ttl < 0 then
  redis.call('PEXPIRE', KEYS[1], ARGV[1])
  ttl = tonumber(ARGV[1])
end
return {c, ttl}
`)

var peekScript = redis.NewScript(`
local c = redis.call('GET', KEYS[1])
if not c then return {0, 0} end
return {tonumber(c), redis.call('PTTL', KEYS[1])}
`)

func key(k string) string { return cache.KeyPrefix + "rl:" + k }

// Hit 计数一次，计数超过 limit 时 Allowed 为 false。
func (l *Limiter) Hit(ctx context.Context, k string, limit int64, window time.Duration) (Result, error) {
	vals, err := hitScript.Run(ctx, l.rdb, []string{key(k)}, window.Milliseconds()).Int64Slice()
	if err != nil {
		return Result{}, fmt.Errorf("限流计数失败: %w", err)
	}
	return Result{Allowed: vals[0] <= limit, Count: vals[0], RetryAfter: time.Duration(vals[1]) * time.Millisecond}, nil
}

// Peek 只读取当前计数，不计数；计数已达到 limit 时 Allowed 为 false。
func (l *Limiter) Peek(ctx context.Context, k string, limit int64) (Result, error) {
	vals, err := peekScript.Run(ctx, l.rdb, []string{key(k)}).Int64Slice()
	if err != nil {
		return Result{}, fmt.Errorf("读取限流计数失败: %w", err)
	}
	return Result{Allowed: vals[0] < limit, Count: vals[0], RetryAfter: time.Duration(max(vals[1], 0)) * time.Millisecond}, nil
}

// Reset 清零计数。
func (l *Limiter) Reset(ctx context.Context, k string) error {
	if err := l.rdb.Del(ctx, key(k)).Err(); err != nil {
		return fmt.Errorf("重置限流计数失败: %w", err)
	}
	return nil
}
