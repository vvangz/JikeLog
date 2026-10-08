package auth

import (
	"bytes"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	secretA = strings.Repeat("a", 32)
	secretB = strings.Repeat("b", 32)
)

func fixedClock(t time.Time) func() time.Time { return func() time.Time { return t } }

func TestTokenRoundTrip(t *testing.T) {
	now := time.Date(2026, 10, 9, 8, 0, 0, 123_000_000, time.UTC)
	m := NewTokenManager(secretA, "", 15*time.Minute, fixedClock(now))
	uid, did := uuid.Must(uuid.NewV7()), uuid.Must(uuid.NewV7())

	tok, exp, err := m.IssueAccess(uid, did, now)
	if err != nil {
		t.Fatal(err)
	}
	if !exp.Equal(now.Add(15 * time.Minute)) {
		t.Errorf("exp = %v", exp)
	}
	p, err := m.ParseAccess(tok)
	if err != nil {
		t.Fatalf("ParseAccess() error = %v", err)
	}
	if p.UserID != uid || p.DeviceID != did || !p.IssuedAt.Equal(now.Truncate(time.Millisecond)) {
		t.Errorf("Principal = %+v", p)
	}
	if m.TTL() != 15*time.Minute {
		t.Errorf("TTL() = %v", m.TTL())
	}
}

func TestTokenExpires(t *testing.T) {
	now := time.Now()
	issuer := NewTokenManager(secretA, "", time.Minute, fixedClock(now))
	tok, _, _ := issuer.IssueAccess(uuid.New(), uuid.New(), now)
	later := NewTokenManager(secretA, "", time.Minute, fixedClock(now.Add(time.Minute+clockLeeway+time.Second)))
	if _, err := later.ParseAccess(tok); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("过期令牌 err = %v", err)
	}
}

func TestTokenKeyRotation(t *testing.T) {
	old := NewTokenManager(secretA, "", time.Minute, nil)
	tok, _, _ := old.IssueAccess(uuid.New(), uuid.New(), time.Now())

	rotated := NewTokenManager(secretB, secretA, time.Minute, nil)
	if _, err := rotated.ParseAccess(tok); err != nil {
		t.Errorf("轮换期内旧密钥签发的令牌应有效: %v", err)
	}
	dropped := NewTokenManager(secretB, "", time.Minute, nil)
	if _, err := dropped.ParseAccess(tok); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("移除旧密钥后应失效, err = %v", err)
	}
}

func TestTokenRejectsTampering(t *testing.T) {
	m := NewTokenManager(secretA, "", time.Minute, nil)
	sign := func(claims jwt.Claims, method jwt.SigningMethod, key any) string {
		s, err := jwt.NewWithClaims(method, claims).SignedString(key)
		if err != nil {
			t.Fatal(err)
		}
		return s
	}
	now := time.Now()
	valid := func() accessClaims {
		return accessClaims{
			RegisteredClaims: jwt.RegisteredClaims{
				Issuer: tokenIssuer, Subject: uuid.NewString(), Audience: jwt.ClaimStrings{AudienceApp},
				IssuedAt: jwt.NewNumericDate(now), ExpiresAt: jwt.NewNumericDate(now.Add(time.Minute)),
			},
			SessionID: uuid.NewString(), IssuedAtMs: now.UnixMilli(),
		}
	}
	adminAud := valid()
	adminAud.Audience = jwt.ClaimStrings{"admin"}
	wrongIss := valid()
	wrongIss.Issuer = "other"
	noExp := valid()
	noExp.ExpiresAt = nil
	badSub := valid()
	badSub.Subject = "not-a-uuid"
	badSid := valid()
	badSid.SessionID = "x"
	noMs := valid()
	noMs.IssuedAtMs = 0

	good := sign(valid(), jwt.SigningMethodHS256, []byte(secretA))
	cases := map[string]string{
		"管理后台受众":   sign(adminAud, jwt.SigningMethodHS256, []byte(secretA)),
		"签发者不符":    sign(wrongIss, jwt.SigningMethodHS256, []byte(secretA)),
		"缺少过期时间":   sign(noExp, jwt.SigningMethodHS256, []byte(secretA)),
		"sub 非法":   sign(badSub, jwt.SigningMethodHS256, []byte(secretA)),
		"sid 非法":   sign(badSid, jwt.SigningMethodHS256, []byte(secretA)),
		"缺少毫秒签发时间": sign(noMs, jwt.SigningMethodHS256, []byte(secretA)),
		"错误密钥":     sign(valid(), jwt.SigningMethodHS256, []byte(secretB)),
		"算法降级":     sign(valid(), jwt.SigningMethodHS512, []byte(secretA)),
		"none 算法":  sign(valid(), jwt.SigningMethodNone, jwt.UnsafeAllowNoneSignatureType),
		"篡改载荷":     good[:len(good)-2] + "xx",
		"不是 JWT":   "garbage",
	}
	if _, err := m.ParseAccess(good); err != nil {
		t.Fatalf("基准令牌应有效: %v", err)
	}
	for name, tok := range cases {
		if _, err := m.ParseAccess(tok); !errors.Is(err, ErrInvalidToken) {
			t.Errorf("%s: err = %v, want ErrInvalidToken", name, err)
		}
	}
	tok, _, _ := m.IssueAccess(uuid.New(), uuid.New(), now)
	header, _ := base64.RawURLEncoding.DecodeString(strings.Split(tok, ".")[0])
	if strings.Contains(string(header), "kid") {
		t.Errorf("令牌头不应携带密钥标识: %s", header)
	}
}

func TestRefreshToken(t *testing.T) {
	raw, hash, err := NewRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	if len(raw) < 40 || strings.ContainsAny(raw, "+/=") {
		t.Errorf("令牌应为无填充的 URL 安全 base64: %q", raw)
	}
	if !bytes.Equal(hash, HashToken(raw)) || len(hash) != 32 {
		t.Error("哈希不一致")
	}
	raw2, _, _ := NewRefreshToken()
	if raw2 == raw {
		t.Error("两次生成的令牌相同")
	}
}
