// Package realtime 通过 WebSocket 通知在线设备"有新数据"（ADR-005 第 5 节）。
//
// 写入事务提交后向 Redis 频道 sync:user:<id> 发布 {seq, origin}；每个 API 实例只订阅一次
// sync:user:*，再转发给本实例上该账号的连接。WebSocket 只用于提醒，不承载数据：
// 丢一条通知不会丢数据，客户端回到前台、网络恢复时都会再拉取。
package realtime

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/platform/cache"
)

const channelPrefix = cache.KeyPrefix + "sync:user:"

// Event 为下发给客户端的消息。
type Event struct {
	Type string `json:"type"`
	Seq  int64  `json:"seq"`
	// Origin 为产生这次写入的设备；客户端忽略自己产生的通知。
	Origin *uuid.UUID `json:"origin,omitempty"`
}

// 消息类型。
const (
	EventHello   = "hello"
	EventChanged = "changed"
)

type message struct {
	Seq    int64     `json:"seq"`
	Origin uuid.UUID `json:"origin"`
}

// Hub 维护本实例上的连接，并与其他实例经 Redis 交换通知。
type Hub struct {
	rdb    *redis.Client
	logger *slog.Logger

	mu    sync.RWMutex
	conns map[uuid.UUID]map[*subscriber]struct{}

	done      chan struct{}
	closeOnce sync.Once
}

// NewHub 创建 Hub；调用 Run 后开始接收其他实例的通知。
func NewHub(rdb *redis.Client, logger *slog.Logger) *Hub {
	return &Hub{rdb: rdb, logger: logger, conns: map[uuid.UUID]map[*subscriber]struct{}{}, done: make(chan struct{})}
}

// Publish 实现 syncer.Notifier：发布失败只记录日志（客户端会在其他时机拉取）。
func (h *Hub) Publish(ctx context.Context, userID uuid.UUID, seq int64, origin uuid.UUID) {
	raw, _ := json.Marshal(message{Seq: seq, Origin: origin})
	if err := h.rdb.Publish(context.WithoutCancel(ctx), channelPrefix+userID.String(), raw).Err(); err != nil {
		h.logger.WarnContext(ctx, "publish sync notification failed", "error", err)
	}
}

// Run 订阅所有账号的通知并分发给本实例的连接，直到 ctx 取消。断线后自动重连。
func (h *Hub) Run(ctx context.Context) {
	for ctx.Err() == nil {
		h.subscribe(ctx)
		select {
		case <-ctx.Done():
		case <-time.After(time.Second):
		}
	}
}

func (h *Hub) subscribe(ctx context.Context) {
	ps := h.rdb.PSubscribe(ctx, channelPrefix+"*")
	defer func() { _ = ps.Close() }()
	if _, err := ps.Receive(ctx); err != nil {
		if ctx.Err() == nil {
			h.logger.WarnContext(ctx, "subscribe sync notifications failed", "error", err)
		}
		return
	}
	ch := ps.Channel()
	for {
		select {
		case <-ctx.Done():
			return
		case m, ok := <-ch:
			if !ok {
				return
			}
			h.dispatch(m.Channel, m.Payload)
		}
	}
}

func (h *Hub) dispatch(channel, payload string) {
	userID, err := uuid.Parse(strings.TrimPrefix(channel, channelPrefix))
	if err != nil {
		return
	}
	var m message
	if err := json.Unmarshal([]byte(payload), &m); err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for sub := range h.conns[userID] {
		sub.notify(m)
	}
}

// ErrTooManyConnections 表示该账号在本实例上的连接数已达上限。
var ErrTooManyConnections = errors.New("连接数过多")

// maxConnsPerUser 为单个账号在一个实例上的连接上限。
const maxConnsPerUser = 10

func (h *Hub) add(userID uuid.UUID, sub *subscriber) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	set := h.conns[userID]
	if len(set) >= maxConnsPerUser {
		return ErrTooManyConnections
	}
	if set == nil {
		set = map[*subscriber]struct{}{}
		h.conns[userID] = set
	}
	set[sub] = struct{}{}
	return nil
}

func (h *Hub) remove(userID uuid.UUID, sub *subscriber) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.conns[userID], sub)
	if len(h.conns[userID]) == 0 {
		delete(h.conns, userID)
	}
}

// subscriber 为一个连接的待发送状态：只保留最新的序号，连续的通知自动合并。
type subscriber struct {
	mu      sync.Mutex
	pending *message
	signal  chan struct{}
}

func newSubscriber() *subscriber { return &subscriber{signal: make(chan struct{}, 1)} }

func (s *subscriber) notify(m message) {
	s.mu.Lock()
	if s.pending == nil || m.Seq >= s.pending.Seq {
		s.pending = &m
	}
	s.mu.Unlock()
	select {
	case s.signal <- struct{}{}:
	default:
	}
}

func (s *subscriber) take() (message, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.pending == nil {
		return message{}, false
	}
	m := *s.pending
	s.pending = nil
	return m, true
}
