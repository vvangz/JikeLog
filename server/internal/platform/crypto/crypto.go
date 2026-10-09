// Package crypto 提供工作日志加密所需的密码学原语（ADR-006）：
// AES-256-GCM 字段加密、本地主密钥包裹（KMS 的开发实现）、X25519 + HKDF 会话密钥派生。
package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
)

// KeySize 为 AES-256 密钥长度。
const KeySize = 32

const nonceSize = 12

// ErrDecrypt 表示密文被篡改、密钥不符或格式错误。不区分具体原因，避免成为解密预言机。
var ErrDecrypt = errors.New("解密失败")

// Seal 用 AES-256-GCM 加密，返回 nonce ‖ 密文 ‖ 标签。aad 把密文绑定到具体用途和位置。
func Seal(key, plaintext, aad []byte) ([]byte, error) {
	gcm, err := newGCM(key)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, nonceSize)
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("生成随机数失败: %w", err)
	}
	return gcm.Seal(nonce, nonce, plaintext, aad), nil
}

// Open 解密 Seal 的输出。
func Open(key, sealed, aad []byte) ([]byte, error) {
	gcm, err := newGCM(key)
	if err != nil {
		return nil, err
	}
	if len(sealed) < nonceSize+gcm.Overhead() {
		return nil, ErrDecrypt
	}
	plain, err := gcm.Open(nil, sealed[:nonceSize], sealed[nonceSize:], aad)
	if err != nil {
		return nil, ErrDecrypt
	}
	return plain, nil
}

// SealString 加密字符串并返回标准 base64。
func SealString(key []byte, plaintext string, aad []byte) (string, error) {
	sealed, err := Seal(key, []byte(plaintext), aad)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// OpenString 解密 SealString 的输出。
func OpenString(key []byte, encoded string, aad []byte) (string, error) {
	sealed, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", ErrDecrypt
	}
	plain, err := Open(key, sealed, aad)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}

func newGCM(key []byte) (cipher.AEAD, error) {
	if len(key) != KeySize {
		return nil, fmt.Errorf("密钥长度必须为 %d 字节", KeySize)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("初始化 AES 失败: %w", err)
	}
	return cipher.NewGCM(block)
}

// NewDataKey 生成随机数据密钥（DEK）。
func NewDataKey() ([]byte, error) {
	key := make([]byte, KeySize)
	if _, err := rand.Read(key); err != nil {
		return nil, fmt.Errorf("生成数据密钥失败: %w", err)
	}
	return key, nil
}

// E2EInfo 为传输加密会话密钥派生的 HKDF info，客户端必须一致。
const E2EInfo = "jikelog-e2e-v1"

// ParseX25519PrivateKey 解析 base64 编码的 32 字节 X25519 私钥。
func ParseX25519PrivateKey(b64 string) (*ecdh.PrivateKey, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, errors.New("X25519 私钥不是合法的 base64")
	}
	key, err := ecdh.X25519().NewPrivateKey(raw)
	if err != nil {
		return nil, errors.New("X25519 私钥必须为 32 字节")
	}
	return key, nil
}

// ParseX25519PublicKey 解析 base64 编码的 32 字节 X25519 公钥。
func ParseX25519PublicKey(b64 string) (*ecdh.PublicKey, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, errors.New("X25519 公钥不是合法的 base64")
	}
	key, err := ecdh.X25519().NewPublicKey(raw)
	if err != nil {
		return nil, errors.New("X25519 公钥必须为 32 字节")
	}
	return key, nil
}

// KeyID 返回公钥标识：SHA-256 前 8 字节的十六进制。客户端据此告诉服务端它内置的是哪把公钥。
func KeyID(pub *ecdh.PublicKey) string {
	sum := sha256.Sum256(pub.Bytes())
	return hex.EncodeToString(sum[:8])
}

// DeriveSessionKey 由己方私钥和对方公钥派生会话密钥：
// HKDF-SHA256(X25519(priv, peer), salt = 客户端公钥 ‖ 服务端公钥, info = E2EInfo)。
func DeriveSessionKey(priv *ecdh.PrivateKey, peer *ecdh.PublicKey, clientPub, serverPub []byte) ([]byte, error) {
	shared, err := priv.ECDH(peer)
	if err != nil {
		return nil, errors.New("密钥协商失败")
	}
	salt := make([]byte, 0, len(clientPub)+len(serverPub))
	salt = append(append(salt, clientPub...), serverPub...)
	return hkdf.Key(sha256.New, shared, salt, E2EInfo, KeySize)
}
