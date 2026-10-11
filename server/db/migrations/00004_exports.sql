-- 数据导出（ADR-010）：用户发起的导出任务，由后台任务生成 zip 上传到对象存储。

-- +goose Up
CREATE TABLE exports (
    id          uuid PRIMARY KEY,
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- 发起导出的设备：完成后向它推送通知
    device_id   uuid REFERENCES devices (id) ON DELETE SET NULL,
    -- 所选模块
    modules     text[]      NOT NULL,
    -- 是否包含附件文件
    attachments boolean     NOT NULL,
    -- pending 等待生成 / running 生成中 / done 已完成 / failed 失败 / expired 文件已过期删除
    -- deleted 用户已删除（记录保留到超过 24 小时，仍计入每天的导出次数）
    status      text        NOT NULL DEFAULT 'pending',
    -- 已尝试生成的次数
    attempts    integer     NOT NULL DEFAULT 0,
    -- 生成中：某个实例领取后在此之前其他实例不再领取；等待重试时为下次可领取的时刻
    lease_until timestamptz,
    object_key  text,
    size        bigint,
    -- 失败原因（给用户看的说明，不含数据）
    error       text,
    created_at  timestamptz NOT NULL,
    finished_at timestamptz,
    -- 导出文件的删除时刻
    expires_at  timestamptz,
    CONSTRAINT exports_status CHECK (status IN ('pending', 'running', 'done', 'failed', 'expired', 'deleted')),
    CONSTRAINT exports_modules CHECK (
        cardinality(modules) BETWEEN 1 AND 4
        AND modules <@ ARRAY['worklog', 'note', 'memo', 'ledger']::text[]
    ),
    CONSTRAINT exports_done CHECK (status <> 'done' OR (object_key IS NOT NULL AND expires_at IS NOT NULL))
);

-- 同一账号同时只能有一个进行中的导出
CREATE UNIQUE INDEX exports_active_key ON exports (user_id) WHERE status IN ('pending', 'running');
CREATE INDEX exports_user_idx ON exports (user_id, created_at DESC);
CREATE INDEX exports_active_idx ON exports (created_at) WHERE status IN ('pending', 'running');
CREATE INDEX exports_expire_idx ON exports (expires_at) WHERE status = 'done';

-- +goose Down
DROP TABLE exports;
