package auth

import (
	"context"
	"errors"
	"strings"
	"testing"
)

// 测试使用低成本参数，避免拖慢测试。
var testArgon = Argon2Params{MemoryKiB: 64, Time: 1, Threads: 1}

func TestHasherRoundTrip(t *testing.T) {
	ctx := context.Background()
	h := NewHasher(testArgon)
	enc, err := h.Hash(ctx, "secret123")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(enc, "$argon2id$v=19$m=64,t=1,p=1$") {
		t.Errorf("哈希格式 = %q", enc)
	}
	other, _ := h.Hash(ctx, "secret123")
	if other == enc {
		t.Error("相同密码两次哈希应使用不同的盐")
	}

	ok, rehash, err := h.Verify(ctx, "secret123", enc)
	if err != nil || !ok || rehash {
		t.Errorf("Verify(正确密码) = %v, %v, %v", ok, rehash, err)
	}
	ok, _, err = h.Verify(ctx, "secret124", enc)
	if err != nil || ok {
		t.Errorf("Verify(错误密码) = %v, %v", ok, err)
	}
}

func TestHasherDetectsOutdatedParams(t *testing.T) {
	ctx := context.Background()
	old := NewHasher(testArgon)
	enc, _ := old.Hash(ctx, "secret123")
	upgraded := NewHasher(Argon2Params{MemoryKiB: 128, Time: 1, Threads: 1})
	ok, rehash, err := upgraded.Verify(ctx, "secret123", enc)
	if err != nil || !ok || !rehash {
		t.Errorf("旧参数哈希应校验通过且提示需要重新哈希: %v %v %v", ok, rehash, err)
	}
}

func TestHasherRejectsMalformedHash(t *testing.T) {
	h := NewHasher(testArgon)
	bad := []string{
		"",
		"plain",
		"$bcrypt$v=19$m=64,t=1,p=1$c2FsdA$aGFzaA",
		"$argon2id$v=18$m=64,t=1,p=1$c2FsdA$aGFzaA",
		"$argon2id$v=19$m=x,t=1,p=1$c2FsdA$aGFzaA",
		"$argon2id$v=19$m=64,t=1,p=1$!!!$aGFzaA",
		"$argon2id$v=19$m=64,t=1,p=1$c2FsdA$!!!",
		"$argon2id$v=19$m=64,t=1,p=1$c2FsdA$",
	}
	for _, enc := range bad {
		if _, _, err := h.Verify(context.Background(), "x", enc); !errors.Is(err, errMalformedHash) {
			t.Errorf("Verify(%q) err = %v, want errMalformedHash", enc, err)
		}
	}
}

func TestHasherRespectsContextWhenSaturated(t *testing.T) {
	h := &Hasher{params: testArgon, sem: make(chan struct{}, 1)}
	h.sem <- struct{}{} // 占满并发额度
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := h.Hash(ctx, "x"); !errors.Is(err, context.Canceled) {
		t.Errorf("Hash() err = %v, want context.Canceled", err)
	}
	enc := "$argon2id$v=19$m=64,t=1,p=1$c2FsdA$aGFzaA"
	if _, _, err := h.Verify(ctx, "x", enc); !errors.Is(err, context.Canceled) {
		t.Errorf("Verify() err = %v, want context.Canceled", err)
	}
}
