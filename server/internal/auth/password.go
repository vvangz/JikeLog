package auth

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"runtime"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Argon2Params 为 argon2id 参数。默认值取 OWASP 推荐的最低配置（19 MiB / 2 次迭代 / 1 线程），
// 在登录高峰时内存占用可控；以后提高参数时，旧哈希会在用户下次登录时自动升级。
type Argon2Params struct {
	MemoryKiB uint32
	Time      uint32
	Threads   uint8
}

// DefaultArgon2Params 为生产使用的参数。
var DefaultArgon2Params = Argon2Params{MemoryKiB: 19 * 1024, Time: 2, Threads: 1}

const (
	saltLen = 16
	keyLen  = 32
)

var errMalformedHash = errors.New("密码哈希格式错误")

// Hasher 计算与校验 argon2id 密码哈希，并限制同时进行的哈希数量，防止大量并发登录请求耗尽内存。
type Hasher struct {
	params Argon2Params
	sem    chan struct{}
}

// NewHasher 创建 Hasher；并发上限为 CPU 核数。
func NewHasher(p Argon2Params) *Hasher {
	return &Hasher{params: p, sem: make(chan struct{}, runtime.NumCPU())}
}

func (h *Hasher) acquire(ctx context.Context) error {
	select {
	case h.sem <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (h *Hasher) release() { <-h.sem }

// Hash 返回 PHC 格式的哈希：$argon2id$v=19$m=…,t=…,p=…$<salt>$<hash>
func (h *Hasher) Hash(ctx context.Context, password string) (string, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("生成盐失败: %w", err)
	}
	if err := h.acquire(ctx); err != nil {
		return "", err
	}
	defer h.release()
	p := h.params
	key := argon2.IDKey([]byte(password), salt, p.Time, p.MemoryKiB, p.Threads, keyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s", argon2.Version, p.MemoryKiB, p.Time, p.Threads,
		b64.EncodeToString(salt), b64.EncodeToString(key)), nil
}

// Verify 校验密码。needsRehash 为 true 表示哈希参数已过时，调用方应在校验成功后用新参数重新哈希保存。
func (h *Hasher) Verify(ctx context.Context, password, encoded string) (ok, needsRehash bool, err error) {
	p, salt, want, err := decodeHash(encoded)
	if err != nil {
		return false, false, err
	}
	if err := h.acquire(ctx); err != nil {
		return false, false, err
	}
	defer h.release()
	got := argon2.IDKey([]byte(password), salt, p.Time, p.MemoryKiB, p.Threads, uint32(len(want))) //nolint:gosec // 长度来自自身生成的哈希
	if subtle.ConstantTimeCompare(got, want) != 1 {
		return false, false, nil
	}
	return true, p != h.params, nil
}

var b64 = base64.RawStdEncoding

func decodeHash(encoded string) (Argon2Params, []byte, []byte, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return Argon2Params{}, nil, nil, errMalformedHash
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return Argon2Params{}, nil, nil, errMalformedHash
	}
	var p Argon2Params
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.MemoryKiB, &p.Time, &p.Threads); err != nil {
		return Argon2Params{}, nil, nil, errMalformedHash
	}
	salt, err := b64.DecodeString(parts[4])
	if err != nil {
		return Argon2Params{}, nil, nil, errMalformedHash
	}
	key, err := b64.DecodeString(parts[5])
	if err != nil || len(key) == 0 {
		return Argon2Params{}, nil, nil, errMalformedHash
	}
	return p, salt, key, nil
}
