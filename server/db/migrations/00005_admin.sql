-- Web 管理后台（ADR-011）：独立的管理员账号、会话与审计日志。

-- +goose Up
CREATE TABLE admin_users (
    id                  uuid PRIMARY KEY,
    username            text        NOT NULL,
    password_hash       text        NOT NULL,
    -- super_admin 可以管理管理员账号；viewer 只能查看
    role                text        NOT NULL,
    disabled            boolean     NOT NULL DEFAULT false,
    -- 新建或被重置密码后，第一次登录必须先修改密码
    must_change_password boolean    NOT NULL DEFAULT true,
    -- 连续登录失败次数与锁定截止时刻
    failed_logins       integer     NOT NULL DEFAULT 0,
    locked_until        timestamptz,
    last_login_at       timestamptz,
    password_changed_at timestamptz NOT NULL,
    created_at          timestamptz NOT NULL,
    updated_at          timestamptz NOT NULL,
    CONSTRAINT admin_users_role CHECK (role IN ('super_admin', 'viewer')),
    CONSTRAINT admin_users_username_format CHECK (username ~ '^[A-Za-z][A-Za-z0-9_]{3,19}$')
);

CREATE UNIQUE INDEX admin_users_username_key ON admin_users (lower(username));

-- 管理员会话：Refresh Token 只存哈希，每次刷新轮换；会话最长 12 小时
CREATE TABLE admin_sessions (
    id           uuid PRIMARY KEY,
    admin_id     uuid        NOT NULL REFERENCES admin_users (id) ON DELETE CASCADE,
    refresh_hash bytea       NOT NULL,
    created_at   timestamptz NOT NULL,
    expires_at   timestamptz NOT NULL,
    last_used_at timestamptz NOT NULL,
    revoked_at   timestamptz
);

CREATE UNIQUE INDEX admin_sessions_refresh_key ON admin_sessions (refresh_hash);
CREATE INDEX admin_sessions_admin_idx ON admin_sessions (admin_id);

-- 审计日志：只追加，不提供修改与删除
CREATE TABLE admin_audit_logs (
    id          uuid PRIMARY KEY,
    -- 登录失败时可能没有对应的管理员（用户名不存在）
    admin_id    uuid REFERENCES admin_users (id) ON DELETE SET NULL,
    -- 当时的用户名（账号删除后仍可追溯；登录失败时为尝试的用户名）
    username    text        NOT NULL,
    action      text        NOT NULL,
    -- 操作对象：user / admin，及其 ID
    target_type text        NOT NULL DEFAULT '',
    target_id   text        NOT NULL DEFAULT '',
    ip          text        NOT NULL DEFAULT '',
    user_agent  text        NOT NULL DEFAULT '',
    -- 少量说明（如搜索关键词、修改的字段），不含用户内容
    detail      jsonb       NOT NULL DEFAULT '{}',
    created_at  timestamptz NOT NULL
);

CREATE INDEX admin_audit_logs_created_idx ON admin_audit_logs (created_at DESC);
CREATE INDEX admin_audit_logs_admin_idx ON admin_audit_logs (admin_id, created_at DESC);

-- 仪表盘与用户列表按最后活跃时间统计
CREATE INDEX devices_last_active_idx ON devices (last_active_at);
CREATE INDEX users_created_idx ON users (created_at);

-- +goose Down
DROP INDEX users_created_idx;
DROP INDEX devices_last_active_idx;
DROP TABLE admin_audit_logs;
DROP TABLE admin_sessions;
DROP TABLE admin_users;
