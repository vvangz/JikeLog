-- 账号、设备（登录会话）与用户设置。
-- 所有 ID 由服务端生成 UUIDv7；时间统一为 timestamptz。

-- +goose Up
CREATE TABLE users (
    id                  uuid PRIMARY KEY,
    username            text        NOT NULL,
    nickname            text        NOT NULL DEFAULT '',
    -- E.164 格式（+8613812345678）；一个手机号只能绑定一个账号
    phone               text,
    password_hash       text        NOT NULL,
    password_changed_at timestamptz NOT NULL DEFAULT now(),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_username_format CHECK (username ~ '^[A-Za-z][A-Za-z0-9_]{3,19}$'),
    CONSTRAINT users_nickname_length CHECK (char_length(nickname) <= 20),
    CONSTRAINT users_phone_format CHECK (phone IS NULL OR phone ~ '^\+[1-9][0-9]{6,14}$')
);

-- 用户名不区分大小写唯一
CREATE UNIQUE INDEX users_username_key ON users (lower(username));
CREATE UNIQUE INDEX users_phone_key ON users (phone) WHERE phone IS NOT NULL;

-- 一行代表某个账号在某台设备上的登录会话。同一安装实例重复登录同一账号时复用该行，
-- 保证后续同步游标（last_ack_seq）稳定。
CREATE TABLE devices (
    id                  uuid PRIMARY KEY,
    user_id             uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- 客户端安装时生成并持久化的标识
    installation_id     text        NOT NULL,
    platform            text        NOT NULL,
    model               text        NOT NULL DEFAULT '',
    os_version          text        NOT NULL DEFAULT '',
    app_version         text        NOT NULL DEFAULT '',
    -- 当前有效 Refresh Token 的 SHA-256；上一枚用于并发刷新的宽限与重放检测
    refresh_hash        bytea,
    refresh_prev_hash   bytea,
    refresh_rotated_at  timestamptz,
    refresh_expires_at  timestamptz,
    last_ip             text        NOT NULL DEFAULT '',
    last_active_at      timestamptz NOT NULL DEFAULT now(),
    created_at          timestamptz NOT NULL DEFAULT now(),
    -- 只接受签发时间不早于该时刻的 Access Token：重新登录与下线时都会更新，
    -- 使下线与数据库事务同时生效，且不依赖缓存
    tokens_valid_after  timestamptz NOT NULL DEFAULT now(),
    -- 非空表示已退出或被踢下线
    revoked_at          timestamptz,
    CONSTRAINT devices_platform CHECK (platform IN ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    CONSTRAINT devices_installation_length CHECK (char_length(installation_id) BETWEEN 8 AND 64)
);

CREATE UNIQUE INDEX devices_user_installation_key ON devices (user_id, installation_id);
CREATE UNIQUE INDEX devices_refresh_hash_key ON devices (refresh_hash) WHERE refresh_hash IS NOT NULL;
CREATE INDEX devices_refresh_prev_hash_idx ON devices (refresh_prev_hash) WHERE refresh_prev_hash IS NOT NULL;

-- 用户设置（多设备同步）。管理员后台可只读查看。
CREATE TABLE user_settings (
    user_id           uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    theme_mode        text        NOT NULL DEFAULT 'system',
    font_scale        real        NOT NULL DEFAULT 1.0,
    -- 新建备忘录时默认的提前提醒（分钟，0 表示准时）
    default_reminders integer[]   NOT NULL DEFAULT '{0}',
    -- 一周的第一天：1 = 周一，7 = 周日
    week_start        smallint    NOT NULL DEFAULT 1,
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_settings_theme CHECK (theme_mode IN ('system', 'light', 'dark')),
    CONSTRAINT user_settings_font_scale CHECK (font_scale BETWEEN 0.8 AND 1.4),
    CONSTRAINT user_settings_reminders CHECK (cardinality(default_reminders) <= 5),
    CONSTRAINT user_settings_week_start CHECK (week_start IN (1, 7))
);

-- +goose Down
DROP TABLE user_settings;
DROP TABLE devices;
DROP TABLE users;
