package export

import (
	"context"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// Handler 实现 export 标签下的接口。所有接口都需要登录（由认证中间件保证）。
type Handler struct {
	svc *Service
}

// NewHandler 创建 Handler。
func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

var errEmptyBody = httpx.Validation(map[string]string{"body": "请求体不能为空"})

// ListExports 实现 GET /api/v1/exports。
func (h *Handler) ListExports(ctx context.Context, _ apigen.ListExportsRequestObject) (apigen.ListExportsResponseObject, error) {
	ctx = httpx.RequestContext(ctx)
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	list, err := h.svc.List(ctx, p)
	if err != nil {
		return nil, err
	}
	out := make([]apigen.Export, len(list))
	for i, e := range list {
		out[i] = toAPI(e)
	}
	base := httpx.Base(ctx, nil)
	return apigen.ListExports200JSONResponse{Success: base.Success, RequestId: base.RequestId, Data: out}, nil
}

// CreateExport 实现 POST /api/v1/exports。
func (h *Handler) CreateExport(ctx context.Context, req apigen.CreateExportRequestObject) (apigen.CreateExportResponseObject, error) {
	ctx = httpx.RequestContext(ctx)
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	modules := make([]Module, len(req.Body.Modules))
	for i, m := range req.Body.Modules {
		modules[i] = Module(m)
	}
	e, err := h.svc.Create(ctx, p, modules, req.Body.Attachments)
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.CreateExport202JSONResponse{Success: base.Success, RequestId: base.RequestId, Data: toAPI(e)}, nil
}

// GetExport 实现 GET /api/v1/exports/{exportId}。
func (h *Handler) GetExport(ctx context.Context, req apigen.GetExportRequestObject) (apigen.GetExportResponseObject, error) {
	ctx = httpx.RequestContext(ctx)
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	e, err := h.svc.Get(ctx, p, req.ExportId)
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.GetExport200JSONResponse{Success: base.Success, RequestId: base.RequestId, Data: toAPI(e)}, nil
}

// DeleteExport 实现 DELETE /api/v1/exports/{exportId}。
func (h *Handler) DeleteExport(ctx context.Context, req apigen.DeleteExportRequestObject) (apigen.DeleteExportResponseObject, error) {
	ctx = httpx.RequestContext(ctx)
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if err := h.svc.Delete(ctx, p, req.ExportId); err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.DeleteExport200JSONResponse{Success: base.Success, RequestId: base.RequestId, Data: apigen.Ack{Ok: true}}, nil
}

// GetExportDownload 实现 GET /api/v1/exports/{exportId}/download。
func (h *Handler) GetExportDownload(ctx context.Context, req apigen.GetExportDownloadRequestObject) (apigen.GetExportDownloadResponseObject, error) {
	ctx = httpx.RequestContext(ctx)
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	url, expires, err := h.svc.DownloadURL(ctx, p, req.ExportId)
	if err != nil {
		return nil, err
	}
	base := httpx.Base(ctx, nil)
	return apigen.GetExportDownload200JSONResponse{Success: base.Success, RequestId: base.RequestId,
		Data: apigen.AttachmentDownload{Url: url, ExpiresAt: expires}}, nil
}

func toAPI(e dbgen.Export) apigen.Export {
	modules := make([]apigen.ExportModule, len(e.Modules))
	for i, m := range e.Modules {
		modules[i] = apigen.ExportModule(m)
	}
	return apigen.Export{
		Id: e.ID, Modules: modules, Attachments: e.Attachments, Status: apigen.ExportStatus(e.Status),
		Size: e.Size, Error: e.Error, CreatedAt: e.CreatedAt, FinishedAt: e.FinishedAt, ExpiresAt: e.ExpiresAt,
	}
}
