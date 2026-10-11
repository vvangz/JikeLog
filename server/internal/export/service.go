// Package export 生成数据导出文件（ADR-010）：用户发起后由后台任务读取并解密所选模块的记录，
// 生成 zip 上传到对象存储，完成后推送通知；文件保留 24 小时。
package export

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"slices"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/pusher"
)

const (
	// MaxPerDay 为每个账号 24 小时内最多发起的导出次数。
	MaxPerDay = 5
	// Retention 为导出文件的保留时长。
	Retention = 24 * time.Hour
	// downloadTTL 为下载地址的有效期。
	downloadTTL = 10 * time.Minute
	// listLimit 为列表返回的最近导出数。
	listLimit = 10
)

// 错误码。
const (
	CodeInProgress = "EXPORT_IN_PROGRESS"
	CodeLimit      = "EXPORT_LIMIT"
	CodeNotReady   = "EXPORT_NOT_READY"
	CodeNotFound   = "NOT_FOUND"
)

var (
	errInProgress = httpx.NewError(http.StatusConflict, CodeInProgress, "已有一个导出正在进行，请等它完成")
	errLimit      = httpx.NewError(http.StatusTooManyRequests, CodeLimit, fmt.Sprintf("24 小时内最多导出 %d 次，请稍后再试", MaxPerDay))
	errNotReady   = httpx.NewError(http.StatusConflict, CodeNotReady, "导出文件尚未生成或已过期")
	errNotFound   = httpx.NewError(http.StatusNotFound, CodeNotFound, "导出不存在")
)

// ObjectStore 为对象存储（*storage.Store 实现）。
type ObjectStore interface {
	Open(ctx context.Context, key string) (io.ReadCloser, error)
	PutFile(ctx context.Context, key, path, contentType string) error
	PresignGet(ctx context.Context, key string, ttl time.Duration) (string, time.Time, error)
	Delete(ctx context.Context, key string) error
}

// Deps 为 Service 的依赖。
type Deps struct {
	Tx      db.TxRunner
	Store   ObjectStore
	Records RecordSource
	Pusher  pusher.Pusher
	Logger  *slog.Logger
	// Now 为空时使用 time.Now。
	Now func() time.Time
	// TempDir 为生成 zip 的临时目录；为空时使用系统默认目录。
	TempDir string
}

// Service 处理导出请求，并在后台生成导出文件。
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

// Create 发起一次导出。modules 不能为空，重复的模块只算一次。
func (s *Service) Create(ctx context.Context, p auth.Principal, modules []Module, attachments bool) (dbgen.Export, error) {
	mods, err := normalize(modules)
	if err != nil {
		return dbgen.Export{}, err
	}
	now := s.d.Now()
	q := s.d.Tx.Queries()
	n, err := q.CountExportsSince(ctx, dbgen.CountExportsSinceParams{UserID: p.UserID, Since: now.Add(-24 * time.Hour)})
	if err != nil {
		return dbgen.Export{}, fmt.Errorf("查询导出次数失败: %w", err)
	}
	if n >= MaxPerDay {
		return dbgen.Export{}, errLimit
	}
	id, err := uuid.NewV7()
	if err != nil {
		return dbgen.Export{}, err
	}
	device := p.DeviceID
	rows, err := q.CreateExport(ctx, dbgen.CreateExportParams{
		ID: id, UserID: p.UserID, DeviceID: &device, Modules: mods, Attachments: attachments, CreatedAt: now,
	})
	if err != nil {
		return dbgen.Export{}, fmt.Errorf("创建导出失败: %w", err)
	}
	if rows == 0 {
		return dbgen.Export{}, errInProgress
	}
	// 审计：导出的是解密后的全部数据
	s.d.Logger.InfoContext(ctx, "export requested", "user_id", p.UserID, "device_id", p.DeviceID,
		"export_id", id, "modules", mods, "attachments", attachments)
	return s.Get(ctx, p, id)
}

// normalize 校验模块并按固定顺序去重。
func normalize(modules []Module) ([]string, error) {
	var out []string
	for _, m := range Modules {
		if slices.Contains(modules, m) {
			out = append(out, string(m))
		}
	}
	for _, m := range modules {
		if !slices.Contains(Modules, m) {
			return nil, httpx.Validation(map[string]string{"modules": "包含未知的模块"})
		}
	}
	if len(out) == 0 {
		return nil, httpx.Validation(map[string]string{"modules": "至少选择一个模块"})
	}
	return out, nil
}

// List 返回最近的导出，新的在前。
func (s *Service) List(ctx context.Context, p auth.Principal) ([]dbgen.Export, error) {
	list, err := s.d.Tx.Queries().ListExports(ctx, dbgen.ListExportsParams{UserID: p.UserID, MaxRows: listLimit})
	if err != nil {
		return nil, fmt.Errorf("查询导出失败: %w", err)
	}
	return list, nil
}

// Get 返回一次导出。
func (s *Service) Get(ctx context.Context, p auth.Principal, id uuid.UUID) (dbgen.Export, error) {
	e, err := s.d.Tx.Queries().GetExport(ctx, dbgen.GetExportParams{ID: id, UserID: p.UserID})
	if db.IsNotFound(err) {
		return dbgen.Export{}, errNotFound
	}
	if err != nil {
		return dbgen.Export{}, fmt.Errorf("查询导出失败: %w", err)
	}
	return e, nil
}

// DownloadURL 返回导出文件的预签名下载地址。
func (s *Service) DownloadURL(ctx context.Context, p auth.Principal, id uuid.UUID) (string, time.Time, error) {
	e, err := s.Get(ctx, p, id)
	if err != nil {
		return "", time.Time{}, err
	}
	if e.Status != statusDone || e.ObjectKey == nil || e.ExpiresAt == nil || !s.d.Now().Before(*e.ExpiresAt) {
		return "", time.Time{}, errNotReady
	}
	url, expires, err := s.d.Store.PresignGet(ctx, *e.ObjectKey, downloadTTL)
	if err != nil {
		return "", time.Time{}, err
	}
	s.d.Logger.InfoContext(ctx, "export download issued", "user_id", p.UserID, "device_id", p.DeviceID, "export_id", id)
	return url, expires, nil
}

// Delete 删除导出文件，并把记录标为已删除（不再显示）。记录保留到超过 24 小时才清除，
// 仍计入每天的导出次数。进行中的导出不能删除。
func (s *Service) Delete(ctx context.Context, p auth.Principal, id uuid.UUID) error {
	e, err := s.Get(ctx, p, id)
	if err != nil {
		return err
	}
	if e.Status == statusPending || e.Status == statusRunning {
		return errInProgress
	}
	// 先删文件再改记录：删除文件失败时记录还在，过期清理仍会处理
	if e.ObjectKey != nil {
		if err := s.d.Store.Delete(ctx, *e.ObjectKey); err != nil {
			return err
		}
	}
	if _, err := s.d.Tx.Queries().MarkExportDeleted(ctx, dbgen.MarkExportDeletedParams{ID: id, UserID: p.UserID}); err != nil {
		return fmt.Errorf("删除导出失败: %w", err)
	}
	s.d.Logger.InfoContext(ctx, "export deleted", "user_id", p.UserID, "export_id", id)
	return nil
}
