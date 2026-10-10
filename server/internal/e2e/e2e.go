// Package e2e 管理工作日志的应用层传输加密会话（ADR-006）：
// 客户端上传临时 X25519 公钥，双方各自派生会话密钥；敏感字段以 AES-256-GCM 加密传输。
package e2e

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/cache"
	"github.com/vvangz/JikeLog/server/internal/platform/crypto"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

// HeaderName 为携带会话 ID 的请求头。
const HeaderName = "X-JikeLog-E2E"

// 错误码。
const (
	// CodeSessionInvalid 表示会话不存在、已过期或不属于当前设备，客户端应重新握手后重试。
	CodeSessionInvalid = "E2E_SESSION_INVALID"
	// CodeKeyUnknown 表示客户端内置的服务端公钥已不再受支持，需要升级 App。
	CodeKeyUnknown = "E2E_KEY_UNKNOWN"
	// CodeDecryptFailed 表示密文无法解开（被篡改或会话不符）。
	CodeDecryptFailed = "E2E_DECRYPT_FAILED"
)

const (
	sessionTTL = 24 * time.Hour
	// 每台设备每小时最多握手次数：正常只在启动和会话过期时握手。
	handshakePerHour = 60
	aadPrefix        = "jikelog-e2e-v1|"
)

var (
	// ErrSessionInvalid 见 CodeSessionInvalid。
	ErrSessionInvalid = httpx.NewError(http.StatusConflict, CodeSessionInvalid, "加密会话已失效，请重试")
	errKeyUnknown     = httpx.NewError(http.StatusConflict, CodeKeyUnknown, "当前版本的加密密钥已停用，请升级 App")
	errBadPublicKey   = httpx.Validation(map[string]string{"clientPublicKey": "必须是 base64 编码的 32 字节 X25519 公钥"})
	// ErrDecrypt 见 CodeDecryptFailed。
	ErrDecrypt = httpx.NewError(http.StatusBadRequest, CodeDecryptFailed, "加密数据校验失败")
)

// Manager 创建与查找加密会话。
type Manager struct {
	rdb     *redis.Client
	limiter *ratelimit.Limiter
	// keys 为当前与上一把服务端私钥，按公钥标识索引。
	keys      map[string]*ecdh.PrivateKey
	currentID string
	now       func() time.Time
}

// NewManager 由 base64 编码的当前私钥与（可选的）上一把私钥创建 Manager。
func NewManager(rdb *redis.Client, limiter *ratelimit.Limiter, current, previous string, now func() time.Time) (*Manager, error) {
	if now == nil {
		now = time.Now
	}
	m := &Manager{rdb: rdb, limiter: limiter, keys: map[string]*ecdh.PrivateKey{}, now: now}
	for i, b64 := range []string{current, previous} {
		if b64 == "" {
			continue
		}
		priv, err := crypto.ParseX25519PrivateKey(b64)
		if err != nil {
			return nil, fmt.Errorf("加载传输加密私钥失败: %w", err)
		}
		id := crypto.KeyID(priv.PublicKey())
		m.keys[id] = priv
		if i == 0 {
			m.currentID = id
		}
	}
	if m.currentID == "" {
		return nil, errors.New("缺少传输加密私钥")
	}
	return m, nil
}

// CurrentKeyID 返回当前服务端公钥标识。
func (m *Manager) CurrentKeyID() string { return m.currentID }

type stored struct {
	UserID    uuid.UUID `json:"u"`
	DeviceID  uuid.UUID `json:"d"`
	ClientPub string    `json:"c"`
	KeyID     string    `json:"k"`
}

// Create 为当前设备创建会话，返回会话 ID 与过期时间。
func (m *Manager) Create(ctx context.Context, p auth.Principal, clientPub, serverKeyID string) (string, time.Time, error) {
	priv, ok := m.keys[serverKeyID]
	if !ok {
		return "", time.Time{}, errKeyUnknown
	}
	if _, err := crypto.ParseX25519PublicKey(clientPub); err != nil {
		return "", time.Time{}, errBadPublicKey
	}
	r, err := m.limiter.Hit(ctx, "e2e:dev:"+p.DeviceID.String(), handshakePerHour, time.Hour)
	if err != nil {
		return "", time.Time{}, err
	}
	if !r.Allowed {
		return "", time.Time{}, httpx.TooManyRequests(httpx.CodeRateLimited, "操作过于频繁，请稍后再试", r.RetryAfter)
	}
	sid, err := newSessionID()
	if err != nil {
		return "", time.Time{}, err
	}
	raw, err := json.Marshal(stored{UserID: p.UserID, DeviceID: p.DeviceID, ClientPub: clientPub, KeyID: crypto.KeyID(priv.PublicKey())})
	if err != nil {
		return "", time.Time{}, fmt.Errorf("编码加密会话失败: %w", err)
	}
	if err := m.rdb.Set(ctx, redisKey(sid), raw, sessionTTL).Err(); err != nil {
		return "", time.Time{}, fmt.Errorf("保存加密会话失败: %w", err)
	}
	return sid, m.now().Add(sessionTTL), nil
}

// Session 查找属于当前设备的会话并派生会话密钥。
func (m *Manager) Session(ctx context.Context, p auth.Principal, sid string) (*Session, error) {
	if sid == "" || len(sid) > 64 {
		return nil, ErrSessionInvalid
	}
	raw, err := m.rdb.Get(ctx, redisKey(sid)).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, ErrSessionInvalid
	}
	if err != nil {
		return nil, fmt.Errorf("读取加密会话失败: %w", err)
	}
	var s stored
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, ErrSessionInvalid
	}
	// 会话绑定到创建它的账号和设备，被其他设备拿去也无法使用
	if s.UserID != p.UserID || s.DeviceID != p.DeviceID {
		return nil, ErrSessionInvalid
	}
	priv, ok := m.keys[s.KeyID]
	if !ok {
		return nil, ErrSessionInvalid // 旧私钥已移除
	}
	clientPub, err := crypto.ParseX25519PublicKey(s.ClientPub)
	if err != nil {
		return nil, ErrSessionInvalid
	}
	key, err := crypto.DeriveSessionKey(priv, clientPub, clientPub.Bytes(), priv.PublicKey().Bytes())
	if err != nil {
		return nil, ErrSessionInvalid
	}
	return &Session{key: key}, nil
}

func redisKey(sid string) string { return cache.KeyPrefix + "e2e:" + sid }

func newSessionID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("生成会话 ID 失败: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// Session 为已建立的加密会话。
type Session struct {
	key []byte
}

// 密文用途：字段值或补丁。
const (
	KindValue = "v"
	KindPatch = "p"
)

// AAD 返回字段密文的附加数据，把密文绑定到具体的记录、字段和用途。
func AAD(entity string, id uuid.UUID, field, kind string) string {
	return aadPrefix + entity + "|" + id.String() + "|" + field + "|" + kind
}

// Open 解密客户端发来的字段。
func (s *Session) Open(aad, enc string) (string, error) {
	plain, err := crypto.OpenString(s.key, enc, []byte(aad))
	if err != nil {
		return "", ErrDecrypt
	}
	return plain, nil
}

// Seal 加密下发给客户端的字段。
func (s *Session) Seal(aad, plain string) (string, error) {
	return crypto.SealString(s.key, plain, []byte(aad))
}
