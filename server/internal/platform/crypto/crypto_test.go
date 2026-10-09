package crypto

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestSealOpenRoundTrip(t *testing.T) {
	key, err := NewDataKey()
	if err != nil {
		t.Fatal(err)
	}
	sealed, err := SealString(key, "工作内容", []byte("aad"))
	if err != nil {
		t.Fatal(err)
	}
	got, err := OpenString(key, sealed, []byte("aad"))
	if err != nil || got != "工作内容" {
		t.Fatalf("got=%q err=%v", got, err)
	}
	again, _ := SealString(key, "工作内容", []byte("aad"))
	if again == sealed {
		t.Fatal("每次加密应使用不同的随机数")
	}
}

func TestOpenRejectsTamperingAndWrongContext(t *testing.T) {
	key, _ := NewDataKey()
	other, _ := NewDataKey()
	sealed, _ := Seal(key, []byte("secret"), []byte("a"))
	flipped := bytes.Clone(sealed)
	flipped[len(flipped)-1] ^= 1
	cases := map[string]func() error{
		"错误的 AAD":  func() error { _, err := Open(key, sealed, []byte("b")); return err },
		"错误的密钥":    func() error { _, err := Open(other, sealed, []byte("a")); return err },
		"篡改密文":     func() error { _, err := Open(key, flipped, []byte("a")); return err },
		"过短":       func() error { _, err := Open(key, sealed[:10], []byte("a")); return err },
		"非 base64": func() error { _, err := OpenString(key, "%%%", nil); return err },
	}
	for name, fn := range cases {
		if err := fn(); !errors.Is(err, ErrDecrypt) {
			t.Errorf("%s：err=%v", name, err)
		}
	}
	if _, err := Seal([]byte("short"), nil, nil); err == nil {
		t.Error("密钥长度错误应当报错")
	}
	if _, err := Open([]byte("short"), sealed, nil); err == nil {
		t.Error("密钥长度错误应当报错")
	}
	if _, err := SealString([]byte("short"), "", nil); err == nil {
		t.Error("密钥长度错误应当报错")
	}
	if _, err := OpenString([]byte("short"), base64.StdEncoding.EncodeToString(sealed), nil); err == nil {
		t.Error("密钥长度错误应当报错")
	}
}

func TestLocalKeyWrapper(t *testing.T) {
	master := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, KeySize))
	w, err := NewLocalKeyWrapper(master)
	if err != nil {
		t.Fatal(err)
	}
	dek, _ := NewDataKey()
	id, wrapped, err := w.Wrap(context.Background(), dek)
	if err != nil {
		t.Fatal(err)
	}
	got, err := w.Unwrap(context.Background(), id, wrapped)
	if err != nil || !bytes.Equal(got, dek) {
		t.Fatalf("err=%v", err)
	}
	if _, err := w.Unwrap(context.Background(), "local:other", wrapped); err == nil {
		t.Fatal("主密钥标识不符应当报错")
	}
	for _, bad := range []string{"not-base64!", base64.StdEncoding.EncodeToString([]byte("short"))} {
		if _, err := NewLocalKeyWrapper(bad); err == nil {
			t.Errorf("%q 应当报错", bad)
		}
	}
}

func TestDeriveSessionKeyAgreesOnBothSides(t *testing.T) {
	server, _ := ecdh.X25519().GenerateKey(rand.Reader)
	client, _ := ecdh.X25519().GenerateKey(rand.Reader)
	cp, sp := client.PublicKey().Bytes(), server.PublicKey().Bytes()
	k1, err := DeriveSessionKey(server, client.PublicKey(), cp, sp)
	if err != nil {
		t.Fatal(err)
	}
	k2, _ := DeriveSessionKey(client, server.PublicKey(), cp, sp)
	if !bytes.Equal(k1, k2) || len(k1) != KeySize {
		t.Fatal("双方派生的会话密钥应一致")
	}
}

// e2eVector 与 Dart 端共用（apps/mobile/test/core/crypto），保证两端派生的会话密钥、AAD 和密文格式一致。
type e2eVector struct {
	ServerPrivateKey string `json:"serverPrivateKey"`
	ServerPublicKey  string `json:"serverPublicKey"`
	ServerKeyID      string `json:"serverKeyId"`
	ClientPrivateKey string `json:"clientPrivateKey"`
	ClientPublicKey  string `json:"clientPublicKey"`
	SessionKey       string `json:"sessionKey"`
	AAD              string `json:"aad"`
	Plaintext        string `json:"plaintext"`
	Sealed           string `json:"sealed"`
}

func TestE2ESharedVector(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "testdata", "crypto", "e2e.json"))
	if err != nil {
		t.Fatal(err)
	}
	var v e2eVector
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	serverPriv, err := ParseX25519PrivateKey(v.ServerPrivateKey)
	if err != nil {
		t.Fatal(err)
	}
	clientPub, err := ParseX25519PublicKey(v.ClientPublicKey)
	if err != nil {
		t.Fatal(err)
	}
	if got := base64.StdEncoding.EncodeToString(serverPriv.PublicKey().Bytes()); got != v.ServerPublicKey {
		t.Fatalf("服务端公钥=%s", got)
	}
	if got := KeyID(serverPriv.PublicKey()); got != v.ServerKeyID {
		t.Fatalf("keyId=%s", got)
	}
	key, err := DeriveSessionKey(serverPriv, clientPub, clientPub.Bytes(), serverPriv.PublicKey().Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if got := base64.StdEncoding.EncodeToString(key); got != v.SessionKey {
		t.Fatalf("sessionKey=%s", got)
	}
	plain, err := OpenString(key, v.Sealed, []byte(v.AAD))
	if err != nil || plain != v.Plaintext {
		t.Fatalf("plain=%q err=%v", plain, err)
	}
}

func TestParseX25519KeysRejectInvalid(t *testing.T) {
	for _, s := range []string{"%%%", base64.StdEncoding.EncodeToString([]byte("short"))} {
		if _, err := ParseX25519PrivateKey(s); err == nil {
			t.Errorf("私钥 %q 应当报错", s)
		}
		if _, err := ParseX25519PublicKey(s); err == nil {
			t.Errorf("公钥 %q 应当报错", s)
		}
	}
}
