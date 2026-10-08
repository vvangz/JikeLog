package system

import (
	"context"
	"io"
	"log/slog"
	"sync"
	"time"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/version"
)

// CodeDependencyUnavailable 表示至少一个依赖未就绪。
const CodeDependencyUnavailable = "DEPENDENCY_UNAVAILABLE"

const (
	defaultCheckTimeout  = 2 * time.Second
	defaultReadyCacheTTL = time.Second
)

// Config 为 Handler 的依赖与参数，零值字段会被填充默认值。
type Config struct {
	Name         string
	Logger       *slog.Logger
	CheckTimeout time.Duration
	// ReadyCacheTTL 为就绪结果缓存时长，避免公开的 /readyz 被高频调用放大为依赖压力。
	ReadyCacheTTL time.Duration
	Checks        []Checker
	Now           func() time.Time
}

// Handler 实现 system 标签下的接口。
type Handler struct {
	cfg Config

	readyMu     sync.Mutex
	readyAt     time.Time
	readyChecks []apigen.HealthCheck
}

// NewHandler 创建 Handler。
func NewHandler(cfg Config) *Handler {
	if cfg.Logger == nil {
		cfg.Logger = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if cfg.CheckTimeout <= 0 {
		cfg.CheckTimeout = defaultCheckTimeout
	}
	if cfg.ReadyCacheTTL <= 0 {
		cfg.ReadyCacheTTL = defaultReadyCacheTTL
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	cfg.Checks = append([]Checker(nil), cfg.Checks...)
	return &Handler{cfg: cfg}
}

// GetHealthz 存活探针：进程能响应即为存活。
func (h *Handler) GetHealthz(ctx context.Context, _ apigen.GetHealthzRequestObject) (apigen.GetHealthzResponseObject, error) {
	base := httpx.Base(ctx, nil)
	return apigen.GetHealthz200JSONResponse{
		Success:   base.Success,
		RequestId: base.RequestId,
		Data:      apigen.Health{Status: apigen.HealthStatusUp, Checks: []apigen.HealthCheck{}},
	}, nil
}

// GetReadyz 就绪探针：所有依赖可用才返回 200。
func (h *Handler) GetReadyz(ctx context.Context, _ apigen.GetReadyzRequestObject) (apigen.GetReadyzResponseObject, error) {
	checks := h.cachedChecks(httpx.RequestIDFrom(ctx))
	for _, c := range checks {
		if c.Status == apigen.HealthCheckStatusDown {
			base := httpx.Base(ctx, httpx.ErrorBody(CodeDependencyUnavailable, "依赖服务不可用"))
			return apigen.GetReadyz503JSONResponse{
				Success:   base.Success,
				RequestId: base.RequestId,
				Error:     base.Error,
				Data:      apigen.Health{Status: apigen.HealthStatusDown, Checks: checks},
			}, nil
		}
	}
	base := httpx.Base(ctx, nil)
	return apigen.GetReadyz200JSONResponse{
		Success:   base.Success,
		RequestId: base.RequestId,
		Data:      apigen.Health{Status: apigen.HealthStatusUp, Checks: checks},
	}, nil
}

// GetSystemInfo 返回服务名称、版本与服务器时间。
func (h *Handler) GetSystemInfo(ctx context.Context, _ apigen.GetSystemInfoRequestObject) (apigen.GetSystemInfoResponseObject, error) {
	base := httpx.Base(ctx, nil)
	return apigen.GetSystemInfo200JSONResponse{
		Success:   base.Success,
		RequestId: base.RequestId,
		Data: apigen.SystemInfo{
			Name:       h.cfg.Name,
			Version:    version.Version,
			Commit:     version.Commit,
			BuildTime:  version.BuildTime,
			ServerTime: h.cfg.Now().UTC(),
		},
	}, nil
}

// cachedChecks 在 TTL 内复用上次结果；并发请求串行等待同一次检查，而不是各自打到依赖上。
func (h *Handler) cachedChecks(requestID string) []apigen.HealthCheck {
	h.readyMu.Lock()
	defer h.readyMu.Unlock()
	now := h.cfg.Now()
	if h.readyChecks != nil && now.Sub(h.readyAt) < h.cfg.ReadyCacheTTL {
		return h.readyChecks
	}
	h.readyChecks = runChecks(h.cfg.Logger, h.cfg.CheckTimeout, h.cfg.Checks, requestID)
	h.readyAt = now
	return h.readyChecks
}
