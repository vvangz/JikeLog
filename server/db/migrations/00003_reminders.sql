-- 备忘录提醒（ADR-008）：设备推送注册与待发提醒。

-- +goose Up
-- 推送注册：设备登录并同意隐私政策后上报。push_token 为空表示该设备收不到服务端推送。
ALTER TABLE devices
    ADD COLUMN push_provider   text,
    ADD COLUMN push_token      text,
    -- 设备时区（IANA 名称），推送文案中的时间按它显示
    ADD COLUMN time_zone       text    NOT NULL DEFAULT '',
    -- 设备能否自己按时弹出提醒（已授予通知与精确闹钟权限）。为 false 时服务端总会推送
    ADD COLUMN local_reminders boolean NOT NULL DEFAULT false,
    -- 本地闹钟覆盖到的时刻：设备只排定最近若干条提醒，晚于此刻的提醒仍由服务端推送；为空表示全部覆盖
    ADD COLUMN local_until     timestamptz,
    ADD CONSTRAINT devices_push_provider CHECK (push_provider IN ('jpush')),
    ADD CONSTRAINT devices_push_token CHECK ((push_provider IS NULL) = (push_token IS NULL));

-- 同一推送标识只属于一台设备：换账号登录同一部手机时，旧账号不再收到推送
CREATE UNIQUE INDEX devices_push_token_key ON devices (push_provider, push_token);

-- 待发的提醒。备忘录每次写入（同一推送事务内）先删后建，删除、完成或时间已过的不再保留。
CREATE TABLE memo_reminders (
    memo_id     uuid        NOT NULL REFERENCES records (id) ON DELETE CASCADE,
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- 提前量（分钟），0 表示准时
    offset_min  integer     NOT NULL,
    fire_at     timestamptz NOT NULL,
    -- 发送中：某个实例领取后在此之前其他实例不再领取；发送失败则到期后重试
    lease_until timestamptz,
    -- 已尝试发送的次数
    attempts    integer     NOT NULL DEFAULT 0,
    PRIMARY KEY (memo_id, offset_min),
    CONSTRAINT memo_reminders_offset CHECK (offset_min BETWEEN 0 AND 43200)
);

CREATE INDEX memo_reminders_due_idx ON memo_reminders (fire_at);

-- +goose Down
DROP TABLE memo_reminders;
DROP INDEX devices_push_token_key;
ALTER TABLE devices
    DROP CONSTRAINT devices_push_token,
    DROP CONSTRAINT devices_push_provider,
    DROP COLUMN local_until,
    DROP COLUMN local_reminders,
    DROP COLUMN time_zone,
    DROP COLUMN push_token,
    DROP COLUMN push_provider;
