// Command api 是即刻日志的 HTTP API 服务入口。
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/platform/cache"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/logging"
	"github.com/vvangz/JikeLog/server/internal/platform/storage"
	"github.com/vvangz/JikeLog/server/internal/server"
	"github.com/vvangz/JikeLog/server/internal/version"
)

const serviceName = "jikelog-api"

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
	logger, err := logging.New(cfg.Log.Level, cfg.Log.Format, os.Stdout)
	if err != nil {
		return err
	}
	logger = logger.With("service", serviceName, "version", version.Version, "env", cfg.Env)

	if cfg.Env != config.EnvDevelopment {
		gin.SetMode(gin.ReleaseMode)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		stop() // 恢复默认信号处理：优雅关闭期间再次 Ctrl+C 可立即退出
	}()

	pool, err := db.Open(ctx, cfg.DB)
	if err != nil {
		return err
	}
	defer pool.Close()
	rdb, err := cache.Open(ctx, cfg.Redis)
	if err != nil {
		return err
	}
	defer func() { _ = rdb.Close() }()

	store, err := storage.New(cfg.Storage)
	if err != nil {
		return err
	}
	if cfg.Env == config.EnvDevelopment {
		// 本地开发自动创建存储桶；生产环境的桶与访问策略由运维预先配置
		if err := store.EnsureBucket(ctx); err != nil {
			return err
		}
	}

	app, err := server.NewApp(ctx, server.Options{Name: serviceName, Config: cfg, Logger: logger, Pool: pool, Redis: rdb, Store: store})
	if err != nil {
		return err
	}
	bgDone := make(chan struct{})
	go func() {
		defer close(bgDone)
		app.RunBackground(ctx)
	}()
	err = server.ListenAndServe(ctx, app.Handler, cfg.HTTP, logger)
	stop()
	<-bgDone
	return err
}
