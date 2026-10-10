package syncer

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
)

// errIDTaken 表示插入时该 ID 已被其他账号并发占用。
var errIDTaken = errors.New("记录 ID 已被占用")

// persist 写入合并结果：分配序号、加密落库、保存修订，并生成该条变更的结果。
func (w *writer) persist(ctx context.Context, e Entity, id uuid.UUID, row dbgen.Record, exists bool, out Outcome) (Result, error) {
	res := Result{ID: id, Status: out.Status}
	if exists {
		res.Version, res.ServerSeq = row.Version, row.ServerSeq
	}
	if out.Changed {
		if err := w.write(ctx, e, id, exists, out); err != nil {
			return res, err
		}
		res.ServerSeq = w.seq
		res.Version = 1
		if exists {
			res.Version = row.Version + 1
		}
		if err := w.saveRevisions(ctx, e, id, row, exists, out, res.Version); err != nil {
			return res, err
		}
	}
	if out.Status == StatusMerged || out.Status == StatusConflict {
		rec, err := outRecord(e, id, res.Version, res.ServerSeq, out.Next, w.s.d.Now(), w.tr)
		if err != nil {
			return res, err
		}
		res.Record = rec
	}
	return res, nil
}

func (w *writer) write(ctx context.Context, e Entity, id uuid.UUID, exists bool, out Outcome) error {
	key, err := w.keyFor(ctx, e)
	if err != nil {
		return err
	}
	fields, err := sealFields(e, w.p.UserID, id, out.Next.Fields, key)
	if err != nil {
		return err
	}
	clocks, err := marshalClocks(out.Next.Clocks)
	if err != nil {
		return fmt.Errorf("编码字段时钟失败: %w", err)
	}
	absorbed, err := marshalAbsorbed(out.Next.Absorbed)
	if err != nil {
		return fmt.Errorf("编码已吸收时钟失败: %w", err)
	}
	w.seq++
	device := w.p.DeviceID
	if !exists {
		var n int64
		n, err = w.q.InsertRecord(ctx, dbgen.InsertRecordParams{
			ID: id, UserID: w.p.UserID, Entity: e.Name, ServerSeq: w.seq,
			Fields: fields, Clocks: clocks, Absorbed: absorbed, Deleted: out.Next.Deleted, DeviceID: &device,
		})
		if err == nil && n == 0 {
			w.seq-- // 未写入，序号不前进
			return errIDTaken
		}
	} else {
		err = w.q.UpdateRecord(ctx, dbgen.UpdateRecordParams{
			ID: id, ServerSeq: w.seq, Fields: fields, Clocks: clocks, Absorbed: absorbed,
			Deleted: out.Next.Deleted, DeviceID: &device,
		})
	}
	if err != nil {
		return fmt.Errorf("写入记录失败: %w", err)
	}
	if e.Name == EntityMemo {
		if err := w.scheduleMemo(ctx, id, out.Next); err != nil {
			return err
		}
	}
	if out.DeletedNow && e.Name == EntityAttachment {
		if err := w.q.MarkAttachmentDeleted(ctx, dbgen.MarkAttachmentDeletedParams{ID: id, UserID: w.p.UserID}); err != nil {
			return fmt.Errorf("标记附件删除失败: %w", err)
		}
	}
	return nil
}

// saveRevisions 按 ADR-005 保存修订：删除前的状态、冲突败方，以及间隔足够久或换了设备时的编辑前状态。
func (w *writer) saveRevisions(ctx context.Context, e Entity, id uuid.UUID, row dbgen.Record, exists bool, out Outcome, version int64) error {
	saved := false
	save := func(reason string, fields []byte, ver int64, device *uuid.UUID) error {
		saved = true
		return w.q.InsertRevision(ctx, dbgen.InsertRevisionParams{
			ID: uuid.Must(uuid.NewV7()), RecordID: id, UserID: w.p.UserID, Entity: e.Name,
			Version: ver, Reason: reason, Fields: fields, DeviceID: device,
		})
	}
	switch {
	case out.DeletedNow:
		if err := save(ReasonDelete, row.Fields, row.Version, row.DeviceID); err != nil {
			return fmt.Errorf("保存删除前修订失败: %w", err)
		}
	case exists && !row.Deleted && out.Edited && w.editRevisionDue(row):
		// 原样保存旧密文：AAD 只绑定账号、记录和字段，修订中可用同一把密钥解开
		if err := save(ReasonEdit, row.Fields, row.Version, row.DeviceID); err != nil {
			return fmt.Errorf("保存编辑前修订失败: %w", err)
		}
	}
	for _, lost := range out.Losers {
		key, err := w.keyFor(ctx, e)
		if err != nil {
			return err
		}
		fields, err := sealFields(e, w.p.UserID, id, lost, key)
		if err != nil {
			return err
		}
		device := w.p.DeviceID
		if err := save(ReasonConflict, fields, version, &device); err != nil {
			return fmt.Errorf("保存冲突修订失败: %w", err)
		}
	}
	if !saved {
		return nil
	}
	if err := w.q.PruneRevisions(ctx, dbgen.PruneRevisionsParams{RecordID: id, Keep: maxRevisionsPerRecord}); err != nil {
		return fmt.Errorf("清理旧修订失败: %w", err)
	}
	return nil
}

// editRevisionDue 报告是否需要为编辑前的状态保存一份修订：换了设备，或距上次写入超过 editRevisionGap。
func (w *writer) editRevisionDue(row dbgen.Record) bool {
	if row.DeviceID == nil || *row.DeviceID != w.p.DeviceID {
		return true
	}
	return w.s.d.Now().Sub(row.UpdatedAt) >= editRevisionGap
}
