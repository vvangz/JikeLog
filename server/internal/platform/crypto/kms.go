package crypto

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
)

// KeyWrapper 用主密钥包裹（加密）和解包数据密钥。生产环境由阿里云 KMS 实现（v0.9.0）。
type KeyWrapper interface {
	// Wrap 返回主密钥标识和被包裹的数据密钥。
	Wrap(ctx context.Context, dek []byte) (keyID string, wrapped []byte, err error)
	// Unwrap 用 keyID 对应的主密钥解包。
	Unwrap(ctx context.Context, keyID string, wrapped []byte) ([]byte, error)
}

// LocalKeyWrapper 用进程内的主密钥做 AES-256-GCM 包裹，供开发和测试环境使用。
type LocalKeyWrapper struct {
	id  string
	key []byte
}

var wrapAAD = []byte("jikelog-dek-wrap-v1")

// NewLocalKeyWrapper 由 base64 编码的 32 字节主密钥创建。
func NewLocalKeyWrapper(b64 string) (*LocalKeyWrapper, error) {
	key, err := base64.StdEncoding.DecodeString(b64)
	if err != nil || len(key) != KeySize {
		return nil, errors.New("本地主密钥必须是 base64 编码的 32 字节")
	}
	sum := sha256.Sum256(key)
	return &LocalKeyWrapper{id: "local:" + hex.EncodeToString(sum[:4]), key: key}, nil
}

// Wrap 实现 KeyWrapper。
func (w *LocalKeyWrapper) Wrap(_ context.Context, dek []byte) (string, []byte, error) {
	wrapped, err := Seal(w.key, dek, wrapAAD)
	return w.id, wrapped, err
}

// Unwrap 实现 KeyWrapper。
func (w *LocalKeyWrapper) Unwrap(_ context.Context, keyID string, wrapped []byte) ([]byte, error) {
	if keyID != w.id {
		return nil, errors.New("主密钥标识不匹配，可能更换了主密钥")
	}
	return Open(w.key, wrapped, wrapAAD)
}
