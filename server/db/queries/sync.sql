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
-- 只锁当前账号的行，避免与其他账号产生锁等待。
SELECT * FROM records WHERE id = @id AND user_id = @user_id FOR UPDATE;

-- name: RecordIDTaken :one
-- ID 是否已被使用（任意账号）。不加锁，只用于判断 ID 冲突。
SELECT EXISTS (SELECT 1 FROM records WHERE id = @id)::boolean AS taken;

-- name: InsertRecord :execrows
-- 两个账号并发插入同一 ID 时，后到者影响 0 行，由调用方报告 ID 冲突。
INSERT INTO records (id, user_id, entity, version, server_seq, fields, clocks, absorbed, deleted, device_id)
VALUES (@id, @user_id, @entity, 1, @server_seq, @fields, @clocks, @absorbed, @deleted, sqlc.narg(device_id))
ON CONFLICT (id) DO NOTHING;

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

-- name: CountPendingAttachments :one
SELECT count(*)::bigint AS n FROM attachments WHERE user_id = @user_id AND status = 'pending';

-- name: ExpirePendingAttachments :execrows
-- 申请后一直未完成的上传视为放弃，交给清理任务删除对象并释放配额。
UPDATE attachments SET status = 'deleted' WHERE status = 'pending' AND created_at < @before;

-- name: ListDeletedAttachments :many
SELECT id, object_key FROM attachments WHERE status = 'deleted' ORDER BY created_at LIMIT @max_rows;

-- name: PurgeAttachment :exec
DELETE FROM attachments WHERE id = @id AND status = 'deleted';

-- name: ListMemoReminders :many
SELECT offset_min, fire_at FROM memo_reminders WHERE memo_id = @memo_id;

-- name: DeleteMemoReminder :exec
DELETE FROM memo_reminders WHERE memo_id = @memo_id AND offset_min = @offset_min;

-- name: UpsertMemoReminder :exec
-- 时刻变化的提醒重新开始计数；时刻未变的保持原样（可能正在发送）。
INSERT INTO memo_reminders (memo_id, user_id, offset_min, fire_at)
VALUES (@memo_id, @user_id, @offset_min, @fire_at)
ON CONFLICT (memo_id, offset_min) DO UPDATE
SET fire_at = EXCLUDED.fire_at, attempts = 0, lease_until = NULL
WHERE memo_reminders.fire_at <> EXCLUDED.fire_at;

-- name: ClaimDueReminders :many
-- 领取到期且未被其他实例领取的提醒，并把领取期限写回（调用方在事务内执行）。
UPDATE memo_reminders AS m
SET lease_until = @lease_until::timestamptz, attempts = m.attempts + 1
FROM (
    SELECT r.memo_id, r.offset_min FROM memo_reminders AS r
    WHERE r.fire_at <= @now::timestamptz AND (r.lease_until IS NULL OR r.lease_until <= @now::timestamptz)
    ORDER BY r.fire_at
    LIMIT @max_rows
    FOR UPDATE SKIP LOCKED
) AS due
WHERE m.memo_id = due.memo_id AND m.offset_min = due.offset_min
RETURNING m.memo_id, m.user_id, m.offset_min, m.fire_at, m.attempts;

-- name: FinishReminder :exec
-- 只删除本次领取的那一条：期间备忘录被修改时，提醒已被替换（fire_at 不同），保留新的。
DELETE FROM memo_reminders
WHERE memo_id = @memo_id AND offset_min = @offset_min AND fire_at = @fire_at;

-- name: ListReminderTargets :many
-- 需要服务端推送的设备：有推送标识，且不能确定它已在本地按时提醒
-- （没有本地提醒能力、尚未同步到这一版备忘录，或提醒时刻超出了本地闹钟覆盖的范围）。
SELECT id, push_provider, push_token, time_zone FROM devices
WHERE user_id = @user_id AND revoked_at IS NULL AND push_token IS NOT NULL
  AND NOT (
    local_reminders AND last_ack_seq >= @memo_seq::bigint
    AND (local_until IS NULL OR local_until >= @fire_at::timestamptz)
  );
