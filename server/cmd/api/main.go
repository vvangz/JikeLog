// Command api 是即刻日志的 HTTP API 服务入口。
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/logging"
	"github.com/vvangz/JikeLog/server/internal/server"
	"github.com/vvangz/JikeLog/server/internal/system"
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

	api := server.NewAPI(system.NewHandler(system.Config{Name: serviceName, Logger: logger}))
	router, err := server.NewRouter(cfg, logger, api)
	if err != nil {
		return err
	}
	return server.ListenAndServe(ctx, router, cfg.HTTP, logger)
}
