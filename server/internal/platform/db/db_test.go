package db_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/testinfra"
)

func newUser(name string) dbgen.CreateUserParams {
	return dbgen.CreateUserParams{ID: uuid.Must(uuid.NewV7()), Username: name, PasswordHash: "x"}
}

func TestMigrateIsIdempotent(t *testing.T) {
	pool := testinfra.Postgres(t)
	n, err := db.Migrate(context.Background(), pool)
	if err != nil {
		t.Fatalf("Migrate() error = %v", err)
	}
	if n != 0 {
		t.Errorf("已迁移的库再次迁移应用了 %d 个版本，want 0", n)
	}
}

func TestInTxCommitsAndRollsBack(t *testing.T) {
	pool := testinfra.Postgres(t)
	ctx := context.Background()
	tx := db.NewTxRunner(pool)

	if err := tx.InTx(ctx, func(q *dbgen.Queries) error {
		_, err := q.CreateUser(ctx, newUser("committed"))
		return err
	}); err != nil {
		t.Fatalf("InTx() error = %v", err)
	}
	boom := errors.New("boom")
	err := tx.InTx(ctx, func(q *dbgen.Queries) error {
		if _, err := q.CreateUser(ctx, newUser("rolledback")); err != nil {
			return err
		}
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("InTx() error = %v, want boom", err)
	}

	if _, err := tx.Queries().GetUserByUsername(ctx, "COMMITTED"); err != nil {
		t.Errorf("已提交的用户应可按不区分大小写的用户名查到: %v", err)
	}
	if _, err := tx.Queries().GetUserByUsername(ctx, "rolledback"); !db.IsNotFound(err) {
		t.Errorf("回滚的用户不应存在，err = %v", err)
	}
}

func TestIsUniqueViolation(t *testing.T) {
	pool := testinfra.Postgres(t)
	ctx := context.Background()
	q := dbgen.New(pool)
	if _, err := q.CreateUser(ctx, newUser("alice")); err != nil {
		t.Fatal(err)
	}
	_, err := q.CreateUser(ctx, newUser("ALICE"))
	if !db.IsUniqueViolation(err, "users_username_key") {
		t.Fatalf("用户名大小写不同也应冲突，err = %v", err)
	}
	if !db.IsUniqueViolation(err, "") {
		t.Error("constraint 为空时应匹配任意唯一约束")
	}
	if db.IsUniqueViolation(err, "users_phone_key") {
		t.Error("不应匹配其他约束")
	}
	if db.IsUniqueViolation(errors.New("x"), "") || db.IsNotFound(errors.New("x")) {
		t.Error("普通错误不应被识别为数据库错误")
	}
	if !db.IsNotFound(pgx.ErrNoRows) {
		t.Error("IsNotFound(ErrNoRows) = false")
	}
}

func TestSchemaConstraints(t *testing.T) {
	pool := testinfra.Postgres(t)
	ctx := context.Background()
	q := dbgen.New(pool)
	bad := []string{"ab", "1abc", "has space", strings.Repeat("a", 21), "名字abc"}
	for _, name := range bad {
		if _, err := q.CreateUser(ctx, newUser(name)); err == nil {
			t.Errorf("用户名 %q 应被约束拒绝", name)
		}
	}
	phone := "13800000000" // 缺少 +86
	p := newUser("bob1")
	p.Phone = &phone
	if _, err := q.CreateUser(ctx, p); err == nil {
		t.Error("非 E.164 手机号应被约束拒绝")
	}
}

func TestOpenRejectsBadURL(t *testing.T) {
	ctx := context.Background()
	_, err := db.Open(ctx, config.DB{URL: "postgres://u:secret@%zz/db", MaxConns: 1})
	if err == nil || strings.Contains(err.Error(), "secret") {
		t.Fatalf("Open() error = %v, want 不含密码的错误", err)
	}
	if _, err := db.Open(ctx, config.DB{URL: "postgres://u:p@127.0.0.1:1/db?connect_timeout=1", MaxConns: 1}); err == nil {
		t.Fatal("连接不可达的数据库应返回错误")
	}
}

func TestMigrateReportsBadScript(t *testing.T) {
	pool := testinfra.Postgres(t)
	fsys := fstest.MapFS{"00099_bad.sql": {Data: []byte("-- +goose Up\nSELEC 1;\n")}}
	if _, err := db.MigrateFS(context.Background(), pool, fsys); err == nil {
		t.Fatal("错误的迁移脚本应返回错误")
	}
}
