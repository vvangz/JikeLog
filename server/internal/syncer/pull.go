package syncer

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/vault"
)

// 单页记录数。
const (
	// DefaultPullLimit 为未指定 limit 时的单页记录数。
	DefaultPullLimit = 200
	// MaxPullLimit 为单页记录数上限。
	MaxPullLimit = 500
	// maxPullBytes 为单页记录字段的近似总字节数（存储格式），超过后提前结束本页。
	maxPullBytes = 2 << 20
)

// 错误码。
const (
	CodeRecordNotFound   = "RECORD_NOT_FOUND"
	CodeRevisionNotFound = "REVISION_NOT_FOUND"
	CodeAckAhead         = "ACK_AHEAD_OF_SERVER"
)

var (
	errRecordNotFound   = httpx.NewError(http.StatusNotFound, CodeRecordNotFound, "记录不存在")
	errRevisionNotFound = httpx.NewError(http.StatusNotFound, CodeRevisionNotFound, "修订不存在")
	errAckAhead         = httpx.NewError(http.StatusUnprocessableEntity, CodeAckAhead, "确认的序号超过了服务端已分配的序号")
)

// Page 为一页拉取结果。
type Page struct {
	Records   []Record
	NextSince int64
	HasMore   bool
}

// Pull 返回 server_seq 大于 since 的记录（含墓碑），按序号升序。
func (s *Service) Pull(ctx context.Context, p auth.Principal, tr Transport, since int64, limit int) (Page, error) {
	if since < 0 {
		return Page{}, httpx.Validation(map[string]string{"since": "不能为负数"})
	}
	if limit <= 0 || limit > MaxPullLimit {
		limit = DefaultPullLimit
	}
	q := s.d.Tx.Queries()
	rows, err := q.ListRecordsSince(ctx, dbgen.ListRecordsSinceParams{UserID: p.UserID, Since: since, MaxRows: int32(limit + 1)})
	if err != nil {
		return Page{}, fmt.Errorf("拉取记录失败: %w", err)
	}
	page := Page{NextSince: since}
	if len(rows) > limit {
		rows, page.HasMore = rows[:limit], true
	}
	var key []byte
	bytes := 0
	for i, row := range rows {
		if i > 0 && bytes+len(row.Fields) > maxPullBytes {
			page.HasMore = true
			break
		}
		bytes += len(row.Fields)
		e, ok := Registry[row.Entity]
		if !ok {
			page.NextSince = row.ServerSeq // 已下线的实体类型：跳过但推进游标
			continue
		}
		if key == nil && !row.Deleted && hasSensitive(e) {
			if key, err = s.d.Keys.DataKey(ctx, q, p.UserID, false); err != nil && !errors.Is(err, vault.ErrNoKey) {
				return Page{}, err
			}
		}
		rec, err := s.recordFromRow(e, row, key, tr)
		if err != nil {
			return Page{}, err
		}
		page.Records = append(page.Records, *rec)
		page.NextSince = row.ServerSeq
	}
	return page, nil
}

func (s *Service) recordFromRow(e Entity, row dbgen.Record, key []byte, tr Transport) (*Record, error) {
	if row.Deleted {
		return &Record{Entity: e.Name, ID: row.ID, Version: row.Version, ServerSeq: row.ServerSeq, Deleted: true,
			Fields: map[string]any{}, Clocks: map[string]Clock{}, UpdatedAt: row.UpdatedAt}, nil
	}
	st, err := rowState(e, row, key)
	if err != nil {
		return nil, err
	}
	return outRecord(e, row.ID, row.Version, row.ServerSeq, st, row.UpdatedAt, tr)
}

// Ack 记录当前设备已处理到的同步序号。
func (s *Service) Ack(ctx context.Context, p auth.Principal, seq int64) error {
	if seq < 0 {
		return httpx.Validation(map[string]string{"seq": "不能为负数"})
	}
	q := s.d.Tx.Queries()
	cursor, err := q.GetSyncCursor(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("读取同步游标失败: %w", err)
	}
	if seq > cursor {
		return errAckAhead
	}
	if _, err := q.AckDevice(ctx, dbgen.AckDeviceParams{Seq: seq, ID: p.DeviceID, UserID: p.UserID}); err != nil {
		return fmt.Errorf("记录同步确认失败: %w", err)
	}
	return nil
}

// Cursor 返回账号当前的同步序号。
func (s *Service) Cursor(ctx context.Context, userID uuid.UUID) (int64, error) {
	seq, err := s.d.Tx.Queries().GetSyncCursor(ctx, userID)
	if err != nil {
		return 0, fmt.Errorf("读取同步游标失败: %w", err)
	}
	return seq, nil
}

// RevisionInfo 为修订列表项。
type RevisionInfo struct {
	ID          uuid.UUID
	Version     int64
	Reason      string
	CreatedAt   time.Time
	DeviceModel string
}

// Revisions 返回记录的修订列表（不含内容），新的在前。
func (s *Service) Revisions(ctx context.Context, p auth.Principal, recordID uuid.UUID) ([]RevisionInfo, error) {
	q := s.d.Tx.Queries()
	if _, err := q.GetRecord(ctx, dbgen.GetRecordParams{ID: recordID, UserID: p.UserID}); err != nil {
		if db.IsNotFound(err) {
			return nil, errRecordNotFound
		}
		return nil, fmt.Errorf("查询记录失败: %w", err)
	}
	rows, err := q.ListRevisions(ctx, dbgen.ListRevisionsParams{RecordID: recordID, UserID: p.UserID})
	if err != nil {
		return nil, fmt.Errorf("查询修订失败: %w", err)
	}
	out := make([]RevisionInfo, len(rows))
	for i, r := range rows {
		out[i] = RevisionInfo{ID: r.ID, Version: r.Version, Reason: r.Reason, CreatedAt: r.CreatedAt, DeviceModel: r.DeviceModel}
	}
	return out, nil
}

// Revision 为修订详情；Fields 中的敏感字段已用传输会话加密。
type Revision struct {
	RevisionInfo
	RecordID uuid.UUID
	Entity   string
	Fields   map[string]any
}

// Revision 返回一份修订的完整内容。
func (s *Service) Revision(ctx context.Context, p auth.Principal, tr Transport, id uuid.UUID) (Revision, error) {
	q := s.d.Tx.Queries()
	row, err := q.GetRevision(ctx, dbgen.GetRevisionParams{ID: id, UserID: p.UserID})
	if db.IsNotFound(err) {
		return Revision{}, errRevisionNotFound
	}
	if err != nil {
		return Revision{}, fmt.Errorf("查询修订失败: %w", err)
	}
	e, ok := Registry[row.Entity]
	if !ok {
		return Revision{}, errRevisionNotFound
	}
	var key []byte
	if hasSensitive(e) {
		if key, err = s.d.Keys.DataKey(ctx, q, p.UserID, false); err != nil && !errors.Is(err, vault.ErrNoKey) {
			return Revision{}, err
		}
	}
	plain, err := openFields(e, p.UserID, row.RecordID, row.Fields, key)
	if err != nil {
		return Revision{}, err
	}
	fields, err := transportFields(e, row.RecordID, plain, tr)
	if err != nil {
		return Revision{}, err
	}
	return Revision{
		RevisionInfo: RevisionInfo{ID: row.ID, Version: row.Version, Reason: row.Reason, CreatedAt: row.CreatedAt},
		RecordID:     row.RecordID, Entity: row.Entity, Fields: fields,
	}, nil
}
