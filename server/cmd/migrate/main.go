// Command migrate 把内嵌的数据库迁移应用到 JIKELOG_DB_URL 指向的数据库。
// 部署时在新版本 API 启动前执行；迁移只向前，回滚通过发布修复迁移完成。
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	pool, err := db.Open(ctx, cfg.DB)
	if err != nil {
		return err
	}
	defer pool.Close()
	n, err := db.Migrate(ctx, pool)
	if err != nil {
		return err
	}
	fmt.Printf("迁移完成，本次应用 %d 个版本\n", n)
	return nil
}
