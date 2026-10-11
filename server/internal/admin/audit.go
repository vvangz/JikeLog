package admin

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
)

// 审计操作（与接口中的 AuditAction 一致）。
const (
	ActionLogin          = "login"
	ActionLoginFailed    = "login_failed"
	ActionLogout         = "logout"
	ActionViewDashboard  = "view_dashboard"
	ActionListUsers      = "list_users"
	ActionViewUser       = "view_user"
	ActionChangePassword = "change_password"
	ActionCreateAdmin    = "create_admin"
	ActionUpdateAdmin    = "update_admin"
	ActionResetPassword  = "reset_password"
)

// maxUserAgent 为审计日志中 User-Agent 的最大长度。
const maxUserAgent = 300

type auditEntry struct {
	adminID    *uuid.UUID
	username   string
	action     string
	targetType string
	targetID   string
	meta       Meta
	detail     map[string]any
}

// auditAs 以已登录的管理员身份记录一条审计日志。
func (s *Service) auditAs(ctx context.Context, p Principal, action string, m Meta, targetType, targetID string, detail map[string]any) {
	id := p.AdminID
	s.audit(ctx, auditEntry{adminID: &id, username: p.Username, action: action, meta: m,
		targetType: targetType, targetID: targetID, detail: detail})
}

// audit 写入一条审计日志。写入失败只记录错误日志，不影响操作本身（审计表故障时管理员仍能登录排查）。
func (s *Service) audit(ctx context.Context, e auditEntry) {
	detail, err := json.Marshal(e.detail)
	if err != nil || e.detail == nil {
		detail = []byte("{}")
	}
	ua := e.meta.UserAgent
	if len(ua) > maxUserAgent {
		ua = ua[:maxUserAgent]
	}
	id, err := uuid.NewV7()
	if err == nil {
		err = s.d.Tx.Queries().InsertAuditLog(ctx, dbgen.InsertAuditLogParams{
			ID: id, AdminID: e.adminID, Username: e.username, Action: e.action,
			TargetType: e.targetType, TargetID: e.targetID, Ip: e.meta.IP, UserAgent: ua,
			Detail: detail, CreatedAt: s.d.Now(),
		})
	}
	if err != nil {
		s.d.Logger.ErrorContext(ctx, "write admin audit log failed", "action", e.action, "admin", e.username, "error", err)
	}
}

// AuditFilter 为审计日志的筛选条件。
type AuditFilter struct {
	AdminID *uuid.UUID
	Action  *string
	Since   *time.Time
	Until   *time.Time
	Page    int
	Size    int
}

// ListAuditLogs 返回一页审计日志（新的在前）与总条数。
func (s *Service) ListAuditLogs(ctx context.Context, f AuditFilter) ([]dbgen.AdminAuditLog, int64, error) {
	page, size := pageOf(f.Page, f.Size)
	limit, offset := limitOffset(page, size)
	q := s.d.Tx.Queries()
	logs, err := q.ListAuditLogs(ctx, dbgen.ListAuditLogsParams{
		AdminID: f.AdminID, Action: f.Action, Since: f.Since, Until: f.Until,
		MaxRows: limit, Skip: offset,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("查询审计日志失败: %w", err)
	}
	total, err := q.CountAuditLogs(ctx, dbgen.CountAuditLogsParams{
		AdminID: f.AdminID, Action: f.Action, Since: f.Since, Until: f.Until,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("统计审计日志失败: %w", err)
	}
	return logs, total, nil
}

// 分页参数：页码从 1 开始，每页默认 20 条、最多 100 条；页码最多到 maxPage，避免过深的 OFFSET。
const (
	defaultPageSize = 20
	maxPageSize     = 100
	maxPage         = 1000
)

// limitOffset 换算为查询的 LIMIT 与 OFFSET（页码与每页条数已由 pageOf 限定范围，不会溢出）。
func limitOffset(page, size int) (int32, int32) {
	return int32(size), int32((page - 1) * size) //nolint:gosec // 范围已由 pageOf 限定
}

func pageOf(page, size int) (int, int) {
	if size <= 0 {
		size = defaultPageSize
	}
	size = min(size, maxPageSize)
	page = min(max(page, 1), maxPage)
	return page, size
}
