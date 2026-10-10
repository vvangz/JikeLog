package server

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/account"
	"github.com/vvangz/JikeLog/server/internal/attachment"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/crypto"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
	"github.com/vvangz/JikeLog/server/internal/realtime"
	"github.com/vvangz/JikeLog/server/internal/syncer"
	"github.com/vvangz/JikeLog/server/internal/system"
	"github.com/vvangz/JikeLog/server/internal/vault"
)

// cleanupInterval 为清理已删除附件对象的间隔。
const cleanupInterval = 10 * time.Minute

// App 为组装好的服务及其依赖。
type App struct {
	Handler http.Handler
	// SMS 为当前使用的短信通道；开发与测试环境为 *auth.MockSender，可读取最近发出的验证码。
	SMS auth.SMSSender

	hub         *realtime.Hub
	attachments *attachment.Service
	logger      *slog.Logger
}

// Options 为组装服务所需的外部依赖。
type Options struct {
	Name   string
	Config config.Config
	Logger *slog.Logger
	Pool   *pgxpool.Pool
	Redis  *redis.Client
	// Store 为对象存储（附件）。
	Store attachment.ObjectStore
	// Argon2 为空时使用 auth.DefaultArgon2Params（测试可传入低成本参数）。
	Argon2 *auth.Argon2Params
	// Now 为空时使用 time.Now（测试可注入可控时钟）。
	Now func() time.Time
}

// NewApp 用已建立的数据库、Redis 与对象存储连接组装全部模块和路由。
func NewApp(ctx context.Context, o Options) (*App, error) {
	if o.Now == nil {
		o.Now = time.Now
	}
	tx := db.NewTxRunner(o.Pool)
	limiter := ratelimit.New(o.Redis)
	authSvc, sender, err := newAuthService(ctx, o, tx, limiter)
	if err != nil {
		return nil, err
	}
	wrapper, err := newKeyWrapper(o.Config.KMS)
	if err != nil {
		return nil, err
	}
	keyring := vault.NewKeyring(wrapper, o.Now)
	sessions, err := e2e.NewManager(o.Redis, limiter, o.Config.E2E.PrivateKey, o.Config.E2E.PreviousPrivateKey, o.Now)
	if err != nil {
		return nil, err
	}
	hub := realtime.NewHub(o.Redis, o.Logger)
	syncSvc := syncer.NewService(syncer.Deps{Tx: tx, Keys: keyring, Notifier: hub, Limiter: limiter, Logger: o.Logger, Now: o.Now})
	attSvc := attachment.NewService(attachment.Deps{
		Tx: tx, Store: o.Store, Keys: keyring, Sync: syncSvc, Limits: o.Config.Attachment, Logger: o.Logger,
	})
	onDeleted := func(ctx context.Context, userID uuid.UUID) {
		keyring.Forget(userID)
		if err := attSvc.DeleteUserObjects(ctx, userID); err != nil {
			o.Logger.ErrorContext(ctx, "delete user objects failed", "user_id", userID, "error", err)
		}
	}
	api := NewAPI(Handlers{
		System:     newSystemHandler(o),
		Auth:       auth.NewHandler(authSvc),
		Account:    account.NewHandler(account.NewService(tx, authSvc, limiter, onDeleted)),
		Sync:       syncer.NewHandler(syncSvc, sessions),
		Attachment: attachment.NewHandler(attSvc, sessions),
	})
	ws := hub.Handler(realtime.Options{Check: authSvc, Cursor: syncSvc.Cursor, Limiter: limiter})
	router, err := NewRouter(o.Config, o.Logger, api, authSvc, ws)
	if err != nil {
		return nil, err
	}
	return &App{Handler: router, SMS: sender, hub: hub, attachments: attSvc, logger: o.Logger}, nil
}

// RunBackground 运行后台任务（跨实例通知订阅、附件对象清理），ctx 取消时关闭全部 WebSocket 连接后返回。
func (a *App) RunBackground(ctx context.Context) {
	go a.hub.Run(ctx)
	ticker := time.NewTicker(cleanupInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			// WebSocket 连接已被接管，http.Server.Shutdown 不会等待或关闭它们
			a.hub.Shutdown()
			return
		case <-ticker.C:
			if _, err := a.attachments.Cleanup(ctx, 100); err != nil {
				a.logger.WarnContext(ctx, "attachment cleanup failed", "error", err)
			}
		}
	}
}

func newAuthService(ctx context.Context, o Options, tx db.TxRunner, limiter *ratelimit.Limiter) (*auth.Service, auth.SMSSender, error) {
	sender, err := newSMSSender(o.Config.SMS, o.Logger)
	if err != nil {
		return nil, nil, err
	}
	if o.Config.Captcha.Provider != config.CaptchaProviderNone {
		return nil, nil, errors.New("阿里云验证码将在 v0.9.0 接入，当前版本请使用 JIKELOG_CAPTCHA_PROVIDER=none")
	}
	params := auth.DefaultArgon2Params
	if o.Argon2 != nil {
		params = *o.Argon2
	}
	tokens := auth.NewTokenManager(o.Config.Auth.JWTSecret, o.Config.Auth.JWTPreviousSecret, o.Config.Auth.AccessTTL, o.Now)
	svc, err := auth.NewService(ctx, auth.Deps{
		Tx: tx, Hasher: auth.NewHasher(params), Tokens: tokens,
		SMS:        auth.NewSMSCodes(o.Redis, limiter, sender, o.Logger, smsHashKey(o.Config.Auth.JWTSecret)),
		Tickets:    auth.NewRegistrationTickets(o.Redis),
		Replay:     auth.NewRefreshReplay(o.Redis),
		Captcha:    auth.NoopCaptcha{},
		Limiter:    limiter,
		RefreshTTL: o.Config.Auth.RefreshTTL,
		Logger:     o.Logger,
		Now:        o.Now,
	})
	if err != nil {
		return nil, nil, fmt.Errorf("初始化认证模块失败: %w", err)
	}
	return svc, sender, nil
}

func newSystemHandler(o Options) *system.Handler {
	return system.NewHandler(system.Config{Name: o.Name, Logger: o.Logger, Now: o.Now, Checks: []system.Checker{
		system.NewCheck("postgres", o.Pool.Ping),
		system.NewCheck("redis", func(ctx context.Context) error { return o.Redis.Ping(ctx).Err() }),
	}})
}

func newKeyWrapper(cfg config.KMS) (crypto.KeyWrapper, error) {
	switch cfg.Provider {
	case config.KMSProviderLocal:
		return crypto.NewLocalKeyWrapper(cfg.LocalMasterKey)
	case config.KMSProviderAliyun:
		return nil, errors.New("阿里云 KMS 将在 v0.9.0 接入，当前版本请使用 JIKELOG_KMS_PROVIDER=local")
	default:
		return nil, fmt.Errorf("未知 KMS 通道 %q", cfg.Provider)
	}
}

// smsHashKey 由服务端密钥派生验证码 HMAC 密钥（与签名用途分离）。轮换 JWT 密钥只会让 5 分钟内未使用的验证码失效。
func smsHashKey(secret string) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte("jikelog-sms-code-hmac"))
	return mac.Sum(nil)
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
