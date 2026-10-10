package vault

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/crypto"
)

type fakeStore struct {
	rows    map[uuid.UUID]dbgen.UserKey
	gets    int
	inserts int
	failGet error
}

func (f *fakeStore) GetUserKey(_ context.Context, id uuid.UUID) (dbgen.UserKey, error) {
	f.gets++
	if f.failGet != nil {
		return dbgen.UserKey{}, f.failGet
	}
	row, ok := f.rows[id]
	if !ok {
		return dbgen.UserKey{}, pgx.ErrNoRows
	}
	return row, nil
}

func (f *fakeStore) InsertUserKey(_ context.Context, arg dbgen.InsertUserKeyParams) error {
	f.inserts++
	if _, exists := f.rows[arg.UserID]; !exists {
		f.rows[arg.UserID] = dbgen.UserKey{UserID: arg.UserID, KmsKeyID: arg.KmsKeyID, Wrapped: arg.Wrapped}
	}
	return nil
}

func newKeyring(t *testing.T, now func() time.Time) *Keyring {
	t.Helper()
	w, err := crypto.NewLocalKeyWrapper(base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{1}, 32)))
	if err != nil {
		t.Fatal(err)
	}
	return NewKeyring(w, now)
}

func TestDataKeyCreatesOnceAndCaches(t *testing.T) {
	ctx := context.Background()
	store := &fakeStore{rows: map[uuid.UUID]dbgen.UserKey{}}
	kr := newKeyring(t, nil)
	user := uuid.New()

	if _, err := kr.DataKey(ctx, store, user, false); !errors.Is(err, ErrNoKey) {
		t.Fatalf("不创建时应返回 ErrNoKey，err=%v", err)
	}
	k1, err := kr.DataKey(ctx, store, user, true)
	if err != nil || len(k1) != crypto.KeySize {
		t.Fatalf("err=%v", err)
	}
	// 新建的密钥不缓存（事务可能回滚），第二次从存储读取后才缓存
	k2, _ := kr.DataKey(ctx, store, user, true)
	gets := store.gets
	k2b, _ := kr.DataKey(ctx, store, user, true)
	if !bytes.Equal(k1, k2) || !bytes.Equal(k2, k2b) || store.gets != gets || store.inserts != 1 {
		t.Fatalf("第三次应命中缓存：gets=%d inserts=%d", store.gets, store.inserts)
	}

	// 缓存过期后从存储读取，得到同一把密钥
	kr2 := newKeyring(t, nil)
	k3, err := kr2.DataKey(ctx, store, user, false)
	if err != nil || !bytes.Equal(k1, k3) {
		t.Fatalf("另一个进程应解出同一把密钥：err=%v", err)
	}
}

func TestDataKeyCacheExpiresAndForget(t *testing.T) {
	ctx := context.Background()
	store := &fakeStore{rows: map[uuid.UUID]dbgen.UserKey{}}
	now := time.Unix(0, 0)
	kr := newKeyring(t, func() time.Time { return now })
	user := uuid.New()
	if _, err := kr.DataKey(ctx, store, user, true); err != nil {
		t.Fatal(err)
	}
	if _, err := kr.DataKey(ctx, store, user, false); err != nil {
		t.Fatal(err)
	}
	gets := store.gets
	now = now.Add(cacheTTL + time.Second)
	if _, err := kr.DataKey(ctx, store, user, false); err != nil || store.gets != gets+1 {
		t.Fatalf("过期后应重新读取：gets=%d err=%v", store.gets, err)
	}
	kr.Forget(user)
	if _, ok := kr.cached(user); ok {
		t.Fatal("Forget 后不应命中缓存")
	}
}

func TestDataKeyErrors(t *testing.T) {
	ctx := context.Background()
	user := uuid.New()
	kr := newKeyring(t, nil)
	if _, err := kr.DataKey(ctx, &fakeStore{failGet: errors.New("db down")}, user, true); err == nil {
		t.Fatal("存储出错应返回错误")
	}
	store := &fakeStore{rows: map[uuid.UUID]dbgen.UserKey{user: {UserID: user, KmsKeyID: "local:other", Wrapped: []byte("x")}}}
	if _, err := kr.DataKey(ctx, store, user, false); err == nil {
		t.Fatal("主密钥不符应返回错误")
	}
}

func TestCacheIsBounded(t *testing.T) {
	kr := newKeyring(t, nil)
	for range maxCached {
		kr.store(uuid.New(), []byte("k"))
	}
	kr.store(uuid.New(), []byte("k"))
	if len(kr.cache) != 1 {
		t.Fatalf("超过上限应清空重建，len=%d", len(kr.cache))
	}
}

func TestSealOpenField(t *testing.T) {
	key, _ := crypto.NewDataKey()
	user, rec := uuid.New(), uuid.New()
	sealed, err := SealField(key, user, rec, "content", "工作内容")
	if err != nil {
		t.Fatal(err)
	}
	if sealed[:3] != sealedPrefix {
		t.Fatalf("缺少格式前缀：%q", sealed)
	}
	got, err := OpenField(key, user, rec, "content", sealed)
	if err != nil || got != "工作内容" {
		t.Fatalf("got=%q err=%v", got, err)
	}
	for name, fn := range map[string]func() error{
		"换字段": func() error { _, err := OpenField(key, user, rec, "location", sealed); return err },
		"换记录": func() error { _, err := OpenField(key, user, uuid.New(), "content", sealed); return err },
		"换账号": func() error { _, err := OpenField(key, uuid.New(), rec, "content", sealed); return err },
		"无前缀": func() error { _, err := OpenField(key, user, rec, "content", "明文"); return err },
	} {
		if err := fn(); !errors.Is(err, crypto.ErrDecrypt) {
			t.Errorf("%s：err=%v", name, err)
		}
	}
	if _, err := SealField([]byte("short"), user, rec, "content", "x"); err == nil {
		t.Error("密钥错误应当报错")
	}
}
