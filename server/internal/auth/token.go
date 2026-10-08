package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	tokenIssuer = "jikelog"
	// AudienceApp 为用户端令牌的受众；管理后台令牌使用不同受众，两者不能互用。
	AudienceApp = "app"
	clockLeeway = 5 * time.Second
	refreshLen  = 32
)

// ErrInvalidToken 表示令牌无效、过期或签名不符。
var ErrInvalidToken = errors.New("令牌无效")

// Principal 为通过认证的调用方。
type Principal struct {
	UserID   uuid.UUID
	DeviceID uuid.UUID
	// IssuedAt 为令牌签发时间（毫秒精度），用于判断令牌是否早于设备下线时间。
	IssuedAt time.Time
}

type accessClaims struct {
	jwt.RegisteredClaims
	SessionID string `json:"sid"`
	// IssuedAtMs 为毫秒精度的签发时间：标准 iat 只到秒，设备下线后同一秒内重新登录签发的令牌会被误判为已撤销
	IssuedAtMs int64 `json:"iat_ms"`
}

// TokenManager 签发与校验 Access Token（HS256 JWT）。支持一把旧密钥用于平滑轮换：
// 验签时依次尝试当前密钥与旧密钥，令牌头不携带任何密钥标识。
type TokenManager struct {
	active []byte
	keys   jwt.VerificationKeySet
	ttl    time.Duration
	now    func() time.Time
}

// NewTokenManager 创建 TokenManager；previous 为空表示没有旧密钥。now 为空时使用 time.Now。
func NewTokenManager(secret, previous string, ttl time.Duration, now func() time.Time) *TokenManager {
	if now == nil {
		now = time.Now
	}
	m := &TokenManager{active: []byte(secret), ttl: ttl, now: now}
	m.keys.Keys = []jwt.VerificationKey{m.active}
	if previous != "" {
		m.keys.Keys = append(m.keys.Keys, []byte(previous))
	}
	return m
}

// TTL 返回 Access Token 有效期。
func (m *TokenManager) TTL() time.Duration { return m.ttl }

// IssueAccess 以 issuedAt 为签发时间为设备会话签发 Access Token。签发时间由调用方给出，
// 以便与设备会话的 tokens_valid_after 使用同一时刻。
func (m *TokenManager) IssueAccess(userID, deviceID uuid.UUID, issuedAt time.Time) (string, time.Time, error) {
	exp := issuedAt.Add(m.ttl)
	claims := accessClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    tokenIssuer,
			Subject:   userID.String(),
			Audience:  jwt.ClaimStrings{AudienceApp},
			IssuedAt:  jwt.NewNumericDate(issuedAt),
			ExpiresAt: jwt.NewNumericDate(exp),
		},
		SessionID:  deviceID.String(),
		IssuedAtMs: issuedAt.UnixMilli(),
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.active)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("签发令牌失败: %w", err)
	}
	return signed, exp, nil
}

// ParseAccess 校验 Access Token 并返回调用方；任何问题都返回 ErrInvalidToken。
func (m *TokenManager) ParseAccess(raw string) (Principal, error) {
	var claims accessClaims
	_, err := jwt.ParseWithClaims(raw, &claims, func(*jwt.Token) (any, error) { return m.keys, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(tokenIssuer),
		jwt.WithAudience(AudienceApp),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
		jwt.WithLeeway(clockLeeway),
		jwt.WithTimeFunc(m.now),
	)
	if err != nil {
		return Principal{}, ErrInvalidToken
	}
	userID, err1 := uuid.Parse(claims.Subject)
	deviceID, err2 := uuid.Parse(claims.SessionID)
	if err1 != nil || err2 != nil || claims.IssuedAtMs <= 0 {
		return Principal{}, ErrInvalidToken
	}
	return Principal{UserID: userID, DeviceID: deviceID, IssuedAt: time.UnixMilli(claims.IssuedAtMs)}, nil
}

// NewRefreshToken 生成随机 Refresh Token，返回原文（交给客户端）与哈希（存库）。
func NewRefreshToken() (raw string, hash []byte, err error) {
	b := make([]byte, refreshLen)
	if _, err := rand.Read(b); err != nil {
		return "", nil, fmt.Errorf("生成令牌失败: %w", err)
	}
	raw = base64.RawURLEncoding.EncodeToString(b)
	return raw, HashToken(raw), nil
}

// HashToken 返回随机令牌的 SHA-256。令牌本身有 256 位熵，无需加盐或慢哈希。
func HashToken(raw string) []byte {
	sum := sha256.Sum256([]byte(raw))
	return sum[:]
}
