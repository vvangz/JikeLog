package attachment

import (
	"context"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// Handler 实现 attachment 标签下的接口。所有接口都需要登录（由认证中间件保证）。
type Handler struct {
	svc      *Service
	sessions *e2e.Manager
}

// NewHandler 创建 Handler。
func NewHandler(svc *Service, sessions *e2e.Manager) *Handler {
	return &Handler{svc: svc, sessions: sessions}
}

var errEmptyBody = httpx.Validation(map[string]string{"body": "请求体不能为空"})

// CreateAttachmentUpload 实现 POST /api/v1/attachments。
func (h *Handler) CreateAttachmentUpload(ctx context.Context, req apigen.CreateAttachmentUploadRequestObject) (apigen.CreateAttachmentUploadResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	if req.Params.XJikeLogE2E == nil {
		return nil, e2e.ErrSessionInvalid // 文件名为敏感字段，必须加密传输
	}
	sess, err := h.sessions.Session(ctx, p, *req.Params.XJikeLogE2E)
	if err != nil {
		return nil, err
	}
	b := req.Body
	name, err := openFileName(sess, b.Id, b.FileName)
	if err != nil {
		return nil, err
	}
	up, err := h.svc.CreateUpload(ctx, p, UploadRequest{
		ID: b.Id, OwnerEntity: b.OwnerEntity, OwnerID: b.OwnerId, FileName: name,
		Mime: b.Mime, Size: b.Size, SHA256: b.Sha256,
	})
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.CreateAttachmentUpload201JSONResponse{Success: base.Success, RequestId: base.RequestId, Data: apigen.AttachmentUpload{
		UploadUrl: up.URL, Method: apigen.AttachmentUploadMethodPUT, Headers: up.Headers, ExpiresAt: up.Expires,
	}}, nil
}

// CompleteAttachmentUpload 实现 POST /api/v1/attachments/{attachmentId}/complete。
func (h *Handler) CompleteAttachmentUpload(ctx context.Context, req apigen.CompleteAttachmentUploadRequestObject) (apigen.CompleteAttachmentUploadResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	seq, err := h.svc.Complete(ctx, p, req.AttachmentId)
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.CompleteAttachmentUpload200JSONResponse{Success: base.Success, RequestId: base.RequestId,
		Data: apigen.AttachmentComplete{ServerSeq: seq}}, nil
}

// GetAttachmentDownload 实现 GET /api/v1/attachments/{attachmentId}/download。
func (h *Handler) GetAttachmentDownload(ctx context.Context, req apigen.GetAttachmentDownloadRequestObject) (apigen.GetAttachmentDownloadResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	url, expires, err := h.svc.DownloadURL(ctx, p, req.AttachmentId)
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.GetAttachmentDownload200JSONResponse{Success: base.Success, RequestId: base.RequestId,
		Data: apigen.AttachmentDownload{Url: url, ExpiresAt: expires}}, nil
}

// GetAttachmentUsage 实现 GET /api/v1/attachments/usage。
func (h *Handler) GetAttachmentUsage(ctx context.Context, _ apigen.GetAttachmentUsageRequestObject) (apigen.GetAttachmentUsageResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	used, quota, maxSize, err := h.svc.Usage(ctx, p)
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.GetAttachmentUsage200JSONResponse{Success: base.Success, RequestId: base.RequestId,
		Data: apigen.AttachmentUsage{Used: used, Quota: quota, MaxSize: maxSize}}, nil
}
