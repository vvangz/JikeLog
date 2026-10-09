package cache

import (
	"context"
	"strings"
	"testing"

	"github.com/alicebob/miniredis/v2"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
)

func TestOpen(t *testing.T) {
	mr := miniredis.RunT(t)
	mr.RequireAuth("pw")
	rdb, err := Open(context.Background(), config.Redis{URL: "redis://:pw@" + mr.Addr() + "/0"})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer func() { _ = rdb.Close() }()
	if err := rdb.Set(context.Background(), KeyPrefix+"k", "v", 0).Err(); err != nil {
		t.Fatal(err)
	}
}

func TestOpenErrors(t *testing.T) {
	ctx := context.Background()
	if _, err := Open(ctx, config.Redis{URL: "http://:secret@h"}); err == nil || strings.Contains(err.Error(), "secret") {
		t.Errorf("非法 URL: err = %v, want 不含密码的错误", err)
	}
	mr := miniredis.RunT(t)
	mr.RequireAuth("pw")
	if _, err := Open(ctx, config.Redis{URL: "redis://:wrong@" + mr.Addr()}); err == nil {
		t.Error("密码错误应返回错误")
	}
}
