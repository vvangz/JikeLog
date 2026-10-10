// Package syncer 实现多设备同步（ADR-005）：推送合并、增量拉取、确认、修订历史与实时通知。
package syncer

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/ratelimit"
	"github.com/vvangz/JikeLog/server/internal/textpatch"
	"github.com/vvangz/JikeLog/server/internal/vault"
)

const (
	// MaxPushChanges 为单次推送的变更数上限。
	MaxPushChanges = 100
	// editRevisionGap 内同一设备的连续保存只保留一份修订（自动保存会频繁写入）。
	editRevisionGap = 10 * time.Minute
	// maxRevisionsPerRecord 为每条记录保留的修订数。
	maxRevisionsPerRecord = 50
	// pushPerMinute 为每个账号每分钟的推送次数上限（正常客户端有 2 秒防抖）。
	pushPerMinute = 120
	// pushPatchBudget 为一次推送中应用文本补丁可扫描的总字节数，防止构造的补丁长时间占用账号锁。
	pushPatchBudget = 64 << 20
)

// CodeRecordCorrupt 表示服务端存储的记录无法解析（已记录日志），该条变更被拒绝。
const CodeRecordCorrupt = "RECORD_CORRUPT"

// 修订原因。
const (
	ReasonEdit     = "edit"
	ReasonConflict = "conflict"
	ReasonDelete   = "delete"
)

// Notifier 在写入提交后通知该账号的其他在线设备。
type Notifier interface {
	Publish(ctx context.Context, userID uuid.UUID, seq int64, origin uuid.UUID)
}

// Deps 为 Service 的依赖。
type Deps struct {
	Tx       db.TxRunner
	Keys     *vault.Keyring
	Notifier Notifier
	// Limiter 为空时不限制推送频率（测试）。
	Limiter *ratelimit.Limiter
	Logger  *slog.Logger
	// Now 为空时使用 time.Now。
	Now func() time.Time
}

// Service 为同步业务逻辑。
type Service struct {
	d Deps
}

// NewService 创建 Service。
func NewService(d Deps) *Service {
	if d.Now == nil {
		d.Now = time.Now
	}
	return &Service{d: d}
}

// Result 为一条变更的处理结果。
type Result struct {
	ID        uuid.UUID
	Status    Status
	Version   int64
	ServerSeq int64
	// Record 在合并或冲突时返回，客户端用它覆盖本地。
	Record *Record
	Error  *ChangeError
}

type decoded struct {
	idx    int
	id     uuid.UUID
	entity Entity
	change Change
}

// Push 处理一批变更，返回逐条结果与该账号当前的同步序号。
func (s *Service) Push(ctx context.Context, p auth.Principal, tr Transport, in []IncomingChange) ([]Result, int64, error) {
	if len(in) > MaxPushChanges {
		return nil, 0, httpx.Validation(map[string]string{"changes": fmt.Sprintf("单次最多推送 %d 条变更", MaxPushChanges)})
	}
	if err := s.limit(ctx, p); err != nil {
		return nil, 0, err
	}
	results := make([]Result, len(in))
	var valid []decoded
	now := s.d.Now()
	budget := textpatch.NewBudget(pushPatchBudget)
	for i, c := range in {
		results[i] = Result{ID: c.ID}
		e, ch, cerr, err := decodeChange(c, tr, now)
		if err != nil {
			return nil, 0, err
		}
		if cerr != nil {
			results[i].Status, results[i].Error = StatusRejected, cerr
			continue
		}
		ch.Budget = budget
		valid = append(valid, decoded{idx: i, id: c.ID, entity: e, change: ch})
	}
	var cursor int64
	advanced := false
	err := s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		w := &writer{s: s, q: q, p: p, tr: tr}
		seq, err := q.LockSyncCursor(ctx, p.UserID)
		if err != nil {
			return fmt.Errorf("锁定同步游标失败: %w", err)
		}
		w.seq = seq
		for _, d := range valid {
			if results[d.idx], err = w.apply(ctx, d); err != nil {
				return err
			}
		}
		cursor = w.seq
		advanced = w.seq != seq
		if advanced {
			return q.SetSyncCursor(ctx, dbgen.SetSyncCursorParams{UserID: p.UserID, LastSeq: w.seq})
		}
		return nil
	})
	if err != nil {
		return nil, 0, err
	}
	if advanced && s.d.Notifier != nil {
		s.d.Notifier.Publish(ctx, p.UserID, cursor, p.DeviceID)
	}
	return results, cursor, nil
}

// writer 在一个推送事务内依次应用变更。
type writer struct {
	s   *Service
	q   *dbgen.Queries
	p   auth.Principal
	tr  Transport
	seq int64
	key []byte
}

func (w *writer) dataKey(ctx context.Context) ([]byte, error) {
	if w.key == nil {
		key, err := w.s.d.Keys.DataKey(ctx, w.q, w.p.UserID, true)
		if err != nil {
			return nil, err
		}
		w.key = key
	}
	return w.key, nil
}

func (w *writer) apply(ctx context.Context, d decoded) (Result, error) {
	id := d.id
	res := Result{ID: id}
	row, err := w.q.GetRecordForUpdate(ctx, dbgen.GetRecordForUpdateParams{ID: id, UserID: w.p.UserID})
	exists := err == nil
	if err != nil && !db.IsNotFound(err) {
		return res, fmt.Errorf("读取记录失败: %w", err)
	}
	if !exists {
		taken, err := w.q.RecordIDTaken(ctx, id)
		if err != nil {
			return res, fmt.Errorf("检查记录 ID 失败: %w", err)
		}
		if taken {
			return idConflict(id), nil // 不透露该 ID 属于其他账号
		}
	}
	if exists && row.Entity != d.entity.Name {
		return idConflict(id), nil
	}
	var cur *State
	if exists {
		key, err := w.keyFor(ctx, d.entity)
		if err != nil {
			return res, err
		}
		st, err := rowState(d.entity, row, key)
		if err != nil {
			// 损坏的记录只拒绝这一条，不能让整批推送失败、客户端无限重试
			w.s.d.Logger.ErrorContext(ctx, "stored record corrupt", "record_id", id, "error", err)
			res.Status, res.Error = StatusRejected, &ChangeError{Code: CodeRecordCorrupt, Message: "记录数据异常，请联系我们处理"}
			return res, nil
		}
		cur = &st
	}
	out, err := Merge(d.entity, cur, d.change)
	if err != nil {
		res.Status, res.Error = StatusRejected, changeErrorFrom(err)
		return res, nil
	}
	res, err = w.persist(ctx, d.entity, id, row, exists, out)
	if errors.Is(err, errIDTaken) {
		return idConflict(id), nil
	}
	return res, err
}

func idConflict(id uuid.UUID) Result {
	return Result{ID: id, Status: StatusRejected, Error: &ChangeError{Code: CodeIDConflict, Message: "记录 ID 冲突，请重新创建"}}
}

func (s *Service) limit(ctx context.Context, p auth.Principal) error {
	if s.d.Limiter == nil {
		return nil
	}
	r, err := s.d.Limiter.Hit(ctx, "sync:push:"+p.UserID.String(), pushPerMinute, time.Minute)
	if err != nil {
		return err
	}
	if !r.Allowed {
		return httpx.TooManyRequests(httpx.CodeRateLimited, "同步过于频繁，请稍后再试", r.RetryAfter)
	}
	return nil
}

// keyFor 在实体含敏感字段时返回账号数据密钥。
func (w *writer) keyFor(ctx context.Context, e Entity) ([]byte, error) {
	if !hasSensitive(e) {
		return nil, nil
	}
	return w.dataKey(ctx)
}

func hasSensitive(e Entity) bool {
	for _, spec := range e.Fields {
		if spec.Sensitive {
			return true
		}
	}
	return false
}

func changeErrorFrom(err error) *ChangeError {
	var fe FieldErrors
	if errors.As(err, &fe) {
		return invalid(fe)
	}
	return &ChangeError{Code: CodeInvalidChange, Message: err.Error()}
}
