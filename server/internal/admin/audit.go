package admin

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
	"unicode"

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
	ActionListAuditLogs  = "list_audit_logs"
	ActionListAdmins     = "list_admins"
)

// 审计日志中各字段的最大字符数。
const (
	maxUserAgent = 300
	maxIP        = 64
	maxDetail    = 100
)

type auditEntry struct {
	adminID    *uuid.UUID
	username   string
	action     string
	targetType string
	targetID   string
	meta       Meta
	detail     map[string]any
}

// auditAs 以已登录的管理员身份记录一条审计日志，失败时返回错误：查看与管理操作必须有审计记录才能执行。
func (s *Service) auditAs(ctx context.Context, p Principal, action string, m Meta, targetType, targetID string, detail map[string]any) error {
	id := p.AdminID
	return s.writeAudit(ctx, auditEntry{adminID: &id, username: p.Username, action: action, meta: m,
		targetType: targetType, targetID: targetID, detail: detail})
}

// audit 写入登录、退出等审计日志。写入失败只记录错误日志，不影响登录本身（审计表故障时管理员仍能登录排查）。
func (s *Service) audit(ctx context.Context, e auditEntry) {
	if err := s.writeAudit(ctx, e); err != nil {
		s.d.Logger.ErrorContext(ctx, "write admin audit log failed", "action", e.action, "error", err)
	}
}

func (s *Service) writeAudit(ctx context.Context, e auditEntry) error {
	detail := make(map[string]any, len(e.detail))
	for k, v := range e.detail {
		if str, ok := v.(string); ok {
			v = clean(str, maxDetail)
		}
		detail[k] = v
	}
	raw, err := json.Marshal(detail)
	if err != nil {
		return fmt.Errorf("编码审计说明失败: %w", err)
	}
	id, err := uuid.NewV7()
	if err != nil {
		return err
	}
	err = s.d.Tx.Queries().InsertAuditLog(ctx, dbgen.InsertAuditLogParams{
		ID: id, AdminID: e.adminID, Username: auditUsername(e.username), Action: e.action,
		TargetType: e.targetType, TargetID: e.targetID, Ip: clean(e.meta.IP, maxIP),
		UserAgent: clean(e.meta.UserAgent, maxUserAgent), Detail: raw, CreatedAt: s.d.Now(),
	})
	if err != nil {
		return fmt.Errorf("写入审计日志失败: %w", err)
	}
	return nil
}

// clean 清理来自请求的字符串：替换非法 UTF-8、去掉 NUL 与控制字符，按字符截断。
// 这些字符会让 PostgreSQL 拒绝写入，攻击者可借此让审计日志写不进去。
func clean(s string, maxRunes int) string {
	s = strings.ToValidUTF8(s, "\uFFFD")
	s = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, s)
	if r := []rune(s); len(r) > maxRunes {
		s = string(r[:maxRunes])
	}
	return s
}

// invalidUsername 为登录时输入了不合规用户名（可能是把密码输进了用户名框）时在审计日志中的记录。
const invalidUsername = "(无效用户名)"

// auditUsername 只记录合规的用户名；不合规的输入可能是误输的密码，不能写进审计日志。
func auditUsername(name string) string {
	if name == cliUser || usernamePattern.MatchString(name) {
		return name
	}
	return invalidUsername
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

// ListAuditLogs 返回一页审计日志（新的在前）与总条数。查看审计日志本身也会记录（其中有其他管理员的 IP 等）。
func (s *Service) ListAuditLogs(ctx context.Context, p Principal, f AuditFilter, m Meta) ([]dbgen.AdminAuditLog, int64, error) {
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
	detail := map[string]any{"page": page}
	if f.Action != nil {
		detail["action"] = *f.Action
	}
	if err := s.auditAs(ctx, p, ActionListAuditLogs, m, "", "", detail); err != nil {
		return nil, 0, err
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
