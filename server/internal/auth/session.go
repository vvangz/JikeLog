package auth

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/platform/cache"
)

// RefreshReplay 让宽限期内的重复刷新请求幂等：用某枚 Refresh Token 刷新成功后，
// 把换发结果缓存 refreshGrace 时长；同一枚令牌再次刷新时直接返回同一结果，而不是再换发一枚，
// 避免客户端持有的令牌因为并发或重试而失效。
//
// 缓存内容用由该 Refresh Token 原文派生的密钥加密（AES-256-GCM），键为其哈希：
// 只有持有原令牌的一方能解出结果，Redis 数据泄露也无法据此获得有效令牌。
type RefreshReplay struct {
	rdb redis.Cmdable
	ttl time.Duration
}

// NewRefreshReplay 创建 RefreshReplay。
func NewRefreshReplay(rdb redis.Cmdable) *RefreshReplay {
	return &RefreshReplay{rdb: rdb, ttl: refreshGrace}
}

func replayKey(presented string) string {
	return cache.KeyPrefix + "rr:" + base64.RawURLEncoding.EncodeToString(HashToken(presented))
}

func replayAEAD(presented string) (cipher.AEAD, error) {
	key, err := hkdf.Key(sha256.New, []byte(presented), nil, "jikelog-refresh-replay", 32)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// Save 缓存用 presented 换发得到的令牌。
func (r *RefreshReplay) Save(ctx context.Context, presented string, pair TokenPair) error {
	plain, err := json.Marshal(pair) //nolint:gosec // 序列化后立即加密，不落明文
	if err != nil {
		return fmt.Errorf("序列化令牌失败: %w", err)
	}
	aead, err := replayAEAD(presented)
	if err != nil {
		return fmt.Errorf("派生密钥失败: %w", err)
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return fmt.Errorf("生成随机数失败: %w", err)
	}
	sealed := aead.Seal(nonce, nonce, plain, nil)
	if err := r.rdb.Set(ctx, replayKey(presented), sealed, r.ttl).Err(); err != nil {
		return fmt.Errorf("缓存令牌失败: %w", err)
	}
	return nil
}

// Load 返回此前用 presented 换发的令牌；不存在或无法解密时 ok 为 false。
func (r *RefreshReplay) Load(ctx context.Context, presented string) (pair TokenPair, ok bool, err error) {
	sealed, err := r.rdb.Get(ctx, replayKey(presented)).Bytes()
	if errors.Is(err, redis.Nil) {
		return TokenPair{}, false, nil
	}
	if err != nil {
		return TokenPair{}, false, fmt.Errorf("读取令牌缓存失败: %w", err)
	}
	aead, err := replayAEAD(presented)
	if err != nil || len(sealed) < aead.NonceSize() {
		return TokenPair{}, false, nil
	}
	plain, err := aead.Open(nil, sealed[:aead.NonceSize()], sealed[aead.NonceSize():], nil)
	if err != nil || json.Unmarshal(plain, &pair) != nil {
		return TokenPair{}, false, nil
	}
	return pair, true, nil
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
