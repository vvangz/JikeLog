package syncer

import (
	"context"
	"maps"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// Handler 实现 sync 标签下的接口。所有接口都需要登录（由认证中间件保证）。
type Handler struct {
	svc      *Service
	sessions *e2e.Manager
}

// NewHandler 创建 Handler。
func NewHandler(svc *Service, sessions *e2e.Manager) *Handler {
	return &Handler{svc: svc, sessions: sessions}
}

var errEmptyBody = httpx.Validation(map[string]string{"body": "请求体不能为空"})

func base(ctx context.Context) apigen.EnvelopeBase { return httpx.Base(ctx, nil) }

// transport 按请求头查找传输加密会话；未携带时返回 nil（只有涉及敏感字段时才会报错）。
func (h *Handler) transport(ctx context.Context, p auth.Principal, header *apigen.E2ESessionHeader) (Transport, error) {
	if header == nil || *header == "" {
		return nil, nil
	}
	return h.sessions.Session(ctx, p, *header)
}

// CreateE2ESession 实现 POST /api/v1/sync/e2e/session。
func (h *Handler) CreateE2ESession(ctx context.Context, req apigen.CreateE2ESessionRequestObject) (apigen.CreateE2ESessionResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	sid, expires, err := h.sessions.Create(ctx, p, req.Body.ClientPublicKey, req.Body.ServerKeyId)
	if err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.CreateE2ESession201JSONResponse{
		Success: b.Success, RequestId: b.RequestId,
		Data: apigen.E2ESession{SessionId: sid, ExpiresAt: expires},
	}, nil
}

// PushChanges 实现 POST /api/v1/sync/push。
func (h *Handler) PushChanges(ctx context.Context, req apigen.PushChangesRequestObject) (apigen.PushChangesResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	tr, err := h.transport(ctx, p, req.Params.XJikeLogE2E)
	if err != nil {
		return nil, err
	}
	in := make([]IncomingChange, len(req.Body.Changes))
	for i, c := range req.Body.Changes {
		in[i] = incoming(c)
	}
	results, cursor, err := h.svc.Push(ctx, p, tr, in)
	if err != nil {
		return nil, err
	}
	out := make([]apigen.PushResult, len(results))
	for i, r := range results {
		out[i] = pushResult(r)
	}
	b := base(ctx)
	return apigen.PushChanges200JSONResponse{
		Success: b.Success, RequestId: b.RequestId,
		Data: apigen.PushResponse{Results: out, Cursor: cursor},
	}, nil
}

// PullChanges 实现 GET /api/v1/sync/pull。
func (h *Handler) PullChanges(ctx context.Context, req apigen.PullChangesRequestObject) (apigen.PullChangesResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	tr, err := h.transport(ctx, p, req.Params.XJikeLogE2E)
	if err != nil {
		return nil, err
	}
	limit := 0
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	page, err := h.svc.Pull(ctx, p, tr, req.Params.Since, limit)
	if err != nil {
		return nil, err
	}
	records := make([]apigen.SyncRecord, len(page.Records))
	for i, r := range page.Records {
		records[i] = syncRecord(r)
	}
	b := base(ctx)
	return apigen.PullChanges200JSONResponse{
		Success: b.Success, RequestId: b.RequestId,
		Data: apigen.PullResponse{Records: records, NextSince: page.NextSince, HasMore: page.HasMore},
	}, nil
}

// AckSync 实现 POST /api/v1/sync/ack。
func (h *Handler) AckSync(ctx context.Context, req apigen.AckSyncRequestObject) (apigen.AckSyncResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	if err := h.svc.Ack(ctx, p, req.Body.Seq); err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AckSync200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: apigen.Ack{Ok: true}}, nil
}

// ListRevisions 实现 GET /api/v1/records/{recordId}/revisions。
func (h *Handler) ListRevisions(ctx context.Context, req apigen.ListRevisionsRequestObject) (apigen.ListRevisionsResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	list, err := h.svc.Revisions(ctx, p, req.RecordId)
	if err != nil {
		return nil, err
	}
	out := make([]apigen.RevisionInfo, len(list))
	for i, r := range list {
		out[i] = apigen.RevisionInfo{
			Id: r.ID, Version: r.Version, Reason: apigen.RevisionInfoReason(r.Reason),
			CreatedAt: r.CreatedAt, DeviceModel: r.DeviceModel,
		}
	}
	b := base(ctx)
	return apigen.ListRevisions200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: out}, nil
}

// GetRevision 实现 GET /api/v1/revisions/{revisionId}。
func (h *Handler) GetRevision(ctx context.Context, req apigen.GetRevisionRequestObject) (apigen.GetRevisionResponseObject, error) {
	p, err := auth.MustPrincipal(ctx)
	if err != nil {
		return nil, err
	}
	tr, err := h.transport(ctx, p, req.Params.XJikeLogE2E)
	if err != nil {
		return nil, err
	}
	r, err := h.svc.Revision(ctx, p, tr, req.RevisionId)
	if err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.GetRevision200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: apigen.Revision{
		Id: r.ID, RecordId: r.RecordID, Entity: r.Entity, Version: r.Version,
		Reason: apigen.RevisionReason(r.Reason), CreatedAt: r.CreatedAt, Fields: r.Fields,
	}}, nil
}

func incoming(c apigen.SyncChange) IncomingChange {
	in := IncomingChange{Entity: c.Entity, ID: c.Id}
	if c.Deleted != nil {
		in.Deleted = *c.Deleted
	}
	if c.Fields != nil {
		in.Fields = *c.Fields
	}
	if c.Clocks != nil {
		in.Clocks = *c.Clocks
	}
	if c.BaseClocks != nil {
		in.BaseClocks = *c.BaseClocks
	}
	if c.Patches != nil {
		in.Patches = *c.Patches
	}
	return in
}

func pushResult(r Result) apigen.PushResult {
	out := apigen.PushResult{Id: r.ID, Status: apigen.PushResultStatus(r.Status)}
	if r.Status != StatusRejected {
		out.Version, out.ServerSeq = &r.Version, &r.ServerSeq
	}
	if r.Record != nil {
		rec := syncRecord(*r.Record)
		out.Record = &rec
	}
	if r.Error != nil {
		e := apigen.ChangeError{Code: r.Error.Code, Message: r.Error.Message}
		if len(r.Error.Fields) > 0 {
			fields := maps.Clone(r.Error.Fields)
			e.Fields = &fields
		}
		out.Error = &e
	}
	return out
}

func syncRecord(r Record) apigen.SyncRecord {
	clocks := make(map[string]string, len(r.Clocks))
	for f, c := range r.Clocks {
		clocks[f] = string(c)
	}
	return apigen.SyncRecord{
		Entity: r.Entity, Id: r.ID, Version: r.Version, ServerSeq: r.ServerSeq, Deleted: r.Deleted,
		Fields: r.Fields, Clocks: clocks, UpdatedAt: r.UpdatedAt,
	}
}
