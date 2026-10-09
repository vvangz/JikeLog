package e2e

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

type vector struct {
	ServerPrivateKey string `json:"serverPrivateKey"`
	ServerKeyID      string `json:"serverKeyId"`
	ClientPublicKey  string `json:"clientPublicKey"`
	AAD              string `json:"aad"`
	Plaintext        string `json:"plaintext"`
	Sealed           string `json:"sealed"`
}

func loadVector(t *testing.T) vector {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "testdata", "crypto", "e2e.json"))
	if err != nil {
		t.Fatal(err)
	}
	var v vector
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func newManager(t *testing.T, current, previous string) (*Manager, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	m, err := NewManager(rdb, ratelimit.New(rdb), current, previous, nil)
	if err != nil {
		t.Fatal(err)
	}
	return m, mr
}

func principal() auth.Principal { return auth.Principal{UserID: uuid.New(), DeviceID: uuid.New()} }

func TestSessionRoundTripWithSharedVector(t *testing.T) {
	v := loadVector(t)
	m, _ := newManager(t, v.ServerPrivateKey, "")
	if m.CurrentKeyID() != v.ServerKeyID {
		t.Fatalf("keyId=%s", m.CurrentKeyID())
	}
	ctx := context.Background()
	p := principal()
	sid, expires, err := m.Create(ctx, p, v.ClientPublicKey, v.ServerKeyID)
	if err != nil || sid == "" || expires.IsZero() {
		t.Fatalf("sid=%q err=%v", sid, err)
	}
	s, err := m.Session(ctx, p, sid)
	if err != nil {
		t.Fatal(err)
	}
	plain, err := s.Open(v.AAD, v.Sealed)
	if err != nil || plain != v.Plaintext {
		t.Fatalf("应能解开客户端用同一会话密钥加密的数据：plain=%q err=%v", plain, err)
	}
	sealed, err := s.Seal(v.AAD, "回程")
	if err != nil {
		t.Fatal(err)
	}
	if back, err := s.Open(v.AAD, sealed); err != nil || back != "回程" {
		t.Fatalf("back=%q err=%v", back, err)
	}
	if _, err := s.Open(AAD("worklog", uuid.New(), "content", KindValue), v.Sealed); !errors.Is(err, ErrDecrypt) {
		t.Fatal("AAD 不符应当解密失败")
	}
}

func TestSessionBoundToDevice(t *testing.T) {
	v := loadVector(t)
	m, mr := newManager(t, v.ServerPrivateKey, "")
	ctx := context.Background()
	p := principal()
	sid, _, err := m.Create(ctx, p, v.ClientPublicKey, v.ServerKeyID)
	if err != nil {
		t.Fatal(err)
	}
	other := auth.Principal{UserID: p.UserID, DeviceID: uuid.New()}
	for name, fn := range map[string]func() error{
		"其他设备":  func() error { _, err := m.Session(ctx, other, sid); return err },
		"不存在":   func() error { _, err := m.Session(ctx, p, "nope"); return err },
		"空 ID":  func() error { _, err := m.Session(ctx, p, ""); return err },
		"ID 过长": func() error { _, err := m.Session(ctx, p, string(make([]byte, 65))); return err },
	} {
		if err := fn(); !errors.Is(err, ErrSessionInvalid) {
			t.Errorf("%s：err=%v", name, err)
		}
	}
	mr.FastForward(sessionTTL + 1)
	if _, err := m.Session(ctx, p, sid); !errors.Is(err, ErrSessionInvalid) {
		t.Fatal("过期后应失效")
	}
}

func TestCreateValidation(t *testing.T) {
	v := loadVector(t)
	m, _ := newManager(t, v.ServerPrivateKey, "")
	ctx := context.Background()
	if _, _, err := m.Create(ctx, principal(), v.ClientPublicKey, "unknown"); !errors.Is(err, errKeyUnknown) {
		t.Fatalf("未知公钥标识：err=%v", err)
	}
	var verr *httpx.Error
	if _, _, err := m.Create(ctx, principal(), "short", v.ServerKeyID); !errors.As(err, &verr) || verr.Code != httpx.CodeValidationFailed {
		t.Fatalf("公钥格式错误：err=%v", err)
	}
}

func TestCreateRateLimited(t *testing.T) {
	v := loadVector(t)
	m, _ := newManager(t, v.ServerPrivateKey, "")
	ctx := context.Background()
	p := principal()
	for range handshakePerHour {
		if _, _, err := m.Create(ctx, p, v.ClientPublicKey, v.ServerKeyID); err != nil {
			t.Fatal(err)
		}
	}
	var herr *httpx.Error
	if _, _, err := m.Create(ctx, p, v.ClientPublicKey, v.ServerKeyID); !errors.As(err, &herr) || herr.Code != httpx.CodeRateLimited {
		t.Fatalf("超过握手频率应限流：err=%v", err)
	}
}

func TestPreviousKeyStillAccepted(t *testing.T) {
	v := loadVector(t)
	next, _ := ecdh.X25519().GenerateKey(rand.Reader)
	m, _ := newManager(t, base64.StdEncoding.EncodeToString(next.Bytes()), v.ServerPrivateKey)
	if m.CurrentKeyID() == v.ServerKeyID {
		t.Fatal("当前公钥应为新密钥")
	}
	ctx := context.Background()
	p := principal()
	sid, _, err := m.Create(ctx, p, v.ClientPublicKey, v.ServerKeyID)
	if err != nil {
		t.Fatalf("旧版本 App 仍应可用：%v", err)
	}
	s, err := m.Session(ctx, p, sid)
	if err != nil {
		t.Fatal(err)
	}
	if plain, err := s.Open(v.AAD, v.Sealed); err != nil || plain != v.Plaintext {
		t.Fatalf("plain=%q err=%v", plain, err)
	}
}

func TestNewManagerErrors(t *testing.T) {
	rdb := redis.NewClient(&redis.Options{Addr: "127.0.0.1:0"})
	if _, err := NewManager(rdb, nil, "", "", nil); err == nil {
		t.Error("缺少私钥应报错")
	}
	if _, err := NewManager(rdb, nil, "bad", "", nil); err == nil {
		t.Error("私钥格式错误应报错")
	}
	key, _ := ecdh.X25519().GenerateKey(rand.Reader)
	if _, err := NewManager(rdb, nil, "", base64.StdEncoding.EncodeToString(key.Bytes()), nil); err == nil {
		t.Error("只有旧私钥应报错")
	}
}

func TestSessionErrorsWhenRedisDown(t *testing.T) {
	v := loadVector(t)
	m, mr := newManager(t, v.ServerPrivateKey, "")
	mr.Close()
	if _, err := m.Session(context.Background(), principal(), "abc"); err == nil || errors.Is(err, ErrSessionInvalid) {
		t.Fatalf("Redis 故障应返回内部错误：%v", err)
	}
}
