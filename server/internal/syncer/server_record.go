package syncer

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
)

// serverNode 为服务端写入时使用的 HLC 节点。
const serverNode = "0000000000000000"

// ServerClock 返回服务端写入使用的时钟。
func ServerClock(now time.Time) Clock {
	return Clock(fmt.Sprintf("%013d-0000-%s", now.UnixMilli(), serverNode))
}

// WriteServerRecord 在调用方的事务内创建一条只能由服务端创建的记录（如附件），返回分配的同步序号。
// 调用方提交事务后应调用 Notify 通知其他设备。
func (s *Service) WriteServerRecord(ctx context.Context, q *dbgen.Queries, p auth.Principal, entity string, id uuid.UUID, fields map[string]Value) (int64, error) {
	e, ok := Registry[entity]
	if !ok || !e.ServerCreated {
		return 0, fmt.Errorf("实体 %q 不能由服务端直接创建", entity)
	}
	clock := ServerClock(s.d.Now())
	clocks := make(map[string]Clock, len(fields))
	for f, v := range fields {
		spec, ok := e.Fields[f]
		if !ok {
			return 0, fmt.Errorf("实体 %s 没有字段 %s", entity, f)
		}
		if _, err := spec.CheckValue(v); err != nil {
			return 0, fmt.Errorf("字段 %s 不合法: %w", f, err)
		}
		clocks[f] = clock
	}
	seq, err := q.LockSyncCursor(ctx, p.UserID)
	if err != nil {
		return 0, fmt.Errorf("锁定同步游标失败: %w", err)
	}
	w := &writer{s: s, q: q, p: p, seq: seq}
	out := Outcome{Status: StatusApplied, Changed: true, Edited: true, Next: State{Fields: fields, Clocks: clocks}}
	if err := w.write(ctx, e, id, false, out); err != nil {
		return 0, err
	}
	if err := q.SetSyncCursor(ctx, dbgen.SetSyncCursorParams{UserID: p.UserID, LastSeq: w.seq}); err != nil {
		return 0, fmt.Errorf("更新同步游标失败: %w", err)
	}
	return w.seq, nil
}

// Notify 通知账号的其他在线设备有新数据。
func (s *Service) Notify(ctx context.Context, p auth.Principal, seq int64) {
	if s.d.Notifier != nil {
		s.d.Notifier.Publish(ctx, p.UserID, seq, p.DeviceID)
	}
}
