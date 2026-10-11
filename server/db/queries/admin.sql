-- Web 管理后台（ADR-011），由 sqlc 生成到 internal/dbgen（scripts/gen-db.sh）。

-- ───────────── 管理员账号 ─────────────

-- name: CreateAdmin :one
INSERT INTO admin_users (id, username, password_hash, role, must_change_password, password_changed_at, created_at, updated_at)
VALUES (@id, @username, @password_hash, @role, @must_change_password, @now, @now, @now)
RETURNING *;

-- name: GetAdmin :one
SELECT * FROM admin_users WHERE id = @id;

-- name: GetAdminForUpdate :one
SELECT * FROM admin_users WHERE id = @id FOR UPDATE;

-- name: GetAdminByUsername :one
SELECT * FROM admin_users WHERE lower(username) = lower(@username);

-- name: ListAdmins :many
SELECT * FROM admin_users ORDER BY created_at;

-- name: CountActiveSuperAdmins :one
SELECT count(*) FROM admin_users WHERE role = 'super_admin' AND NOT disabled;

-- name: UpdateAdmin :one
UPDATE admin_users SET role = @role, disabled = @disabled, updated_at = @now WHERE id = @id RETURNING *;

-- name: SetAdminPassword :exec
-- 修改或重置密码。must_change_password 为 true 表示下次登录必须先改密码（被他人重置时）。
UPDATE admin_users
SET password_hash = @password_hash, must_change_password = @must_change_password,
    password_changed_at = @now, updated_at = @now
WHERE id = @id;

-- name: RecordAdminLogin :exec
UPDATE admin_users SET last_login_at = @now WHERE id = @id;

-- name: LockAdminRoles :exec
-- 修改管理员角色或停用状态时串行执行，保证"至少一个启用的超级管理员"不会被并发修改打破（事务结束时释放）。
SELECT pg_advisory_xact_lock(7243001);

-- ───────────── 会话 ─────────────

-- name: CreateAdminSession :exec
INSERT INTO admin_sessions (id, admin_id, refresh_hash, created_at, expires_at, last_used_at)
VALUES (@id, @admin_id, @refresh_hash, @now, @expires_at, @now);

-- name: GetAdminSessionByHashForUpdate :one
SELECT * FROM admin_sessions WHERE refresh_hash = @refresh_hash FOR UPDATE;

-- name: RotateAdminSession :exec
UPDATE admin_sessions
SET prev_refresh_hash = refresh_hash, refresh_hash = @refresh_hash, rotated_at = @now, last_used_at = @now
WHERE id = @id;

-- name: GetAdminSessionByPrevHash :one
SELECT * FROM admin_sessions WHERE prev_refresh_hash = @prev_refresh_hash;

-- name: RevokeAdminSession :exec
UPDATE admin_sessions SET revoked_at = @now WHERE id = @id AND revoked_at IS NULL;

-- name: RevokeAdminSessions :exec
-- 修改或重置密码、停用账号时让该管理员的全部会话失效。
UPDATE admin_sessions SET revoked_at = @now WHERE admin_id = @admin_id AND revoked_at IS NULL;

-- name: RevokeOtherAdminSessions :exec
-- 修改自己的密码时，其他会话失效，当前会话保留。
UPDATE admin_sessions SET revoked_at = @now WHERE admin_id = @admin_id AND id <> @keep AND revoked_at IS NULL;

-- name: GetAdminForSession :one
-- Access Token 只在会话仍有效时可用：退出、改密码、停用后立即失效。角色与是否须改密码以数据库为准。
SELECT a.id, a.username, a.role, a.must_change_password
FROM admin_sessions s JOIN admin_users a ON a.id = s.admin_id
WHERE s.id = @session_id AND s.admin_id = @admin_id AND s.revoked_at IS NULL AND s.expires_at > @now AND NOT a.disabled;

-- name: PruneAdminSessions :execrows
DELETE FROM admin_sessions WHERE expires_at < @before;

-- ───────────── 审计日志 ─────────────

-- name: InsertAuditLog :exec
INSERT INTO admin_audit_logs (id, admin_id, username, action, target_type, target_id, ip, user_agent, detail, created_at)
VALUES (@id, sqlc.narg(admin_id), @username, @action, @target_type, @target_id, @ip, @user_agent, @detail, @created_at);

-- name: ListAuditLogs :many
SELECT * FROM admin_audit_logs
WHERE (sqlc.narg(admin_id)::uuid IS NULL OR admin_id = sqlc.narg(admin_id))
  AND (sqlc.narg(action)::text IS NULL OR action = sqlc.narg(action))
  AND (sqlc.narg(since)::timestamptz IS NULL OR created_at >= sqlc.narg(since))
  AND (sqlc.narg(until)::timestamptz IS NULL OR created_at < sqlc.narg(until))
ORDER BY created_at DESC, id DESC
LIMIT @max_rows OFFSET @skip;

-- name: CountAuditLogs :one
SELECT count(*) FROM admin_audit_logs
WHERE (sqlc.narg(admin_id)::uuid IS NULL OR admin_id = sqlc.narg(admin_id))
  AND (sqlc.narg(action)::text IS NULL OR action = sqlc.narg(action))
  AND (sqlc.narg(since)::timestamptz IS NULL OR created_at >= sqlc.narg(since))
  AND (sqlc.narg(until)::timestamptz IS NULL OR created_at < sqlc.narg(until));

-- ───────────── 仪表盘 ─────────────

-- name: AdminUserStats :one
-- 用户总数、某时刻之后新增的用户数，以及各时间窗口内有设备活动的用户数。
SELECT
    (SELECT count(*) FROM users)::bigint AS total,
    (SELECT count(*) FROM users WHERE created_at >= @today::timestamptz)::bigint AS new_today,
    (SELECT count(DISTINCT user_id) FROM devices WHERE last_active_at >= @today::timestamptz)::bigint AS active_today,
    (SELECT count(DISTINCT user_id) FROM devices WHERE last_active_at >= @week::timestamptz)::bigint AS active_week,
    (SELECT count(DISTINCT user_id) FROM devices WHERE last_active_at >= @month::timestamptz)::bigint AS active_month,
    (SELECT COALESCE(SUM(size), 0) FROM attachments WHERE status <> 'deleted')::bigint AS storage_bytes;

-- name: AdminDailyNewUsers :many
-- 每天新增的用户数（按给定时区的日期）。
SELECT to_char(created_at AT TIME ZONE @tz::text, 'YYYY-MM-DD')::text AS day, count(*)::bigint AS users
FROM users
WHERE created_at >= @since
GROUP BY day
ORDER BY day;

-- name: AdminPlatformStats :many
-- 最近活跃的已登录设备的平台分布。
SELECT platform, count(*)::bigint AS devices
FROM devices
WHERE revoked_at IS NULL AND last_active_at >= @since
GROUP BY platform
ORDER BY devices DESC;

-- ───────────── 用户 ─────────────

-- name: AdminListUsers :many
-- 用户列表：按用户名、昵称或手机号后几位搜索，新注册的在前。
SELECT
    u.id, u.username, u.nickname, u.phone, u.created_at,
    -- 没有设备（全部退出且被清理）时以注册时间代替
    COALESCE((SELECT max(d.last_active_at) FROM devices d WHERE d.user_id = u.id), u.created_at)::timestamptz AS last_active_at,
    (SELECT count(*) FROM devices d WHERE d.user_id = u.id AND d.revoked_at IS NULL)::bigint AS device_count,
    (SELECT COALESCE(SUM(a.size), 0) FROM attachments a WHERE a.user_id = u.id AND a.status <> 'deleted')::bigint AS storage_bytes
FROM users u
WHERE @query::text = ''
   OR u.username ILIKE '%' || @query::text || '%'
   OR u.nickname ILIKE '%' || @query::text || '%'
   OR (@phone_suffix::text <> '' AND u.phone LIKE '%' || @phone_suffix::text)
ORDER BY u.created_at DESC, u.id
LIMIT @max_rows OFFSET @skip;

-- name: AdminCountUsers :one
SELECT count(*) FROM users u
WHERE @query::text = ''
   OR u.username ILIKE '%' || @query::text || '%'
   OR u.nickname ILIKE '%' || @query::text || '%'
   OR (@phone_suffix::text <> '' AND u.phone LIKE '%' || @phone_suffix::text);

-- name: AdminListUserDevices :many
SELECT id, platform, model, os_version, app_version, last_active_at, created_at, revoked_at,
       local_reminders, last_ack_seq, (push_token IS NOT NULL)::boolean AS push_enabled
FROM devices
WHERE user_id = @user_id
ORDER BY revoked_at IS NOT NULL, last_active_at DESC;

-- name: AdminLastSync :one
-- 最后一次有记录写入服务端的时间（不含内容）；没有任何记录时查不到。
-- 按同步序号取最后一条（有索引），每次写入都会推进序号并更新 updated_at
SELECT updated_at FROM records WHERE user_id = @user_id ORDER BY server_seq DESC LIMIT 1;
