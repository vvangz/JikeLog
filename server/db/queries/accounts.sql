-- 账号、设备与设置相关查询，由 sqlc 生成到 internal/dbgen（scripts/gen-db.sh）。

-- name: CreateUser :one
INSERT INTO users (id, username, nickname, phone, password_hash)
VALUES (@id, @username, @nickname, sqlc.narg(phone), @password_hash)
RETURNING *;

-- name: GetUserByID :one
SELECT * FROM users WHERE id = @id;

-- name: GetUserByUsername :one
SELECT * FROM users WHERE lower(username) = lower(@username);

-- name: GetUserByPhone :one
SELECT * FROM users WHERE phone = @phone::text;

-- name: UpdateUserPassword :exec
UPDATE users
SET password_hash = @password_hash, password_changed_at = now(), updated_at = now()
WHERE id = @id;

-- name: UpdateUserPasswordHash :exec
-- 仅升级哈希参数（密码本身未变），不更新 password_changed_at；旧哈希不符说明密码已被并发修改，放弃升级。
UPDATE users SET password_hash = @password_hash WHERE id = @id AND password_hash = @old_hash;

-- name: UpdateUserPhone :exec
UPDATE users SET phone = sqlc.narg(phone), updated_at = now() WHERE id = @id;

-- name: UpdateUserNickname :one
UPDATE users SET nickname = @nickname, updated_at = now() WHERE id = @id
RETURNING *;

-- name: DeleteUser :execrows
DELETE FROM users WHERE id = @id;

-- name: UpsertDevice :one
-- 同一安装实例再次登录同一账号时复用设备行：重新激活、更新设备信息并换发 Refresh Token。
INSERT INTO devices (
    id, user_id, installation_id, platform, model, os_version, app_version,
    refresh_hash, refresh_rotated_at, refresh_expires_at, last_ip, tokens_valid_after
) VALUES (
    @id, @user_id, @installation_id, @platform, @model, @os_version, @app_version,
    @refresh_hash, @now::timestamptz, @refresh_expires_at, @last_ip, @now::timestamptz
)
ON CONFLICT (user_id, installation_id) DO UPDATE SET
    platform           = EXCLUDED.platform,
    model              = EXCLUDED.model,
    os_version         = EXCLUDED.os_version,
    app_version        = EXCLUDED.app_version,
    refresh_hash       = EXCLUDED.refresh_hash,
    refresh_prev_hash  = NULL,
    refresh_rotated_at = EXCLUDED.refresh_rotated_at,
    refresh_expires_at = EXCLUDED.refresh_expires_at,
    last_ip            = EXCLUDED.last_ip,
    last_active_at     = now(),
    -- 新会话：此前签发给该设备的令牌全部作废
    tokens_valid_after = EXCLUDED.tokens_valid_after,
    revoked_at         = NULL
RETURNING *;

-- name: GetDeviceByRefreshHashForUpdate :one
-- 同时匹配当前与上一枚 Refresh Token，由调用方区分正常刷新、并发宽限与重放。
SELECT * FROM devices
WHERE (refresh_hash = @hash OR refresh_prev_hash = @hash) AND revoked_at IS NULL
LIMIT 1
FOR UPDATE;

-- name: SetDeviceRefresh :exec
UPDATE devices SET
    refresh_hash       = @refresh_hash,
    refresh_prev_hash  = sqlc.narg(refresh_prev_hash),
    refresh_rotated_at = @refresh_rotated_at,
    refresh_expires_at = @refresh_expires_at,
    last_ip            = @last_ip,
    last_active_at     = now()
WHERE id = @id;

-- name: GetDeviceByID :one
SELECT * FROM devices WHERE id = @id;

-- name: GetDeviceSession :one
-- 认证中间件每个请求调用一次（主键查询）。
SELECT user_id, tokens_valid_after FROM devices WHERE id = @id AND revoked_at IS NULL;

-- name: ListActiveDevices :many
SELECT * FROM devices
WHERE user_id = @user_id AND revoked_at IS NULL
ORDER BY last_active_at DESC;

-- name: RevokeDevice :many
UPDATE devices
SET revoked_at = @now::timestamptz, tokens_valid_after = @now::timestamptz, refresh_hash = NULL, refresh_prev_hash = NULL
WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL
RETURNING id;

-- name: RevokeOtherDevices :many
UPDATE devices
SET revoked_at = @now::timestamptz, tokens_valid_after = @now::timestamptz, refresh_hash = NULL, refresh_prev_hash = NULL
WHERE user_id = @user_id AND id <> @keep_id AND revoked_at IS NULL
RETURNING id;

-- name: RevokeAllDevices :many
UPDATE devices
SET revoked_at = @now::timestamptz, tokens_valid_after = @now::timestamptz, refresh_hash = NULL, refresh_prev_hash = NULL
WHERE user_id = @user_id AND revoked_at IS NULL
RETURNING id;

-- name: CreateDefaultSettings :exec
INSERT INTO user_settings (user_id) VALUES (@user_id) ON CONFLICT (user_id) DO NOTHING;

-- name: GetSettings :one
SELECT * FROM user_settings WHERE user_id = @user_id;

-- name: UpdateSettings :one
UPDATE user_settings SET
    theme_mode        = @theme_mode,
    font_scale        = @font_scale,
    default_reminders = @default_reminders,
    week_start        = @week_start,
    updated_at        = now()
WHERE user_id = @user_id
RETURNING *;
