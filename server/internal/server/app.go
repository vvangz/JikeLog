package server

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/account"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
	"github.com/vvangz/JikeLog/server/internal/system"
)

// App 为组装好的服务及其依赖。
type App struct {
	Handler http.Handler
	// SMS 为当前使用的短信通道；开发与测试环境为 *auth.MockSender，可读取最近发出的验证码。
	SMS auth.SMSSender
}

// Options 为组装服务所需的外部依赖。
type Options struct {
	Name   string
	Config config.Config
	Logger *slog.Logger
	Pool   *pgxpool.Pool
	Redis  *redis.Client
	// Argon2 为空时使用 auth.DefaultArgon2Params（测试可传入低成本参数）。
	Argon2 *auth.Argon2Params
	// Now 为空时使用 time.Now（测试可注入可控时钟）。
	Now func() time.Time
}

// NewApp 用已建立的数据库与 Redis 连接组装全部模块和路由。
func NewApp(ctx context.Context, o Options) (*App, error) {
	sender, err := newSMSSender(o.Config.SMS, o.Logger)
	if err != nil {
		return nil, err
	}
	params := auth.DefaultArgon2Params
	if o.Argon2 != nil {
		params = *o.Argon2
	}
	tx := db.NewTxRunner(o.Pool)
	limiter := ratelimit.New(o.Redis)
	tokens := auth.NewTokenManager(o.Config.Auth.JWTSecret, o.Config.Auth.JWTPreviousSecret, o.Config.Auth.AccessTTL, o.Now)
	authSvc, err := auth.NewService(ctx, auth.Deps{
		Tx: tx, Hasher: auth.NewHasher(params), Tokens: tokens,
		SMS:        auth.NewSMSCodes(o.Redis, limiter, sender, o.Logger),
		Tickets:    auth.NewRegistrationTickets(o.Redis),
		Revoked:    auth.NewRevocations(o.Redis, o.Config.Auth.AccessTTL),
		Limiter:    limiter,
		RefreshTTL: o.Config.Auth.RefreshTTL,
		Logger:     o.Logger,
		Now:        o.Now,
	})
	if err != nil {
		return nil, fmt.Errorf("初始化认证模块失败: %w", err)
	}
	sys := system.NewHandler(system.Config{Name: o.Name, Logger: o.Logger, Now: o.Now, Checks: []system.Checker{
		system.NewCheck("postgres", o.Pool.Ping),
		system.NewCheck("redis", func(ctx context.Context) error { return o.Redis.Ping(ctx).Err() }),
	}})
	api := NewAPI(Handlers{
		System:  sys,
		Auth:    auth.NewHandler(authSvc),
		Account: account.NewHandler(account.NewService(tx, authSvc, limiter)),
	})
	router, err := NewRouter(o.Config, o.Logger, api, authSvc)
	if err != nil {
		return nil, err
	}
	return &App{Handler: router, SMS: sender}, nil
}

func newSMSSender(cfg config.SMS, logger *slog.Logger) (auth.SMSSender, error) {
	switch cfg.Provider {
	case config.SMSProviderMock:
		return &auth.MockSender{Logger: logger}, nil
	case config.SMSProviderAliyun:
		return nil, errors.New("阿里云短信通道将在 v0.9.0 接入，当前版本请使用 JIKELOG_SMS_PROVIDER=mock")
	default:
		return nil, fmt.Errorf("未知短信通道 %q", cfg.Provider)
	}
}
