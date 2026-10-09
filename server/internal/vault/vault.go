// Package vault 管理每个账号的数据密钥（DEK），并提供落库字段的信封加密（ADR-006）。
package vault

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/crypto"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

const (
	// cacheTTL 为解开的数据密钥在进程内的缓存时长，避免每次请求都调用 KMS。
	cacheTTL = 10 * time.Minute
	// maxCached 为缓存条目上限，超过时清空重建（简单且足够：活跃账号会很快重新缓存）。
	maxCached = 10_000
	// sealedPrefix 标记落库密文的格式版本。
	sealedPrefix = "v1:"
)

// ErrNoKey 表示账号还没有数据密钥（从未写入过敏感字段）。
var ErrNoKey = errors.New("账号尚无数据密钥")

// KeyStore 为数据密钥的持久化（*dbgen.Queries 实现）。
type KeyStore interface {
	GetUserKey(ctx context.Context, userID uuid.UUID) (dbgen.UserKey, error)
	InsertUserKey(ctx context.Context, arg dbgen.InsertUserKeyParams) error
}

// Keyring 获取并缓存账号的数据密钥。
type Keyring struct {
	wrapper crypto.KeyWrapper
	now     func() time.Time

	mu    sync.Mutex
	cache map[uuid.UUID]cachedKey
}

type cachedKey struct {
	key     []byte
	expires time.Time
}

// NewKeyring 创建 Keyring；now 为空时使用 time.Now。
func NewKeyring(wrapper crypto.KeyWrapper, now func() time.Time) *Keyring {
	if now == nil {
		now = time.Now
	}
	return &Keyring{wrapper: wrapper, now: now, cache: map[uuid.UUID]cachedKey{}}
}

// DataKey 返回账号的数据密钥。create 为 true 时若不存在就生成并保存（需在事务内调用）。
func (k *Keyring) DataKey(ctx context.Context, store KeyStore, userID uuid.UUID, create bool) ([]byte, error) {
	if key, ok := k.cached(userID); ok {
		return key, nil
	}
	row, err := store.GetUserKey(ctx, userID)
	if db.IsNotFound(err) {
		if !create {
			return nil, ErrNoKey
		}
		if row, err = k.create(ctx, store, userID); err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, fmt.Errorf("查询数据密钥失败: %w", err)
	}
	key, err := k.wrapper.Unwrap(ctx, row.KmsKeyID, row.Wrapped)
	if err != nil {
		return nil, fmt.Errorf("解包数据密钥失败: %w", err)
	}
	k.store(userID, key)
	return key, nil
}

func (k *Keyring) create(ctx context.Context, store KeyStore, userID uuid.UUID) (dbgen.UserKey, error) {
	dek, err := crypto.NewDataKey()
	if err != nil {
		return dbgen.UserKey{}, err
	}
	keyID, wrapped, err := k.wrapper.Wrap(ctx, dek)
	if err != nil {
		return dbgen.UserKey{}, fmt.Errorf("包裹数据密钥失败: %w", err)
	}
	if err := store.InsertUserKey(ctx, dbgen.InsertUserKeyParams{UserID: userID, KmsKeyID: keyID, Wrapped: wrapped}); err != nil {
		return dbgen.UserKey{}, fmt.Errorf("保存数据密钥失败: %w", err)
	}
	// 并发创建时以先写入者为准
	row, err := store.GetUserKey(ctx, userID)
	if err != nil {
		return dbgen.UserKey{}, fmt.Errorf("查询数据密钥失败: %w", err)
	}
	return row, nil
}

func (k *Keyring) cached(userID uuid.UUID) ([]byte, bool) {
	k.mu.Lock()
	defer k.mu.Unlock()
	c, ok := k.cache[userID]
	if !ok || k.now().After(c.expires) {
		return nil, false
	}
	return c.key, true
}

func (k *Keyring) store(userID uuid.UUID, key []byte) {
	k.mu.Lock()
	defer k.mu.Unlock()
	if len(k.cache) >= maxCached {
		k.cache = map[uuid.UUID]cachedKey{}
	}
	k.cache[userID] = cachedKey{key: key, expires: k.now().Add(cacheTTL)}
}

// Forget 清除账号的缓存密钥（注销账号后调用）。
func (k *Keyring) Forget(userID uuid.UUID) {
	k.mu.Lock()
	defer k.mu.Unlock()
	delete(k.cache, userID)
}

// SealField 加密落库字段。AAD 绑定账号、记录与字段，防止密文被挪用到别处。
func SealField(key []byte, userID, recordID uuid.UUID, field, plain string) (string, error) {
	enc, err := crypto.SealString(key, plain, fieldAAD(userID, recordID, field))
	if err != nil {
		return "", err
	}
	return sealedPrefix + enc, nil
}

// OpenField 解密 SealField 的输出。
func OpenField(key []byte, userID, recordID uuid.UUID, field, sealed string) (string, error) {
	enc, ok := strings.CutPrefix(sealed, sealedPrefix)
	if !ok {
		return "", crypto.ErrDecrypt
	}
	return crypto.OpenString(key, enc, fieldAAD(userID, recordID, field))
}

func fieldAAD(userID, recordID uuid.UUID, field string) []byte {
	return []byte("jikelog-rest-v1|" + userID.String() + "|" + recordID.String() + "|" + field)
}
