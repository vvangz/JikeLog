// Package server 组装路由、中间件与各业务模块处理器，并负责 HTTP 服务的启动与优雅关闭。
package server

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/vvangz/JikeLog/server/internal/account"
	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/system"
)

// 各模块处理器类型名都叫 Handler，用别名嵌入以避免字段名冲突。
type (
	systemHandler  = system.Handler
	authHandler    = auth.Handler
	accountHandler = account.Handler
)

// API 聚合所有模块处理器，实现生成的 StrictServerInterface。
type API struct {
	*systemHandler
	*authHandler
	*accountHandler
}

var _ apigen.StrictServerInterface = API{}

// Handlers 为各模块处理器。
type Handlers struct {
	System  *system.Handler
	Auth    *auth.Handler
	Account *account.Handler
}

// NewAPI 创建 API。
func NewAPI(h Handlers) API {
	return API{systemHandler: h.System, authHandler: h.Auth, accountHandler: h.Account}
}

// maxBodyBytes 为 JSON 请求体上限；附件走对象存储直传，不经过 API。
const maxBodyBytes = 1 << 20

// NewRouter 创建 Gin 引擎并注册全部路由。authn 用于默认拒绝的认证中间件：除公开路由外都必须登录。
func NewRouter(cfg config.Config, logger *slog.Logger, api API, authn *auth.Service) (*gin.Engine, error) {
	r := gin.New()
	// 让 *gin.Context 作为 context.Context 时继承请求的取消与截止时间（客户端断开即取消下游调用）
	r.ContextWithFallback = true
	if err := r.SetTrustedProxies(cfg.HTTP.TrustedProxies); err != nil {
		return nil, fmt.Errorf("设置可信代理失败: %w", err)
	}
	r.HandleMethodNotAllowed = true
	r.Use(
		httpx.RequestID(), httpx.SecurityHeaders(), httpx.AccessLog(logger), httpx.Recovery(logger),
		httpx.CORS(cfg.HTTP.CORSOrigins), httpx.ClientIP(), httpx.BodyLimit(maxBodyBytes),
		auth.Middleware(authn, isPublicRoute),
	)
	r.NoRoute(func(c *gin.Context) {
		httpx.Fail(c, http.StatusNotFound, httpx.CodeNotFound, httpx.MsgNotFound)
	})
	r.NoMethod(func(c *gin.Context) {
		httpx.Fail(c, http.StatusMethodNotAllowed, httpx.CodeMethodNotAllowed, httpx.MsgMethodNotAllowed)
	})

	strict := apigen.NewStrictHandlerWithOptions(api, nil, httpx.StrictOptions(logger))
	opts := apigen.GinServerOptions{
		ErrorHandler: func(c *gin.Context, err error, status int) {
			logger.InfoContext(c, "request rejected", "request_id", httpx.RequestIDFrom(c), "error", err)
			httpx.Fail(c, status, httpx.CodeBadRequest, httpx.MsgBadRequest)
		},
	}
	apigen.RegisterHandlersWithOptions(r, strict, opts)
	registerProbeHEAD(r, strict, opts)
	return r, nil
}

// registerProbeHEAD 让探针同时响应 HEAD（阿里云 CLB 等负载均衡默认用 HEAD 做健康检查）。
// net/http 会自动丢弃 HEAD 响应体。
func registerProbeHEAD(r *gin.Engine, si apigen.ServerInterface, opts apigen.GinServerOptions) {
	w := apigen.ServerInterfaceWrapper{Handler: si, ErrorHandler: opts.ErrorHandler}
	r.HEAD("/healthz", w.GetHealthz)
	r.HEAD("/readyz", w.GetReadyz)
}

// maxHeaderBytes 限制请求头大小（默认 1MB 过大，易被用于消耗内存）。
const maxHeaderBytes = 64 << 10

func newHTTPServer(handler http.Handler, cfg config.HTTP, logger *slog.Logger) *http.Server {
	return &http.Server{
		Handler:           handler,
		ReadTimeout:       cfg.ReadTimeout,
		ReadHeaderTimeout: cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
		MaxHeaderBytes:    maxHeaderBytes,
		ErrorLog:          slog.NewLogLogger(logger.Handler(), slog.LevelWarn),
	}
}

// Serve 在给定监听器上提供服务，ctx 取消后在 ShutdownTimeout 内优雅关闭。
func Serve(ctx context.Context, ln net.Listener, handler http.Handler, cfg config.HTTP, logger *slog.Logger) error {
	srv := newHTTPServer(handler, cfg, logger)
	errCh := make(chan error, 1)
	go func() { errCh <- srv.Serve(ln) }()
	logger.Info("http server started", "addr", ln.Addr().String())

	select {
	case err := <-errCh:
		return fmt.Errorf("http 服务异常退出: %w", err)
	case <-ctx.Done():
	}

	logger.Info("http server shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), cfg.ShutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		_ = srv.Close() // 宽限期已过，强制断开剩余连接
		return fmt.Errorf("http 服务关闭失败: %w", err)
	}
	if err := <-errCh; err != nil && !errors.Is(err, http.ErrServerClosed) {
		return fmt.Errorf("http 服务异常退出: %w", err)
	}
	return nil
}

// ListenAndServe 监听 cfg.Addr 并提供服务。
func ListenAndServe(ctx context.Context, handler http.Handler, cfg config.HTTP, logger *slog.Logger) error {
	var lc net.ListenConfig
	ln, err := lc.Listen(ctx, "tcp", cfg.Addr)
	if err != nil {
		return fmt.Errorf("监听 %s 失败: %w", cfg.Addr, err)
	}
	return Serve(ctx, ln, handler, cfg, logger)
}
