-- 同步、修订历史、数据密钥与附件相关查询，由 sqlc 生成到 internal/dbgen（scripts/gen-db.sh）。

-- name: LockSyncCursor :one
-- 取得（必要时创建）账号的同步游标并加行锁，同一账号的推送因此串行。
INSERT INTO sync_cursors (user_id) VALUES (@user_id)
ON CONFLICT (user_id) DO UPDATE SET last_seq = sync_cursors.last_seq
RETURNING last_seq;

-- name: SetSyncCursor :exec
UPDATE sync_cursors SET last_seq = @last_seq WHERE user_id = @user_id;

-- name: GetSyncCursor :one
SELECT COALESCE((SELECT last_seq FROM sync_cursors WHERE user_id = @user_id), 0)::bigint AS last_seq;

-- name: GetRecordForUpdate :one
SELECT * FROM records WHERE id = @id FOR UPDATE;

-- name: InsertRecord :exec
INSERT INTO records (id, user_id, entity, version, server_seq, fields, clocks, absorbed, deleted, device_id)
VALUES (@id, @user_id, @entity, 1, @server_seq, @fields, @clocks, @absorbed, @deleted, sqlc.narg(device_id));

-- name: UpdateRecord :exec
UPDATE records
SET version = version + 1, server_seq = @server_seq, fields = @fields, clocks = @clocks,
    absorbed = @absorbed, deleted = @deleted, device_id = sqlc.narg(device_id), updated_at = now()
WHERE id = @id;

-- name: ListRecordsSince :many
SELECT * FROM records
WHERE user_id = @user_id AND server_seq > @since
ORDER BY server_seq
LIMIT @max_rows;

-- name: GetRecord :one
SELECT * FROM records WHERE id = @id AND user_id = @user_id;

-- name: InsertRevision :exec
INSERT INTO record_revisions (id, record_id, user_id, entity, version, reason, fields, device_id)
VALUES (@id, @record_id, @user_id, @entity, @version, @reason, @fields, sqlc.narg(device_id));

-- name: PruneRevisions :exec
-- 每条记录最多保留最近 @keep 份修订。
DELETE FROM record_revisions AS old
WHERE old.record_id = @record_id::uuid
  AND old.id NOT IN (
    SELECT r.id FROM record_revisions AS r WHERE r.record_id = @record_id::uuid
    ORDER BY r.created_at DESC, r.id DESC LIMIT @keep
  );

-- name: ListRevisions :many
SELECT r.id, r.version, r.reason, r.created_at, r.device_id, COALESCE(d.model, '')::text AS device_model
FROM record_revisions r
LEFT JOIN devices d ON d.id = r.device_id
WHERE r.record_id = @record_id AND r.user_id = @user_id
ORDER BY r.created_at DESC, r.id DESC;

-- name: GetRevision :one
SELECT * FROM record_revisions WHERE id = @id AND user_id = @user_id;

-- name: GetUserKey :one
SELECT * FROM user_keys WHERE user_id = @user_id;

-- name: InsertUserKey :exec
-- 并发创建时以先写入者为准，调用方随后重新读取。
INSERT INTO user_keys (user_id, kms_key_id, wrapped) VALUES (@user_id, @kms_key_id, @wrapped)
ON CONFLICT (user_id) DO NOTHING;

-- name: AckDevice :execrows
UPDATE devices SET last_ack_seq = GREATEST(last_ack_seq, @seq)
WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL;

-- name: InsertAttachment :exec
INSERT INTO attachments (id, user_id, owner_entity, owner_id, object_key, file_name, mime, size, sha256)
VALUES (@id, @user_id, @owner_entity, @owner_id, @object_key, @file_name, @mime, @size, @sha256);

-- name: GetAttachment :one
SELECT * FROM attachments WHERE id = @id AND user_id = @user_id;

-- name: GetAttachmentForUpdate :one
SELECT * FROM attachments WHERE id = @id AND user_id = @user_id FOR UPDATE;

-- name: MarkAttachmentReady :exec
UPDATE attachments SET status = 'ready', completed_at = now() WHERE id = @id;

-- name: MarkAttachmentDeleted :exec
UPDATE attachments SET status = 'deleted' WHERE id = @id AND user_id = @user_id;

-- name: SumAttachmentBytes :one
SELECT COALESCE(SUM(size), 0)::bigint AS total FROM attachments WHERE user_id = @user_id AND status <> 'deleted';

-- name: ListDeletedAttachments :many
SELECT id, object_key FROM attachments WHERE status = 'deleted' ORDER BY created_at LIMIT @max_rows;

-- name: PurgeAttachment :exec
DELETE FROM attachments WHERE id = @id AND status = 'deleted';
