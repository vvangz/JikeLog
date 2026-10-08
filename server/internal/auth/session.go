package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/platform/cache"
)

// Revocations 记录设备会话的下线时间。Access Token 是无状态的，设备下线后，
// 在其剩余有效期内仍需逐个请求检查：签发时间不晚于下线时间的令牌一律拒绝。
type Revocations struct {
	rdb redis.Cmdable
	// ttl 至少为 Access Token 有效期：之后旧令牌已自然过期，标记可以删除
	ttl time.Duration
}

// NewRevocations 创建 Revocations。
func NewRevocations(rdb redis.Cmdable, accessTTL time.Duration) *Revocations {
	return &Revocations{rdb: rdb, ttl: accessTTL + time.Minute}
}

func revokedKey(deviceID uuid.UUID) string { return cache.KeyPrefix + "rev:" + deviceID.String() }

// MarkRevoked 记录这些设备在 at 时刻下线。
func (r *Revocations) MarkRevoked(ctx context.Context, deviceIDs []uuid.UUID, at time.Time) error {
	if len(deviceIDs) == 0 {
		return nil
	}
	pipe := r.rdb.Pipeline()
	for _, id := range deviceIDs {
		pipe.Set(ctx, revokedKey(id), at.UnixMilli(), r.ttl)
	}
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("记录设备下线失败: %w", err)
	}
	return nil
}

// IsRevoked 报告该令牌是否签发于设备下线之前。
func (r *Revocations) IsRevoked(ctx context.Context, p Principal) (bool, error) {
	v, err := r.rdb.Get(ctx, revokedKey(p.DeviceID)).Result()
	if errors.Is(err, redis.Nil) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("读取设备下线状态失败: %w", err)
	}
	revokedAt, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return true, nil // 标记损坏时按已下线处理
	}
	return p.IssuedAt.UnixMilli() <= revokedAt, nil
}

// RegistrationTickets 保存短信登录时为新手机号签发的一次性注册凭证。
type RegistrationTickets struct {
	rdb redis.Cmdable
}

// RegistrationTicketTTL 为注册凭证有效期。
const RegistrationTicketTTL = 10 * time.Minute

// NewRegistrationTickets 创建 RegistrationTickets。
func NewRegistrationTickets(rdb redis.Cmdable) *RegistrationTickets {
	return &RegistrationTickets{rdb: rdb}
}

func ticketKey(ticket string) string {
	return cache.KeyPrefix + "regt:" + base64.RawURLEncoding.EncodeToString(HashToken(ticket))
}

// Issue 为已验证的手机号签发注册凭证。
func (t *RegistrationTickets) Issue(ctx context.Context, phone string) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("生成注册凭证失败: %w", err)
	}
	ticket := base64.RawURLEncoding.EncodeToString(b)
	if err := t.rdb.Set(ctx, ticketKey(ticket), phone, RegistrationTicketTTL).Err(); err != nil {
		return "", fmt.Errorf("保存注册凭证失败: %w", err)
	}
	return ticket, nil
}

// Peek 返回凭证对应的手机号但不消费；凭证无效时 ok 为 false。
func (t *RegistrationTickets) Peek(ctx context.Context, ticket string) (phone string, ok bool, err error) {
	phone, err = t.rdb.Get(ctx, ticketKey(ticket)).Result()
	if errors.Is(err, redis.Nil) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("读取注册凭证失败: %w", err)
	}
	return phone, true, nil
}

// Consume 删除凭证。
func (t *RegistrationTickets) Consume(ctx context.Context, ticket string) error {
	if err := t.rdb.Del(ctx, ticketKey(ticket)).Err(); err != nil {
		return fmt.Errorf("作废注册凭证失败: %w", err)
	}
	return nil
}
