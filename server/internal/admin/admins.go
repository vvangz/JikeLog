package admin

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"sync"
	"unicode"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

const (
	minPasswordLen = 10
	maxPasswordLen = 128
)

var usernamePattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]{3,19}$`)

// checkPassword 校验管理员密码：至少 10 位，同时包含字母和数字。
func checkPassword(pw string) error {
	if n := len([]rune(pw)); n < minPasswordLen || n > maxPasswordLen {
		return httpx.Validation(map[string]string{"password": "密码长度为 10 到 128 位"}) //nolint:gosec // 校验提示，不是凭据
	}
	var letter, digit bool
	for _, r := range pw {
		letter = letter || unicode.IsLetter(r)
		digit = digit || unicode.IsDigit(r)
	}
	if !letter || !digit {
		return httpx.Validation(map[string]string{"password": "密码需要同时包含字母和数字"}) //nolint:gosec // 校验提示，不是凭据
	}
	return nil
}

func checkRole(role string) error {
	if role != RoleSuperAdmin && role != RoleViewer {
		return httpx.Validation(map[string]string{"role": "角色只能是 super_admin 或 viewer"})
	}
	return nil
}

// dummyHash 用于用户名不存在时执行一次同样耗时的校验，避免通过响应时间判断用户名是否存在。
var (
	dummyOnce sync.Once
	dummyHash string
)

func (s *Service) dummy(ctx context.Context) string {
	dummyOnce.Do(func() {
		dummyHash, _ = s.d.Hasher.Hash(ctx, "jikelog-dummy-password-1")
	})
	return dummyHash
}

// requireSuper 只允许超级管理员。
func requireSuper(p Principal) error {
	if p.Role != RoleSuperAdmin {
		return errForbidden
	}
	return nil
}

// ListAdmins 返回全部管理员（仅超级管理员）。
func (s *Service) ListAdmins(ctx context.Context, p Principal) ([]dbgen.AdminUser, error) {
	if err := requireSuper(p); err != nil {
		return nil, err
	}
	list, err := s.d.Tx.Queries().ListAdmins(ctx)
	if err != nil {
		return nil, fmt.Errorf("查询管理员失败: %w", err)
	}
	return list, nil
}

// CreateAdmin 新建管理员。p 为 nil 表示由命令行创建（第一个超级管理员），此时不要求首次登录改密码。
func (s *Service) CreateAdmin(ctx context.Context, p *Principal, username, role, password string, m Meta) (dbgen.AdminUser, error) {
	if p != nil {
		if err := requireSuper(*p); err != nil {
			return dbgen.AdminUser{}, err
		}
	}
	if !usernamePattern.MatchString(username) {
		return dbgen.AdminUser{}, httpx.Validation(map[string]string{"username": "用户名为 4–20 位字母、数字或下划线，以字母开头"})
	}
	if err := checkRole(role); err != nil {
		return dbgen.AdminUser{}, err
	}
	if err := checkPassword(password); err != nil {
		return dbgen.AdminUser{}, err
	}
	hash, err := s.d.Hasher.Hash(ctx, password)
	if err != nil {
		return dbgen.AdminUser{}, err
	}
	id, err := uuid.NewV7()
	if err != nil {
		return dbgen.AdminUser{}, err
	}
	a, err := s.d.Tx.Queries().CreateAdmin(ctx, dbgen.CreateAdminParams{
		ID: id, Username: username, PasswordHash: hash, Role: role, MustChangePassword: p != nil, Now: s.d.Now(),
	})
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return dbgen.AdminUser{}, errUsernameTaken
	}
	if err != nil {
		return dbgen.AdminUser{}, fmt.Errorf("创建管理员失败: %w", err)
	}
	if p != nil {
		s.auditAs(ctx, *p, ActionCreateAdmin, m, "admin", a.ID.String(), map[string]any{"username": username, "role": role})
	}
	return a, nil
}

// UpdateAdmin 修改其他管理员的角色或停用状态（仅超级管理员）。不能修改自己，也不能停用或降级最后一个超级管理员。
func (s *Service) UpdateAdmin(ctx context.Context, p Principal, id uuid.UUID, role *string, disabled *bool, m Meta) (dbgen.AdminUser, error) {
	if err := requireSuper(p); err != nil {
		return dbgen.AdminUser{}, err
	}
	if id == p.AdminID {
		return dbgen.AdminUser{}, httpx.Validation(map[string]string{"adminId": "不能修改自己的角色或停用自己"})
	}
	if role != nil {
		if err := checkRole(*role); err != nil {
			return dbgen.AdminUser{}, err
		}
	}
	var out dbgen.AdminUser
	err := s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		cur, err := q.GetAdminForUpdate(ctx, id)
		if db.IsNotFound(err) {
			return errNotFound
		}
		if err != nil {
			return err
		}
		next := cur
		if role != nil {
			next.Role = *role
		}
		if disabled != nil {
			next.Disabled = *disabled
		}
		// 这个超级管理员被降级或停用后，必须还有其他启用的超级管理员
		if cur.Role == RoleSuperAdmin && !cur.Disabled && (next.Role != RoleSuperAdmin || next.Disabled) {
			n, err := q.CountActiveSuperAdmins(ctx)
			if err != nil {
				return err
			}
			if n <= 1 {
				return errLastSuperAdmin
			}
		}
		now := s.d.Now()
		if out, err = q.UpdateAdmin(ctx, dbgen.UpdateAdminParams{ID: id, Role: next.Role, Disabled: next.Disabled, Now: now}); err != nil {
			return err
		}
		if next.Disabled && !cur.Disabled {
			return q.RevokeAdminSessions(ctx, dbgen.RevokeAdminSessionsParams{AdminID: id, Now: &now})
		}
		return nil
	})
	if err != nil {
		var he *httpx.Error
		if errors.As(err, &he) {
			return dbgen.AdminUser{}, err
		}
		return dbgen.AdminUser{}, fmt.Errorf("修改管理员失败: %w", err)
	}
	s.auditAs(ctx, p, ActionUpdateAdmin, m, "admin", id.String(), map[string]any{"role": out.Role, "disabled": out.Disabled})
	return out, nil
}

// ResetPassword 重置其他管理员的密码（仅超级管理员）：对方会话全部失效，下次登录必须修改密码。
// p 为 nil 表示由命令行重置（找回超级管理员），此时不要求改密码。
func (s *Service) ResetPassword(ctx context.Context, p *Principal, id uuid.UUID, password string, m Meta) error {
	if p != nil {
		if err := requireSuper(*p); err != nil {
			return err
		}
		if id == p.AdminID {
			return httpx.Validation(map[string]string{"adminId": "修改自己的密码请使用\"修改密码\""})
		}
	}
	if err := checkPassword(password); err != nil {
		return err
	}
	hash, err := s.d.Hasher.Hash(ctx, password)
	if err != nil {
		return err
	}
	err = s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		if _, err := q.GetAdminForUpdate(ctx, id); err != nil {
			if db.IsNotFound(err) {
				return errNotFound
			}
			return err
		}
		now := s.d.Now()
		if err := q.SetAdminPassword(ctx, dbgen.SetAdminPasswordParams{ID: id, PasswordHash: hash, MustChangePassword: p != nil, Now: now}); err != nil {
			return err
		}
		return q.RevokeAdminSessions(ctx, dbgen.RevokeAdminSessionsParams{AdminID: id, Now: &now})
	})
	if err != nil {
		var he *httpx.Error
		if errors.As(err, &he) {
			return err
		}
		return fmt.Errorf("重置密码失败: %w", err)
	}
	if p != nil {
		s.auditAs(ctx, *p, ActionResetPassword, m, "admin", id.String(), nil)
	}
	return nil
}

// AdminByUsername 按用户名查找管理员（命令行使用）。
func (s *Service) AdminByUsername(ctx context.Context, username string) (dbgen.AdminUser, error) {
	a, err := s.d.Tx.Queries().GetAdminByUsername(ctx, username)
	if db.IsNotFound(err) {
		return dbgen.AdminUser{}, errNotFound
	}
	return a, err
}
