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
	// Wrap 返回主密钥标识和被包裹的数据密钥。owner 为密钥所属账号，绑定到包裹结果中，
	// 防止有数据库写权限的人在账号之间互换密钥。
	Wrap(ctx context.Context, owner string, dek []byte) (keyID string, wrapped []byte, err error)
	// Unwrap 用 keyID 对应的主密钥解包。
	Unwrap(ctx context.Context, owner, keyID string, wrapped []byte) ([]byte, error)
}

// LocalKeyWrapper 用进程内的主密钥做 AES-256-GCM 包裹，供开发和测试环境使用。
type LocalKeyWrapper struct {
	id  string
	key []byte
}

func wrapAAD(owner string) []byte { return []byte("jikelog-dek-wrap-v1|" + owner) }

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
func (w *LocalKeyWrapper) Wrap(_ context.Context, owner string, dek []byte) (string, []byte, error) {
	wrapped, err := Seal(w.key, dek, wrapAAD(owner))
	return w.id, wrapped, err
}

// Unwrap 实现 KeyWrapper。
func (w *LocalKeyWrapper) Unwrap(_ context.Context, owner, keyID string, wrapped []byte) ([]byte, error) {
	if keyID != w.id {
		return nil, errors.New("主密钥标识不匹配，可能更换了主密钥")
	}
	return Open(w.key, wrapped, wrapAAD(owner))
}
