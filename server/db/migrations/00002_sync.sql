-- 同步引擎（ADR-005）、落库加密密钥（ADR-006）与附件。

-- +goose Up
-- 每个账号的同步序号分配器。推送事务先锁住本行，同一账号的写入因此串行、序号无空洞。
CREATE TABLE sync_cursors (
    user_id  uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    last_seq bigint NOT NULL DEFAULT 0
);

-- 全部同步实体的通用记录表；字段定义在服务端 schema 中登记（internal/syncer）。
CREATE TABLE records (
    -- 客户端生成的 UUIDv7
    id          uuid PRIMARY KEY,
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    entity      text        NOT NULL,
    version     bigint      NOT NULL,
    server_seq  bigint      NOT NULL,
    -- 字段名 → 值；敏感字段为 "v1:" 开头的密文
    fields      jsonb       NOT NULL,
    -- 字段名 → 最后修改的 HLC
    clocks      jsonb       NOT NULL,
    -- 字段名 → 已吸收的客户端 HLC（推送重试幂等）
    absorbed    jsonb       NOT NULL DEFAULT '{}',
    -- 墓碑：保留最后内容便于恢复，拉取时不下发字段
    deleted     boolean     NOT NULL DEFAULT false,
    -- 最后写入的设备
    device_id   uuid REFERENCES devices (id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT records_entity_format CHECK (entity ~ '^[a-z][a-z_]{1,31}$')
);

CREATE UNIQUE INDEX records_user_seq_key ON records (user_id, server_seq);

-- 修订历史：edit（同一设备 10 分钟内只留一份）、conflict（冲突败方）、delete（删除前状态）。
CREATE TABLE record_revisions (
    id         uuid PRIMARY KEY,
    record_id  uuid        NOT NULL REFERENCES records (id) ON DELETE CASCADE,
    user_id    uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    entity     text        NOT NULL,
    -- 快照对应的记录版本
    version    bigint      NOT NULL,
    reason     text        NOT NULL,
    -- 与 records.fields 格式相同（敏感字段为密文）
    fields     jsonb       NOT NULL,
    device_id  uuid REFERENCES devices (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT record_revisions_reason CHECK (reason IN ('edit', 'conflict', 'delete'))
);

CREATE INDEX record_revisions_record_idx ON record_revisions (record_id, created_at DESC);

-- 每个账号一把数据密钥（DEK），由 KMS 主密钥包裹。注销账号时随账号删除，备份中的密文随之无法解开。
CREATE TABLE user_keys (
    user_id    uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    kms_key_id text        NOT NULL,
    wrapped    bytea       NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 附件对象。客户端通过预签名 URL 直传对象存储，完成后由服务端写入 attachment 同步记录。
CREATE TABLE attachments (
    -- 与 attachment 同步记录的 id 相同
    id           uuid PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    owner_entity text        NOT NULL,
    owner_id     uuid        NOT NULL,
    object_key   text        NOT NULL,
    -- 文件名密文（与同步记录中的 fileName 相同）
    file_name    text        NOT NULL,
    mime         text        NOT NULL,
    size         bigint      NOT NULL,
    sha256       text        NOT NULL,
    status       text        NOT NULL DEFAULT 'pending',
    created_at   timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    CONSTRAINT attachments_status CHECK (status IN ('pending', 'ready', 'deleted')),
    CONSTRAINT attachments_size CHECK (size > 0),
    CONSTRAINT attachments_sha256 CHECK (sha256 ~ '^[0-9a-f]{64}$')
);

-- 统计配额（pending 也计入，防止反复申请上传绕过配额）
CREATE INDEX attachments_user_active_idx ON attachments (user_id) WHERE status <> 'deleted';
-- 清理任务：待删除的对象
CREATE INDEX attachments_deleted_idx ON attachments (status) WHERE status = 'deleted';

-- 设备已确认的同步序号（M4 提醒去重据此判断设备是否已同步到某条备忘录）
ALTER TABLE devices ADD COLUMN last_ack_seq bigint NOT NULL DEFAULT 0;

-- +goose Down
ALTER TABLE devices DROP COLUMN last_ack_seq;
DROP TABLE attachments;
DROP TABLE user_keys;
DROP TABLE record_revisions;
DROP TABLE records;
DROP TABLE sync_cursors;
