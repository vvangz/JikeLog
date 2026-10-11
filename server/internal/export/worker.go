package export

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
	_ "time/tzdata" // 运行镜像不一定带时区数据库，按设备时区显示导出中的时间

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/attachment"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/pusher"
	"github.com/vvangz/JikeLog/server/internal/platform/storage"
)

const (
	statusPending = "pending"
	statusRunning = "running"
	statusDone    = "done"

	// PollInterval 为检查待生成导出的间隔。
	PollInterval = 5 * time.Second
	// cleanupInterval 为清理过期导出文件的间隔。
	cleanupInterval = 10 * time.Minute
	// lease 为领取后独占的时长；生成时间超过 lease-leaseMargin 时放弃本次尝试，由重新领取的实例重试。
	lease       = 30 * time.Minute
	leaseMargin = 2 * time.Minute
	// maxAttempts 为一次导出最多尝试生成的次数。
	maxAttempts = 3
	// retryDelay 为失败后到下次重试的间隔。
	retryDelay = time.Minute
	// pruneAfter 之后删除已结束且没有文件的导出记录。
	pruneAfter = 30 * 24 * time.Hour
	// expireBatch 为每次清理的过期导出数。
	expireBatch = 50
	// defaultTimeZone 用于没有上报时区的设备。
	defaultTimeZone = "Asia/Shanghai"
	// failedMessage 为给用户看的失败说明（详细原因只写日志）。
	failedMessage = "生成导出文件失败，请稍后重试"
)

// Run 定期生成待处理的导出并清理过期文件，直到 ctx 取消。
func (s *Service) Run(ctx context.Context) {
	s.sweepTemp()
	poll := time.NewTicker(PollInterval)
	defer poll.Stop()
	cleanup := time.NewTicker(cleanupInterval)
	defer cleanup.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-poll.C:
			if _, err := s.Tick(ctx); err != nil && ctx.Err() == nil {
				s.d.Logger.WarnContext(ctx, "export tick failed", "error", err)
			}
		case <-cleanup.C:
			if _, err := s.Cleanup(ctx); err != nil && ctx.Err() == nil {
				s.d.Logger.WarnContext(ctx, "export cleanup failed", "error", err)
			}
		}
	}
}

// Tick 依次生成当前全部可以处理的导出，返回处理的个数。只有数据库错误会返回。
func (s *Service) Tick(ctx context.Context) (int, error) {
	n := 0
	for {
		job, ok, err := s.claim(ctx)
		if err != nil || !ok {
			return n, err
		}
		if err := s.process(ctx, job); err != nil {
			return n, err
		}
		n++
	}
}

func (s *Service) claim(ctx context.Context) (dbgen.Export, bool, error) {
	now := s.d.Now()
	var job dbgen.Export
	err := s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		var err error
		job, err = q.ClaimExport(ctx, dbgen.ClaimExportParams{LeaseUntil: now.Add(lease), Now: now})
		return err
	})
	if db.IsNotFound(err) {
		return dbgen.Export{}, false, nil
	}
	if err != nil {
		return dbgen.Export{}, false, fmt.Errorf("领取导出失败: %w", err)
	}
	return job, true, nil
}

// process 生成一次导出并记录结果。生成失败按重试策略处理，不作为错误返回。
func (s *Service) process(ctx context.Context, job dbgen.Export) error {
	log := s.d.Logger.With("export_id", job.ID, "user_id", job.UserID, "attempt", job.Attempts)
	if job.Attempts > maxAttempts {
		// 之前的尝试中途崩溃（没有记录结果），不再继续
		log.WarnContext(ctx, "export dropped: too many attempts")
		return s.fail(ctx, job)
	}
	genCtx, cancel := context.WithTimeout(ctx, lease-leaseMargin)
	defer cancel()
	key, size, err := s.safeGenerate(genCtx, job, s.location(ctx, job))
	if err != nil {
		if ctx.Err() != nil {
			s.release(job) // 服务停止：交还领取，重启后立即重新生成
			return ctx.Err()
		}
		log.ErrorContext(ctx, "export failed", "error", err)
		if job.Attempts < maxAttempts {
			_, err := s.d.Tx.Queries().RetryExport(ctx, dbgen.RetryExportParams{
				ID: job.ID, Attempts: job.Attempts, RetryAt: ptr(s.d.Now().Add(retryDelay)), Error: ptr(failedMessage),
			})
			return wrapDB(err)
		}
		return s.fail(ctx, job)
	}
	now := s.d.Now()
	rows, err := s.d.Tx.Queries().CompleteExport(ctx, dbgen.CompleteExportParams{
		ID: job.ID, Attempts: job.Attempts, ObjectKey: &key, Size: &size, FinishedAt: &now, ExpiresAt: ptr(now.Add(Retention)),
	})
	if err != nil {
		s.discard(ctx, job) // 没有记录指向这个文件，过期清理找不到它
		return wrapDB(err)
	}
	if rows == 0 {
		log.WarnContext(ctx, "export result discarded: lease lost or export removed")
		s.discard(ctx, job)
		return nil
	}
	log.InfoContext(ctx, "export done", "size", size)
	s.notify(ctx, job, "导出已完成", "数据导出文件已生成，24 小时内可以在 App 中下载。")
	return nil
}

func (s *Service) fail(ctx context.Context, job dbgen.Export) error {
	// 之前的尝试可能已经上传了文件（随后写结果失败），一并删除
	s.discard(ctx, job)
	rows, err := s.d.Tx.Queries().FailExport(ctx, dbgen.FailExportParams{
		ID: job.ID, Attempts: job.Attempts, Error: ptr(failedMessage), FinishedAt: ptr(s.d.Now()),
	})
	if err != nil {
		return wrapDB(err)
	}
	if rows > 0 {
		s.notify(ctx, job, "导出失败", "数据导出没有完成，请稍后在 App 中重试。")
	}
	return nil
}

// discard 删除没有记录指向的导出文件（明文不能留在对象存储中）。
// 另一个实例已经完成同一导出时保留（同一对象键）。
func (s *Service) discard(ctx context.Context, job dbgen.Export) {
	status, err := s.d.Tx.Queries().GetExportStatus(ctx, job.ID)
	if err == nil && status == statusDone {
		return
	}
	if err := s.d.Store.Delete(ctx, ObjectKey(job.UserID, job.ID)); err != nil {
		s.d.Logger.ErrorContext(ctx, "delete orphan export failed", "export_id", job.ID, "error", err)
	}
}

// release 交还未完成的领取（服务停止时），不计入尝试次数。
func (s *Service) release(job dbgen.Export) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := s.d.Tx.Queries().ReleaseExport(ctx, dbgen.ReleaseExportParams{ID: job.ID, Attempts: job.Attempts}); err != nil {
		s.d.Logger.WarnContext(ctx, "release export failed", "export_id", job.ID, "error", err)
	}
}

// safeGenerate 生成导出文件；生成过程中的 panic（如异常数据）按失败处理，不让整个服务退出。
func (s *Service) safeGenerate(ctx context.Context, job dbgen.Export, loc *time.Location) (key string, size int64, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("生成导出文件时 panic: %v", r)
		}
	}()
	return s.generate(ctx, job, loc)
}

// generate 生成 zip 并上传，返回对象键与大小。
func (s *Service) generate(ctx context.Context, job dbgen.Export, loc *time.Location) (string, int64, error) {
	modules := make([]Module, len(job.Modules))
	for i, m := range job.Modules {
		modules[i] = Module(m)
	}
	data, err := load(ctx, s.d.Records, job.UserID, modules)
	if err != nil {
		return "", 0, err
	}
	opts := buildOptions{Now: s.d.Now(), Location: loc}
	if job.Attachments {
		if opts.Open, err = s.attachmentOpener(ctx, job.UserID); err != nil {
			return "", 0, err
		}
	}
	tmp, err := os.CreateTemp(s.d.TempDir, tempPattern)
	if err != nil {
		return "", 0, fmt.Errorf("创建临时文件失败: %w", err)
	}
	defer func() {
		_ = tmp.Close()
		_ = os.Remove(tmp.Name())
	}()
	if _, err := build(ctx, tmp, data, opts); err != nil {
		return "", 0, err
	}
	info, err := tmp.Stat()
	if err != nil {
		return "", 0, fmt.Errorf("读取临时文件失败: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return "", 0, fmt.Errorf("写入临时文件失败: %w", err)
	}
	key := ObjectKey(job.UserID, job.ID)
	if err := s.d.Store.PutFile(ctx, key, tmp.Name(), "application/zip"); err != nil {
		return "", 0, err
	}
	return key, info.Size(), nil
}

// ObjectKey 为导出文件的对象键：放在账号前缀下，注销账号时随附件一起删除。
func ObjectKey(userID, exportID uuid.UUID) string {
	return attachment.UserPrefix(userID) + "exports/" + exportID.String() + ".zip"
}

// attachmentOpener 返回按附件 ID 读取文件的函数；只能读取已上传完成的附件。
func (s *Service) attachmentOpener(ctx context.Context, userID uuid.UUID) (func(context.Context, uuid.UUID) (io.ReadCloser, error), error) {
	rows, err := s.d.Tx.Queries().ListReadyAttachments(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("查询附件失败: %w", err)
	}
	keys := make(map[uuid.UUID]string, len(rows))
	for _, r := range rows {
		keys[r.ID] = r.ObjectKey
	}
	return func(ctx context.Context, id uuid.UUID) (io.ReadCloser, error) {
		key, ok := keys[id]
		if !ok {
			return nil, storage.ErrNotFound
		}
		return s.d.Store.Open(ctx, key)
	}, nil
}

// location 为发起导出的设备所在时区（导出中的日期时间按它显示）；查不到时使用默认时区。
func (s *Service) location(ctx context.Context, job dbgen.Export) *time.Location {
	if job.DeviceID == nil {
		return location("")
	}
	d, err := s.d.Tx.Queries().GetExportDevice(ctx, dbgen.GetExportDeviceParams{ID: *job.DeviceID, UserID: job.UserID})
	if err != nil {
		if !db.IsNotFound(err) {
			s.d.Logger.WarnContext(ctx, "load export device failed", "export_id", job.ID, "error", err)
		}
		return location("")
	}
	return location(d.TimeZone)
}

func location(name string) *time.Location {
	if loc, err := time.LoadLocation(name); err == nil && name != "" {
		return loc
	}
	loc, _ := time.LoadLocation(defaultTimeZone)
	return loc
}

// notify 向账号所有已登录的设备推送一条通知（不含数据）：不只是发起导出的设备，
// 其他设备也能知道发生了导出。推送失败只写日志。
func (s *Service) notify(ctx context.Context, job dbgen.Export, title, body string) {
	tokens, err := s.d.Tx.Queries().ListPushTokens(ctx, job.UserID)
	if err != nil {
		s.d.Logger.WarnContext(ctx, "load push tokens failed", "export_id", job.ID, "error", err)
		return
	}
	if len(tokens) == 0 {
		return
	}
	err = s.d.Pusher.Push(ctx, pusher.Message{
		Tokens: tokens, Title: title, Body: body, TTL: Retention, Channel: pusher.ChannelGeneral,
		Extras: map[string]string{"type": "export", "exportId": job.ID.String()},
	})
	if err != nil {
		s.d.Logger.WarnContext(ctx, "export notification failed", "export_id", job.ID, "error", err)
	}
}

// Cleanup 删除过期的导出文件，并清除很久以前的导出记录。返回删除的文件数。
func (s *Service) Cleanup(ctx context.Context) (int, error) {
	q := s.d.Tx.Queries()
	expired, err := q.ListExpiredExports(ctx, dbgen.ListExpiredExportsParams{Now: ptr(s.d.Now()), MaxRows: expireBatch})
	if err != nil {
		return 0, fmt.Errorf("查询过期导出失败: %w", err)
	}
	n := 0
	var firstErr error
	for _, e := range expired {
		// 一个文件删除失败不影响其他文件：记下错误，继续处理
		if e.ObjectKey != nil {
			if err := s.d.Store.Delete(ctx, *e.ObjectKey); err != nil {
				s.d.Logger.WarnContext(ctx, "delete expired export failed", "export_id", e.ID, "error", err)
				firstErr = cmp.Or(firstErr, err)
				continue
			}
		}
		if err := q.ExpireExport(ctx, e.ID); err != nil {
			return n, fmt.Errorf("更新导出状态失败: %w", err)
		}
		n++
	}
	if _, err := q.PruneExports(ctx, s.d.Now().Add(-pruneAfter)); err != nil {
		return n, fmt.Errorf("清除导出记录失败: %w", err)
	}
	return n, firstErr
}

// tempPattern 为生成中的临时文件名。
const tempPattern = "jikelog-export-*.zip"

// sweepTemp 删除异常退出（如被强制结束）留下的临时文件，其中是明文数据。
func (s *Service) sweepTemp() {
	dir := cmp.Or(s.d.TempDir, os.TempDir())
	files, err := filepath.Glob(filepath.Join(dir, tempPattern))
	if err != nil {
		return
	}
	for _, f := range files {
		// 同一目录可能有其他实例正在生成：只删超过领取期限的
		if info, err := os.Stat(f); err != nil || time.Since(info.ModTime()) < lease {
			continue
		}
		if err := os.Remove(f); err != nil {
			s.d.Logger.Warn("remove stale export temp file failed", "error", err)
		}
	}
}

func wrapDB(err error) error {
	if err == nil || errors.Is(err, context.Canceled) {
		return err
	}
	return fmt.Errorf("记录导出结果失败: %w", err)
}

func ptr[T any](v T) *T { return &v }
