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
	"github.com/vvangz/JikeLog/server/internal/admin"
	"github.com/vvangz/JikeLog/server/internal/attachment"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/export"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/crypto"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/pusher"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
	"github.com/vvangz/JikeLog/server/internal/realtime"
	"github.com/vvangz/JikeLog/server/internal/reminder"
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
	// Reminders 发送到期的备忘录提醒（测试可直接调用 Tick）。
	Reminders *reminder.Dispatcher
	// Exports 生成数据导出文件（测试可直接调用 Tick 与 Cleanup）。
	Exports *export.Service
	// Admins 为管理后台（测试可直接创建管理员）。
	Admins *admin.Service

	hub         *realtime.Hub
	attachments *attachment.Service
	logger      *slog.Logger
}

// ObjectStore 为对象存储（*storage.Store 实现）：附件直传直下与导出文件。
type ObjectStore interface {
	attachment.ObjectStore
	export.ObjectStore
}

// Options 为组装服务所需的外部依赖。
type Options struct {
	Name   string
	Config config.Config
	Logger *slog.Logger
	Pool   *pgxpool.Pool
	Redis  *redis.Client
	// Store 为对象存储（附件与导出文件）。
	Store ObjectStore
	// Argon2 为空时使用 auth.DefaultArgon2Params（测试可传入低成本参数）。
	Argon2 *auth.Argon2Params
	// Now 为空时使用 time.Now（测试可注入可控时钟）。
	Now func() time.Time
	// Pusher 为空时按配置创建（测试可注入记录推送的实现）。
	Pusher pusher.Pusher
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
	push := o.Pusher
	if push == nil {
		push = newPusher(o.Config.Push, o.Logger)
	}
	exports := export.NewService(export.Deps{
		Tx: tx, Store: o.Store, Records: syncSvc, Pusher: push, Logger: o.Logger, Now: o.Now,
	})
	admins := newAdminService(o, tx, limiter)
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
		Export:     export.NewHandler(exports),
		Admin:      admin.NewHandler(admins, o.Config.IsDeployed()),
	})
	ws := hub.Handler(realtime.Options{Check: authSvc, Cursor: syncSvc.Cursor, Limiter: limiter})
	router, err := NewRouter(o.Config, o.Logger, api, authSvc, admins, ws)
	if err != nil {
		return nil, err
	}
	reminders := reminder.NewDispatcher(reminder.Deps{Tx: tx, Pusher: push, Logger: o.Logger, Now: o.Now})
	return &App{
		Handler: router, SMS: sender, Reminders: reminders, Exports: exports, Admins: admins,
		hub: hub, attachments: attSvc, logger: o.Logger,
	}, nil
}

// RunBackground 运行后台任务（跨实例通知订阅、备忘录提醒、数据导出、附件对象清理），ctx 取消时关闭全部 WebSocket 连接后返回。
func (a *App) RunBackground(ctx context.Context) {
	go a.hub.Run(ctx)
	go a.Reminders.Run(ctx)
	go a.Exports.Run(ctx)
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
			if err := a.Admins.Cleanup(ctx); err != nil {
				a.logger.WarnContext(ctx, "admin session cleanup failed", "error", err)
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

// newAdminService 创建管理后台服务：管理员令牌的签名密钥由 JWT 密钥派生，与用户令牌不同（ADR-011）。
func newAdminService(o Options, tx db.TxRunner, limiter *ratelimit.Limiter) *admin.Service {
	params := auth.DefaultArgon2Params
	if o.Argon2 != nil {
		params = *o.Argon2
	}
	return admin.NewService(admin.Deps{
		Tx: tx, Hasher: auth.NewHasher(params), Limiter: limiter, Logger: o.Logger, Now: o.Now,
		Tokens: admin.NewTokens(o.Config.Auth.JWTSecret, o.Config.Auth.JWTPreviousSecret, o.Now),
		Quota:  o.Config.Attachment.Quota,
	})
}

func newSystemHandler(o Options) *system.Handler {
	return system.NewHandler(system.Config{Name: o.Name, Logger: o.Logger, Now: o.Now, Checks: []system.Checker{
		system.NewCheck("postgres", o.Pool.Ping),
		system.NewCheck("redis", func(ctx context.Context) error { return o.Redis.Ping(ctx).Err() }),
	}})
}

func newPusher(cfg config.Push, logger *slog.Logger) pusher.Pusher {
	if cfg.Provider == config.PushProviderJPush {
		return pusher.NewJPush(pusher.JPushConfig{AppKey: cfg.JPushAppKey, MasterSecret: cfg.JPushMasterSecret, Endpoint: cfg.JPushEndpoint}, nil)
	}
	return pusher.Log{Logger: logger}
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
