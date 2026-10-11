package admin

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	openapi_types "github.com/oapi-codegen/runtime/types"

	"github.com/vvangz/JikeLog/server/internal/account"
	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

// RefreshCookie 为管理员 Refresh Token 的 Cookie 名，只在刷新与退出接口的路径下发送。
const (
	RefreshCookie = "jikelog_admin_refresh"
	cookiePath    = "/api/admin/v1/auth"
)

// Handler 实现 admin 标签下的接口。
type Handler struct {
	svc *Service
	// secure 为 true 时 Cookie 只经 HTTPS 发送（开发环境为 false）。
	secure bool
}

// NewHandler 创建 Handler。
func NewHandler(svc *Service, secureCookie bool) *Handler {
	return &Handler{svc: svc, secure: secureCookie}
}

type principalKey struct{}

// WithPrincipal 把管理员放入请求上下文（由认证中间件调用）。
func WithPrincipal(ctx context.Context, p Principal) context.Context {
	return context.WithValue(ctx, principalKey{}, p)
}

func principal(ctx context.Context) (Principal, error) {
	p, ok := ctx.Value(principalKey{}).(Principal)
	if !ok {
		return Principal{}, errSession
	}
	return p, nil
}

// request 返回请求上下文、当前管理员与请求来源。
func request(ctx context.Context) (context.Context, Principal, Meta, error) {
	m := metaOf(ctx)
	ctx = httpx.RequestContext(ctx)
	p, err := principal(ctx)
	return ctx, p, m, err
}

func metaOf(ctx context.Context) Meta {
	m := Meta{IP: httpx.ClientIPFrom(httpx.RequestContext(ctx))}
	if c, ok := ctx.(*gin.Context); ok && c.Request != nil {
		m.UserAgent = c.Request.UserAgent()
	}
	return m
}

// cookie 生成 Refresh Token 的 Set-Cookie；value 为空时删除 Cookie。
func (h *Handler) cookie(value string, expires time.Time) *string {
	c := http.Cookie{ //nolint:gosec // Secure 由部署环境决定：开发与验收环境走 HTTP，部署环境为 true
		Name: RefreshCookie, Value: value, Path: cookiePath,
		HttpOnly: true, Secure: h.secure, SameSite: http.SameSiteStrictMode,
	}
	if value == "" {
		c.MaxAge = -1
	} else {
		c.Expires = expires
		c.MaxAge = int(time.Until(expires).Seconds())
	}
	s := c.String()
	return &s
}

func base(ctx context.Context) apigen.EnvelopeBase { return httpx.Base(ctx, nil) }

func sessionBody(ctx context.Context, s Session) apigen.AdminSessionEnvelope {
	b := base(ctx)
	return apigen.AdminSessionEnvelope{Success: b.Success, RequestId: b.RequestId, Data: apigen.AdminSession{
		AccessToken: s.AccessToken, ExpiresAt: s.ExpiresAt, Admin: profile(s.Admin),
	}}
}

func profile(a dbgen.AdminUser) apigen.AdminProfile {
	return apigen.AdminProfile{
		Id: a.ID, Username: a.Username, Role: apigen.AdminRole(a.Role), Disabled: a.Disabled,
		MustChangePassword: a.MustChangePassword, LastLoginAt: a.LastLoginAt, CreatedAt: a.CreatedAt,
	}
}

var errEmptyBody = httpx.Validation(map[string]string{"body": "请求体不能为空"})

// AdminLogin 实现 POST /api/admin/v1/auth/login。
func (h *Handler) AdminLogin(ctx context.Context, req apigen.AdminLoginRequestObject) (apigen.AdminLoginResponseObject, error) {
	m := metaOf(ctx)
	ctx = httpx.RequestContext(ctx)
	if req.Body == nil {
		return nil, errEmptyBody
	}
	s, err := h.svc.Login(ctx, req.Body.Username, req.Body.Password, m)
	if err != nil {
		return nil, err
	}
	return apigen.AdminLogin200JSONResponse{Body: sessionBody(ctx, s),
		Headers: apigen.AdminLogin200ResponseHeaders{SetCookie: h.cookie(s.RefreshToken, s.RefreshExpires)}}, nil
}

func cookieValue(c *apigen.AdminRefreshCookie) string {
	if c == nil {
		return ""
	}
	return *c
}

// AdminRefresh 实现 POST /api/admin/v1/auth/refresh。
func (h *Handler) AdminRefresh(ctx context.Context, req apigen.AdminRefreshRequestObject) (apigen.AdminRefreshResponseObject, error) {
	ctx = httpx.RequestContext(ctx)
	s, err := h.svc.Refresh(ctx, cookieValue(req.Params.JikelogAdminRefresh))
	if err != nil {
		return nil, err
	}
	return apigen.AdminRefresh200JSONResponse{Body: sessionBody(ctx, s),
		Headers: apigen.AdminRefresh200ResponseHeaders{SetCookie: h.cookie(s.RefreshToken, s.RefreshExpires)}}, nil
}

// AdminLogout 实现 POST /api/admin/v1/auth/logout。
func (h *Handler) AdminLogout(ctx context.Context, req apigen.AdminLogoutRequestObject) (apigen.AdminLogoutResponseObject, error) {
	m := metaOf(ctx)
	ctx = httpx.RequestContext(ctx)
	if err := h.svc.Logout(ctx, cookieValue(req.Params.JikelogAdminRefresh), m); err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AdminLogout200JSONResponse{
		Body:    apigen.AckEnvelope{Success: b.Success, RequestId: b.RequestId, Data: apigen.Ack{Ok: true}},
		Headers: apigen.AdminLogout200ResponseHeaders{SetCookie: h.cookie("", time.Time{})},
	}, nil
}

// AdminMe 实现 GET /api/admin/v1/me。
func (h *Handler) AdminMe(ctx context.Context, _ apigen.AdminMeRequestObject) (apigen.AdminMeResponseObject, error) {
	ctx, p, _, err := request(ctx)
	if err != nil {
		return nil, err
	}
	a, err := h.svc.Me(ctx, p)
	if err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AdminMe200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: profile(a)}, nil
}

// AdminChangePassword 实现 PUT /api/admin/v1/me/password。
func (h *Handler) AdminChangePassword(ctx context.Context, req apigen.AdminChangePasswordRequestObject) (apigen.AdminChangePasswordResponseObject, error) {
	ctx, p, m, err := request(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	if err := h.svc.ChangePassword(ctx, p, req.Body.CurrentPassword, req.Body.NewPassword, m); err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AdminChangePassword200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: apigen.Ack{Ok: true}}, nil
}

// AdminDashboard 实现 GET /api/admin/v1/dashboard。
func (h *Handler) AdminDashboard(ctx context.Context, _ apigen.AdminDashboardRequestObject) (apigen.AdminDashboardResponseObject, error) {
	ctx, p, m, err := request(ctx)
	if err != nil {
		return nil, err
	}
	d, err := h.svc.Dashboard(ctx, p, m)
	if err != nil {
		return nil, err
	}
	out := apigen.AdminDashboard{
		TotalUsers: d.Stats.Total, NewUsersToday: d.Stats.NewToday, ActiveToday: d.Stats.ActiveToday,
		ActiveWeek: d.Stats.ActiveWeek, ActiveMonth: d.Stats.ActiveMonth, StorageBytes: d.Stats.StorageBytes,
		NewUsersDaily: make([]apigen.DailyCount, 0, len(d.Daily)), Platforms: make([]apigen.PlatformCount, 0, len(d.Platforms)),
	}
	for _, c := range d.Daily {
		day, _ := time.Parse(time.DateOnly, c.Day)
		out.NewUsersDaily = append(out.NewUsersDaily, apigen.DailyCount{Day: openapi_types.Date{Time: day}, Count: c.Count})
	}
	for _, pc := range d.Platforms {
		out.Platforms = append(out.Platforms, apigen.PlatformCount{Platform: pc.Platform, Devices: pc.Devices})
	}
	b := base(ctx)
	return apigen.AdminDashboard200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: out}, nil
}

func pageParams(page *apigen.Page, size *apigen.PageSize) (int, int) {
	p, s := 1, defaultPageSize
	if page != nil {
		p = *page
	}
	if size != nil {
		s = *size
	}
	return p, s
}

// AdminListUsers 实现 GET /api/admin/v1/users。
func (h *Handler) AdminListUsers(ctx context.Context, req apigen.AdminListUsersRequestObject) (apigen.AdminListUsersResponseObject, error) {
	ctx, p, m, err := request(ctx)
	if err != nil {
		return nil, err
	}
	q := ""
	if req.Params.Q != nil {
		q = *req.Params.Q
	}
	page, size := pageParams(req.Params.Page, req.Params.PageSize)
	res, err := h.svc.ListUsers(ctx, p, q, page, size, m)
	if err != nil {
		return nil, err
	}
	out := make([]apigen.AdminUserSummary, len(res.Users))
	for i, u := range res.Users {
		out[i] = apigen.AdminUserSummary{
			Id: u.ID, Username: u.Username, Nickname: u.Nickname, PhoneMasked: maskedPtr(u.Phone),
			CreatedAt: u.CreatedAt, LastActiveAt: &u.LastActiveAt, DeviceCount: u.DeviceCount, StorageBytes: u.StorageBytes,
		}
	}
	b := base(ctx)
	return apigen.AdminListUsers200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: out,
		Meta: apigen.PageMeta{Total: res.Total, Page: res.Page, Limit: res.Size}}, nil
}

func maskedPtr(phone *string) *string {
	if phone == nil {
		return nil
	}
	m := MaskPhone(*phone)
	return &m
}

// AdminGetUser 实现 GET /api/admin/v1/users/{userId}。
func (h *Handler) AdminGetUser(ctx context.Context, req apigen.AdminGetUserRequestObject) (apigen.AdminGetUserResponseObject, error) {
	ctx, p, m, err := request(ctx)
	if err != nil {
		return nil, err
	}
	d, err := h.svc.GetUser(ctx, p, req.UserId, m)
	if err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AdminGetUser200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: detail(d)}, nil
}

func detail(d UserDetail) apigen.AdminUserDetail {
	summary := apigen.AdminUserSummary{
		Id: d.User.ID, Username: d.User.Username, Nickname: d.User.Nickname, PhoneMasked: maskedPtr(d.User.Phone),
		CreatedAt: d.User.CreatedAt, StorageBytes: d.Used,
	}
	devices := make([]apigen.AdminUserDevice, len(d.Devices))
	for i, dv := range d.Devices {
		devices[i] = apigen.AdminUserDevice{
			Id: dv.ID, Platform: dv.Platform, Model: dv.Model, OsVersion: dv.OsVersion, AppVersion: dv.AppVersion,
			LastActiveAt: dv.LastActiveAt, CreatedAt: dv.CreatedAt, SignedIn: dv.RevokedAt == nil,
			LocalReminders: dv.LocalReminders, PushEnabled: dv.PushEnabled, AckSeq: dv.LastAckSeq,
		}
		if dv.RevokedAt == nil {
			summary.DeviceCount++
		}
		if summary.LastActiveAt == nil || dv.LastActiveAt.After(*summary.LastActiveAt) {
			t := dv.LastActiveAt
			summary.LastActiveAt = &t
		}
	}
	settings := apigen.Settings{ThemeMode: apigen.ThemeModeSystem, FontScale: 1, WeekStart: 1, DefaultReminders: []int32{0}}
	if d.HasSetting {
		settings = account.ToSettings(d.Settings)
	}
	out := apigen.AdminUserDetail{User: summary, Settings: settings, Devices: devices}
	out.Sync.ServerSeq = d.ServerSeq
	out.Sync.LastSyncAt = d.LastSync
	out.Storage.Used, out.Storage.Quota = d.Used, d.Quota
	return out
}

// AdminListAuditLogs 实现 GET /api/admin/v1/audit-logs。
func (h *Handler) AdminListAuditLogs(ctx context.Context, req apigen.AdminListAuditLogsRequestObject) (apigen.AdminListAuditLogsResponseObject, error) {
	ctx, _, _, err := request(ctx)
	if err != nil {
		return nil, err
	}
	page, size := pageParams(req.Params.Page, req.Params.PageSize)
	f := AuditFilter{AdminID: req.Params.AdminId, Since: req.Params.From, Until: req.Params.To, Page: page, Size: size}
	if req.Params.Action != nil {
		a := string(*req.Params.Action)
		f.Action = &a
	}
	logs, total, err := h.svc.ListAuditLogs(ctx, f)
	if err != nil {
		return nil, err
	}
	out := make([]apigen.AuditLog, len(logs))
	for i, l := range logs {
		out[i] = auditLog(l)
	}
	page, size = pageOf(page, size)
	b := base(ctx)
	return apigen.AdminListAuditLogs200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: out,
		Meta: apigen.PageMeta{Total: total, Page: page, Limit: size}}, nil
}

// AdminListAdmins 实现 GET /api/admin/v1/admins。
func (h *Handler) AdminListAdmins(ctx context.Context, _ apigen.AdminListAdminsRequestObject) (apigen.AdminListAdminsResponseObject, error) {
	ctx, p, _, err := request(ctx)
	if err != nil {
		return nil, err
	}
	list, err := h.svc.ListAdmins(ctx, p)
	if err != nil {
		return nil, err
	}
	out := make([]apigen.AdminProfile, len(list))
	for i, a := range list {
		out[i] = profile(a)
	}
	b := base(ctx)
	return apigen.AdminListAdmins200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: out}, nil
}

// AdminCreateAdmin 实现 POST /api/admin/v1/admins。
func (h *Handler) AdminCreateAdmin(ctx context.Context, req apigen.AdminCreateAdminRequestObject) (apigen.AdminCreateAdminResponseObject, error) {
	ctx, p, m, err := request(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	a, err := h.svc.CreateAdmin(ctx, &p, req.Body.Username, string(req.Body.Role), req.Body.Password, m)
	if err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AdminCreateAdmin201JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: profile(a)}, nil
}

// AdminUpdateAdmin 实现 PATCH /api/admin/v1/admins/{adminId}。
func (h *Handler) AdminUpdateAdmin(ctx context.Context, req apigen.AdminUpdateAdminRequestObject) (apigen.AdminUpdateAdminResponseObject, error) {
	ctx, p, m, err := request(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	var role *string
	if req.Body.Role != nil {
		r := string(*req.Body.Role)
		role = &r
	}
	a, err := h.svc.UpdateAdmin(ctx, p, req.AdminId, role, req.Body.Disabled, m)
	if err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AdminUpdateAdmin200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: profile(a)}, nil
}

// AdminResetPassword 实现 POST /api/admin/v1/admins/{adminId}/password。
func (h *Handler) AdminResetPassword(ctx context.Context, req apigen.AdminResetPasswordRequestObject) (apigen.AdminResetPasswordResponseObject, error) {
	ctx, p, m, err := request(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errEmptyBody
	}
	if err := h.svc.ResetPassword(ctx, &p, req.AdminId, req.Body.Password, m); err != nil {
		return nil, err
	}
	b := base(ctx)
	return apigen.AdminResetPassword200JSONResponse{Success: b.Success, RequestId: b.RequestId, Data: apigen.Ack{Ok: true}}, nil
}

func auditLog(l dbgen.AdminAuditLog) apigen.AuditLog {
	detail := map[string]any{}
	_ = json.Unmarshal(l.Detail, &detail)
	return apigen.AuditLog{
		Id: l.ID, AdminId: l.AdminID, Username: l.Username, Action: apigen.AuditAction(l.Action),
		TargetType: l.TargetType, TargetId: l.TargetID, Ip: l.Ip, UserAgent: l.UserAgent,
		Detail: detail, CreatedAt: l.CreatedAt,
	}
}
