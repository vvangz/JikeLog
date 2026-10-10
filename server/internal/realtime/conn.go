package realtime

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
)

// 自定义关闭码。
const (
	// CloseSessionRevoked 表示设备已下线或密码已修改，客户端应回到登录页。
	CloseSessionRevoked websocket.StatusCode = 4401
)

// CodeTooManyConnections 为连接数超限的错误码。
const CodeTooManyConnections = "TOO_MANY_CONNECTIONS"

// SessionChecker 重新确认设备会话（*auth.Service 实现）。
type SessionChecker interface {
	CheckSession(ctx context.Context, p auth.Principal) error
}

// CursorFunc 返回账号当前的同步序号。
type CursorFunc func(ctx context.Context, userID uuid.UUID) (int64, error)

// Options 为连接参数。
type Options struct {
	Check  SessionChecker
	Cursor CursorFunc
	// Limiter 限制每台设备的握手频率；为空时不限制（测试）。
	Limiter *ratelimit.Limiter
	// PingInterval 与 CheckInterval 为空时分别使用 30 秒与 1 分钟。
	PingInterval  time.Duration
	CheckInterval time.Duration
}

const (
	writeTimeout = 10 * time.Second
	checkTimeout = 10 * time.Second
	// handshakesPerHour 为每台设备每小时的握手次数上限（客户端断线重连有退避，回到前台才重新连接）。
	handshakesPerHour = 120
)

// Handler 返回 WebSocket 处理器。路由需经过认证中间件。
func (h *Hub) Handler(o Options) gin.HandlerFunc {
	if o.PingInterval == 0 {
		o.PingInterval = 30 * time.Second
	}
	if o.CheckInterval == 0 {
		o.CheckInterval = time.Minute
	}
	return func(c *gin.Context) {
		p, err := auth.MustPrincipal(c.Request.Context())
		if err != nil {
			httpx.WriteError(c, err)
			return
		}
		if err := limitHandshake(c.Request.Context(), o.Limiter, p); err != nil {
			httpx.WriteError(c, err)
			return
		}
		sub := newSubscriber()
		if err := h.add(p.UserID, sub); err != nil {
			httpx.Fail(c, http.StatusTooManyRequests, CodeTooManyConnections, "连接数过多，请关闭其他设备上的应用后重试")
			return
		}
		defer h.remove(p.UserID, sub)
		// 先登记连接再读序号：两者之间提交的写入会作为通知送达，不会漏掉
		seq, err := o.Cursor(c.Request.Context(), p.UserID)
		if err != nil {
			httpx.WriteError(c, err)
			return
		}
		// 升级后的连接会沿用 HTTP 服务器的读写超时，长连接必须清除
		rc := http.NewResponseController(c.Writer)
		_ = rc.SetReadDeadline(time.Time{})
		_ = rc.SetWriteDeadline(time.Time{})
		conn, err := websocket.Accept(c.Writer, c.Request, nil)
		if err != nil {
			return // Accept 已写入错误响应
		}
		defer func() { _ = conn.CloseNow() }()
		ctx := conn.CloseRead(context.WithoutCancel(c.Request.Context()))
		h.serve(ctx, conn, p, seq, sub, o)
	}
}

func (h *Hub) serve(ctx context.Context, conn *websocket.Conn, p auth.Principal, seq int64, sub *subscriber, o Options) {
	if !h.send(ctx, conn, Event{Type: EventHello, Seq: seq}) {
		return
	}
	ping := time.NewTicker(o.PingInterval)
	defer ping.Stop()
	check := time.NewTicker(o.CheckInterval)
	defer check.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-h.done:
			_ = conn.Close(websocket.StatusGoingAway, "server shutting down")
			return
		case <-sub.signal:
			if m, ok := sub.take(); ok {
				ev := Event{Type: EventChanged, Seq: m.Seq}
				if m.Origin != uuid.Nil {
					ev.Origin = &m.Origin
				}
				if !h.send(ctx, conn, ev) {
					return
				}
			}
		case <-ping.C:
			pctx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := conn.Ping(pctx)
			cancel()
			if err != nil {
				return
			}
		case <-check.C:
			cctx, cancel := context.WithTimeout(ctx, checkTimeout)
			err := o.Check.CheckSession(cctx, p)
			cancel()
			if revoked(err) {
				_ = conn.Close(CloseSessionRevoked, "session revoked")
				return
			}
		}
	}
}

func (h *Hub) send(ctx context.Context, conn *websocket.Conn, ev Event) bool {
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	return wsjson.Write(wctx, conn, ev) == nil
}

func limitHandshake(ctx context.Context, l *ratelimit.Limiter, p auth.Principal) error {
	if l == nil {
		return nil
	}
	r, err := l.Hit(ctx, "ws:dev:"+p.DeviceID.String(), handshakesPerHour, time.Hour)
	if err != nil {
		return err
	}
	if !r.Allowed {
		return httpx.TooManyRequests(httpx.CodeRateLimited, "连接过于频繁，请稍后再试", r.RetryAfter)
	}
	return nil
}

// revoked 只在会话确实失效（401）时断开；数据库暂时不可用时保持连接。
func revoked(err error) bool {
	var herr *httpx.Error
	return errors.As(err, &herr) && herr.Status == http.StatusUnauthorized
}

// Shutdown 通知本实例上的所有连接以 1001 关闭（服务优雅退出时调用）。
func (h *Hub) Shutdown() {
	h.closeOnce.Do(func() { close(h.done) })
}
