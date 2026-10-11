package syncer

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/vault"
)

// snapshotPage 为逐条读取记录时每次查询的行数。
const snapshotPage = 200

// Snapshot 为一条有效记录的明文内容（数据导出用）。
type Snapshot struct {
	Entity    string
	ID        uuid.UUID
	Fields    map[string]Value
	UpdatedAt time.Time
}

// EachRecord 按同步顺序读取账号中指定实体的全部有效记录（不含墓碑），解开落库加密后逐条交给 fn。
// 无法解码的记录写日志后跳过，不影响其余记录；fn 返回错误时停止。
func (s *Service) EachRecord(ctx context.Context, userID uuid.UUID, entities []string, fn func(Snapshot) error) error {
	q := s.d.Tx.Queries()
	key, err := s.d.Keys.DataKey(ctx, q, userID, false)
	if err != nil && !errors.Is(err, vault.ErrNoKey) {
		return err
	}
	var after int64
	for {
		rows, err := q.ListUserRecords(ctx, dbgen.ListUserRecordsParams{
			UserID: userID, Entities: entities, After: after, MaxRows: snapshotPage,
		})
		if err != nil {
			return fmt.Errorf("读取记录失败: %w", err)
		}
		for _, row := range rows {
			after = row.ServerSeq
			e, ok := Registry[row.Entity]
			if !ok {
				continue
			}
			fields, err := openFields(e, row.UserID, row.ID, row.Fields, key)
			if err != nil {
				s.d.Logger.ErrorContext(ctx, "skip corrupt record in export", "record_id", row.ID, "error", err)
				continue
			}
			if err := fn(Snapshot{Entity: row.Entity, ID: row.ID, Fields: fields, UpdatedAt: row.UpdatedAt}); err != nil {
				return err
			}
		}
		if len(rows) < snapshotPage {
			return nil
		}
	}
}
