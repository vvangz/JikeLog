// Package attachment 实现附件的直传直下：服务端只签发预签名地址、核对上传结果并生成同步记录，
// 文件内容不经过 API 服务器。对象键不含文件名，文件名以密文保存（ADR-006）。
package attachment

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/storage"
	"github.com/vvangz/JikeLog/server/internal/syncer"
	"github.com/vvangz/JikeLog/server/internal/vault"
)

// 错误码。
const (
	CodeTooLarge         = "ATTACHMENT_TOO_LARGE"
	CodeQuotaExceeded    = "QUOTA_EXCEEDED"
	CodeOwnerNotFound    = "OWNER_NOT_FOUND"
	CodeNotFound         = "ATTACHMENT_NOT_FOUND"
	CodeUploadIncomplete = "UPLOAD_INCOMPLETE"
	CodeIDConflict       = "ID_CONFLICT"
)

const (
	uploadTTL   = 15 * time.Minute
	downloadTTL = 10 * time.Minute
	// 文件名字段的落库 AAD 与 attachment 同步记录一致，便于复用同一密文。
	fieldFileName = "fileName"
)

var (
	mimePattern   = regexp.MustCompile(`^[a-z0-9][a-z0-9!#$&^_.+-]{0,63}/[a-z0-9][a-z0-9!#$&^_.+-]{0,63}$`)
	sha256Pattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

	errNotFound      = httpx.NewError(http.StatusNotFound, CodeNotFound, "附件不存在")
	errOwnerNotFound = httpx.NewError(http.StatusNotFound, CodeOwnerNotFound, "附件所属的记录不存在，请先同步该记录")
	errIncomplete    = httpx.NewError(http.StatusConflict, CodeUploadIncomplete, "文件尚未上传完成，请重新上传")
	errIDConflict    = httpx.NewError(http.StatusConflict, CodeIDConflict, "附件 ID 冲突，请重新选择文件")
)

// ObjectStore 为对象存储（*storage.Store 实现）。
type ObjectStore interface {
	PresignPut(ctx context.Context, key string, size int64, contentType string, ttl time.Duration) (storage.Upload, error)
	PresignGet(ctx context.Context, key string, ttl time.Duration) (string, time.Time, error)
	Size(ctx context.Context, key string) (int64, error)
	Delete(ctx context.Context, key string) error
	DeletePrefix(ctx context.Context, prefix string) error
}

// Deps 为 Service 的依赖。
type Deps struct {
	Tx     db.TxRunner
	Store  ObjectStore
	Keys   *vault.Keyring
	Sync   *syncer.Service
	Limits config.Attachment
	Logger *slog.Logger
}

// Service 为附件业务逻辑。
type Service struct {
	d Deps
}

// NewService 创建 Service。
func NewService(d Deps) *Service { return &Service{d: d} }

// UploadRequest 为申请上传参数；FileName 为明文（已由处理器解密）。
type UploadRequest struct {
	ID          uuid.UUID
	OwnerEntity string
	OwnerID     uuid.UUID
	FileName    string
	Mime        string
	Size        int64
	SHA256      string
}

func objectKey(userID, id uuid.UUID) string { return "u/" + userID.String() + "/" + id.String() }

// UserPrefix 返回账号全部附件对象的前缀。
func UserPrefix(userID uuid.UUID) string { return "u/" + userID.String() + "/" }

func (r UploadRequest) validate(maxSize int64) error {
	fields := map[string]string{}
	if e, ok := syncer.Registry[r.OwnerEntity]; !ok || e.ServerCreated {
		fields["ownerEntity"] = "不支持为该类型添加附件"
	}
	if !mimePattern.MatchString(r.Mime) {
		fields["mime"] = "文件类型格式错误"
	}
	if !sha256Pattern.MatchString(r.SHA256) {
		fields["sha256"] = "必须是 64 位小写十六进制"
	}
	if msg := checkFileName(r.FileName); msg != "" {
		fields["fileName"] = msg
	}
	if r.Size <= 0 {
		fields["size"] = "必须大于 0"
	}
	if len(fields) > 0 {
		return httpx.Validation(fields)
	}
	if r.Size > maxSize {
		return httpx.NewError(http.StatusRequestEntityTooLarge, CodeTooLarge, fmt.Sprintf("单个附件不能超过 %d MB", maxSize>>20))
	}
	return nil
}

func checkFileName(name string) string {
	switch {
	case strings.TrimSpace(name) == "":
		return "不能为空"
	case utf8.RuneCountInString(name) > 255:
		return "不能超过 255 个字符"
	case strings.ContainsAny(name, `/\`) || strings.IndexFunc(name, unicode.IsControl) >= 0:
		return "不能包含路径分隔符或控制字符"
	}
	return ""
}

// CreateUpload 登记附件并返回预签名上传地址。同一附件重复申请时重新签发地址（幂等）。
func (s *Service) CreateUpload(ctx context.Context, p auth.Principal, r UploadRequest) (storage.Upload, error) {
	if err := r.validate(s.d.Limits.MaxSize); err != nil {
		return storage.Upload{}, err
	}
	err := s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		existing, err := q.GetAttachment(ctx, dbgen.GetAttachmentParams{ID: r.ID, UserID: p.UserID})
		switch {
		case err == nil:
			if existing.Status != "pending" || existing.Size != r.Size || existing.Mime != r.Mime {
				return errIDConflict
			}
			return nil
		case !db.IsNotFound(err):
			return fmt.Errorf("查询附件失败: %w", err)
		}
		return s.register(ctx, q, p, r)
	})
	if err != nil {
		return storage.Upload{}, err
	}
	return s.d.Store.PresignPut(ctx, objectKey(p.UserID, r.ID), r.Size, r.Mime, uploadTTL)
}

func (s *Service) register(ctx context.Context, q *dbgen.Queries, p auth.Principal, r UploadRequest) error {
	owner, err := q.GetRecord(ctx, dbgen.GetRecordParams{ID: r.OwnerID, UserID: p.UserID})
	if db.IsNotFound(err) || (err == nil && (owner.Deleted || owner.Entity != r.OwnerEntity)) {
		return errOwnerNotFound
	}
	if err != nil {
		return fmt.Errorf("查询所属记录失败: %w", err)
	}
	if _, err := q.GetRecordForUpdate(ctx, r.ID); err == nil {
		return errIDConflict // 已被其他记录或其他账号占用
	} else if !db.IsNotFound(err) {
		return fmt.Errorf("查询记录失败: %w", err)
	}
	used, err := q.SumAttachmentBytes(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("统计附件用量失败: %w", err)
	}
	if used+r.Size > s.d.Limits.Quota {
		return httpx.NewError(http.StatusRequestEntityTooLarge, CodeQuotaExceeded, "附件空间已用完，请删除不需要的附件后重试")
	}
	key, err := s.d.Keys.DataKey(ctx, q, p.UserID, true)
	if err != nil {
		return err
	}
	sealed, err := vault.SealField(key, p.UserID, r.ID, fieldFileName, r.FileName)
	if err != nil {
		return err
	}
	if err := q.InsertAttachment(ctx, dbgen.InsertAttachmentParams{
		ID: r.ID, UserID: p.UserID, OwnerEntity: r.OwnerEntity, OwnerID: r.OwnerID,
		ObjectKey: objectKey(p.UserID, r.ID), FileName: sealed, Mime: r.Mime, Size: r.Size, Sha256: r.SHA256,
	}); err != nil {
		return fmt.Errorf("登记附件失败: %w", err)
	}
	return nil
}

// Complete 核对对象大小，标记为可用并生成 attachment 同步记录，返回同步序号。重复调用是幂等的。
func (s *Service) Complete(ctx context.Context, p auth.Principal, id uuid.UUID) (int64, error) {
	var seq int64
	created := false
	err := s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		a, err := q.GetAttachmentForUpdate(ctx, dbgen.GetAttachmentForUpdateParams{ID: id, UserID: p.UserID})
		if db.IsNotFound(err) || (err == nil && a.Status == "deleted") {
			return errNotFound
		}
		if err != nil {
			return fmt.Errorf("查询附件失败: %w", err)
		}
		if a.Status == "ready" {
			seq, err = q.GetSyncCursor(ctx, p.UserID)
			return err
		}
		size, err := s.d.Store.Size(ctx, a.ObjectKey)
		if err != nil || size != a.Size {
			if err != nil && !errors.Is(err, storage.ErrNotFound) {
				return err
			}
			return errIncomplete
		}
		if seq, err = s.writeRecord(ctx, q, p, a); err != nil {
			return err
		}
		created = true
		return q.MarkAttachmentReady(ctx, id)
	})
	if err != nil {
		return 0, err
	}
	if created {
		s.d.Sync.Notify(ctx, p, seq)
	}
	return seq, nil
}

func (s *Service) writeRecord(ctx context.Context, q *dbgen.Queries, p auth.Principal, a dbgen.Attachment) (int64, error) {
	key, err := s.d.Keys.DataKey(ctx, q, p.UserID, false)
	if err != nil {
		return 0, err
	}
	name, err := vault.OpenField(key, p.UserID, a.ID, fieldFileName, a.FileName)
	if err != nil {
		return 0, fmt.Errorf("解密文件名失败: %w", err)
	}
	return s.d.Sync.WriteServerRecord(ctx, q, p, syncer.EntityAttachment, a.ID, map[string]syncer.Value{
		"ownerEntity": a.OwnerEntity, "ownerId": a.OwnerID.String(), fieldFileName: name,
		"mime": a.Mime, "size": a.Size, "sha256": a.Sha256,
	})
}

// DownloadURL 返回已上传附件的预签名下载地址。
func (s *Service) DownloadURL(ctx context.Context, p auth.Principal, id uuid.UUID) (string, time.Time, error) {
	a, err := s.d.Tx.Queries().GetAttachment(ctx, dbgen.GetAttachmentParams{ID: id, UserID: p.UserID})
	if db.IsNotFound(err) || (err == nil && a.Status != "ready") {
		return "", time.Time{}, errNotFound
	}
	if err != nil {
		return "", time.Time{}, fmt.Errorf("查询附件失败: %w", err)
	}
	return s.d.Store.PresignGet(ctx, a.ObjectKey, downloadTTL)
}

// Usage 返回账号的附件用量与上限。
func (s *Service) Usage(ctx context.Context, p auth.Principal) (used, quota, maxSize int64, err error) {
	used, err = s.d.Tx.Queries().SumAttachmentBytes(ctx, p.UserID)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("统计附件用量失败: %w", err)
	}
	return used, s.d.Limits.Quota, s.d.Limits.MaxSize, nil
}

// Cleanup 删除已标记删除的附件对象，返回清理数量。由后台定时调用。
func (s *Service) Cleanup(ctx context.Context, batch int32) (int, error) {
	q := s.d.Tx.Queries()
	rows, err := q.ListDeletedAttachments(ctx, batch)
	if err != nil {
		return 0, fmt.Errorf("查询待清理附件失败: %w", err)
	}
	n := 0
	for _, r := range rows {
		if err := s.d.Store.Delete(ctx, r.ObjectKey); err != nil {
			s.d.Logger.WarnContext(ctx, "delete attachment object failed", "attachment_id", r.ID, "error", err)
			continue
		}
		if err := q.PurgeAttachment(ctx, r.ID); err != nil {
			return n, fmt.Errorf("清理附件记录失败: %w", err)
		}
		n++
	}
	return n, nil
}

// DeleteUserObjects 删除账号的全部附件对象（注销账号后调用）。
func (s *Service) DeleteUserObjects(ctx context.Context, userID uuid.UUID) error {
	return s.d.Store.DeletePrefix(ctx, UserPrefix(userID))
}

// openFileName 解密附件请求中的文件名。
func openFileName(sess *e2e.Session, id uuid.UUID, enc string) (string, error) {
	return sess.Open(e2e.AAD(syncer.EntityAttachment, id, fieldFileName, e2e.KindValue), enc)
}
