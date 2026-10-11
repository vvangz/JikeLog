-- 数据导出（ADR-010），由 sqlc 生成到 internal/dbgen（scripts/gen-db.sh）。

-- name: CreateExport :execrows
-- 已有进行中的导出时影响 0 行。
INSERT INTO exports (id, user_id, device_id, modules, attachments, created_at)
VALUES (@id, @user_id, sqlc.narg(device_id), @modules, @attachments, @created_at)
ON CONFLICT (user_id) WHERE status IN ('pending', 'running') DO NOTHING;

-- name: CountExportsSince :one
SELECT count(*) FROM exports WHERE user_id = @user_id AND created_at >= @since;

-- name: ListExports :many
SELECT * FROM exports WHERE user_id = @user_id ORDER BY created_at DESC LIMIT @max_rows;

-- name: GetExport :one
SELECT * FROM exports WHERE id = @id AND user_id = @user_id;

-- name: ClaimExport :one
-- 领取一个可以生成的导出（等待中，或生成中但领取已过期），并写回领取期限（调用方在事务内执行）。
UPDATE exports AS e
SET status = 'running', lease_until = @lease_until::timestamptz, attempts = e.attempts + 1
FROM (
    SELECT x.id FROM exports AS x
    WHERE x.status IN ('pending', 'running')
      AND (x.lease_until IS NULL OR x.lease_until <= @now::timestamptz)
    ORDER BY x.created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED
) AS due
WHERE e.id = due.id
RETURNING e.*;

-- name: CompleteExport :execrows
-- 只有本次领取（attempts 相同）仍然有效时才写入结果：领取过期后已被其他实例重新领取的，以后者为准。
UPDATE exports
SET status = 'done', object_key = @object_key, size = @size, finished_at = @finished_at,
    expires_at = @expires_at, lease_until = NULL, error = NULL
WHERE id = @id AND status = 'running' AND attempts = @attempts;

-- name: RetryExport :execrows
UPDATE exports SET status = 'pending', lease_until = @retry_at, error = @error
WHERE id = @id AND status = 'running' AND attempts = @attempts;

-- name: FailExport :execrows
UPDATE exports SET status = 'failed', lease_until = NULL, error = @error, finished_at = @finished_at
WHERE id = @id AND status = 'running' AND attempts = @attempts;

-- name: ListExpiredExports :many
SELECT id, object_key FROM exports
WHERE status = 'done' AND expires_at <= @now
ORDER BY expires_at
LIMIT @max_rows;

-- name: ExpireExport :exec
UPDATE exports SET status = 'expired', object_key = NULL, lease_until = NULL WHERE id = @id AND status = 'done';

-- name: DeleteExport :one
-- 删除一条已结束的导出记录（进行中的不删除），返回需要删除的对象。
DELETE FROM exports
WHERE id = @id AND user_id = @user_id AND status NOT IN ('pending', 'running')
RETURNING object_key;

-- name: PruneExports :execrows
-- 已结束且文件已不存在的导出记录保留一段时间供查看，之后删除。
DELETE FROM exports WHERE status IN ('failed', 'expired') AND created_at < @before;

-- name: ListUserRecords :many
-- 逐页读取账号的有效记录（不含墓碑），按同步序号翻页。
SELECT * FROM records
WHERE user_id = @user_id AND NOT deleted AND entity = ANY(@entities::text[]) AND server_seq > @after
ORDER BY server_seq
LIMIT @max_rows;

-- name: ListReadyAttachments :many
SELECT id, object_key, size FROM attachments WHERE user_id = @user_id AND status = 'ready';

-- name: GetExportDevice :one
-- 发起导出的设备：推送标识（可能为空）与时区。已退出登录的设备查不到。
SELECT push_token, time_zone FROM devices
WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL;
