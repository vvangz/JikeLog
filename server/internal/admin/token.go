package admin

import (
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	tokenIssuer = "jikelog"
	// Audience 为管理员令牌的受众，用户端令牌为 auth.AudienceApp，两者不能互用。
	Audience = "admin"
	// AccessTTL 为管理员 Access Token 的有效期。
	AccessTTL   = 15 * time.Minute
	clockLeeway = 5 * time.Second
)

var errInvalidToken = errors.New("管理员令牌无效")

type claims struct {
	jwt.RegisteredClaims
	SessionID string `json:"sid"`
}

// Tokens 签发与校验管理员 Access Token（HS256）。签名密钥由服务端 JWT 密钥派生，与用户令牌的密钥不同。
type Tokens struct {
	key  []byte
	keys jwt.VerificationKeySet
	now  func() time.Time
}

// deriveKey 由服务端 JWT 密钥派生管理员令牌的签名密钥。
func deriveKey(secret string) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte("jikelog-admin-jwt"))
	return mac.Sum(nil)
}

// NewTokens 创建 Tokens；previous 为轮换期间的旧 JWT 密钥（可为空）。now 为空时使用 time.Now。
func NewTokens(secret, previous string, now func() time.Time) *Tokens {
	if now == nil {
		now = time.Now
	}
	t := &Tokens{key: deriveKey(secret), now: now}
	t.keys.Keys = []jwt.VerificationKey{t.key}
	if previous != "" {
		t.keys.Keys = append(t.keys.Keys, deriveKey(previous))
	}
	return t
}

// Issue 为管理员会话签发 Access Token。
func (t *Tokens) Issue(adminID, sessionID uuid.UUID) (string, time.Time, error) {
	now := t.now()
	exp := now.Add(AccessTTL)
	c := claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer: tokenIssuer, Subject: adminID.String(), Audience: jwt.ClaimStrings{Audience},
			IssuedAt: jwt.NewNumericDate(now), ExpiresAt: jwt.NewNumericDate(exp),
		},
		SessionID: sessionID.String(),
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(t.key)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("签发令牌失败: %w", err)
	}
	return signed, exp, nil
}

// Parse 校验 Access Token，返回管理员 ID 与会话 ID。
func (t *Tokens) Parse(raw string) (adminID, sessionID uuid.UUID, err error) {
	var c claims
	_, err = jwt.ParseWithClaims(raw, &c, func(*jwt.Token) (any, error) { return t.keys, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(tokenIssuer),
		jwt.WithAudience(Audience),
		jwt.WithExpirationRequired(),
		jwt.WithLeeway(clockLeeway),
		jwt.WithTimeFunc(t.now),
	)
	if err != nil {
		return uuid.Nil, uuid.Nil, errInvalidToken
	}
	adminID, err1 := uuid.Parse(c.Subject)
	sessionID, err2 := uuid.Parse(c.SessionID)
	if err1 != nil || err2 != nil {
		return uuid.Nil, uuid.Nil, errInvalidToken
	}
	return adminID, sessionID, nil
}

// bearer 取出 Authorization 头中的 Bearer 令牌。
func bearer(header string) (string, bool) {
	const prefix = "Bearer "
	if len(header) <= len(prefix) || !strings.EqualFold(header[:len(prefix)], prefix) {
		return "", false
	}
	return strings.TrimSpace(header[len(prefix):]), true
}

// IsAdminToken 报告 Authorization 头是否携带有效的管理员令牌（不查数据库）。
// 用户接口据此对管理员令牌返回 403，而不是笼统的 401。
func (t *Tokens) IsAdminToken(header string) bool {
	raw, ok := bearer(header)
	if !ok {
		return false
	}
	_, _, err := t.Parse(raw)
	return err == nil
}
