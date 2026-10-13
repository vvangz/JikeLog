#!/bin/sh
# 全量备份（ADR-012）：
#   1. pg_dump -Fc 导出数据库，rclone 复制附件存储桶，连同 /config/env（.env）打包；
#   2. 用 age 公钥加密为 /backups/jikelog-<时间>.tar.age，附带 manifest（各表行数，供恢复后校验）；
#   3. 上传到异地 OSS（已配置时）；本地保留最近 BACKUP_KEEP 份，OSS 上的旧备份由存储桶的生命周期规则删除
#      （BACKUP_OSS_PRUNE=true 时由本脚本删除，需要 AccessKey 有列出与删除权限）；
#   4. 结果写入 /backups/status.json。
# 用法：backup.sh scheduled（未到间隔则跳过） | backup.sh now（立即执行）
set -eu
umask 077 # 备份文件与状态只有 root 可读（备份本身已加密，仍不必让其他用户看到）

MODE="${1:-now}"
DIR=/backups
INTERVAL_DAYS="${BACKUP_INTERVAL_DAYS:-14}"
KEEP="${BACKUP_KEEP:-6}"
LAST="$DIR/last-success"
STATUS="$DIR/status.json"
# 每天 03:30 检查一次，上次备份本身要花几分钟：留 2 小时余量，保证间隔是 14 天而不是 15 天
SLACK_SECONDS=7200
TABLES="users records attachments admin_users"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [backup] $*"; }

write_status() { # 结果 文件 说明
  jq -n --arg result "$1" --arg file "$2" --arg message "$3" --arg at "$(date -Iseconds)" \
    --arg last "$(cat "$LAST" 2>/dev/null || echo 0)" \
    '{result: $result, file: $file, message: $message, at: $at, lastSuccessEpoch: ($last | tonumber)}' >"$STATUS"
}

fail() {
  log "失败：$*"
  write_status failed "" "$*"
  exit 1
}

if [ "$MODE" = scheduled ] && [ -f "$LAST" ]; then
  elapsed=$(($(date +%s) - $(cat "$LAST")))
  if [ "$elapsed" -lt $((INTERVAL_DAYS * 86400 - SLACK_SECONDS)) ]; then
    log "距上次成功备份 $((elapsed / 86400)) 天，未满 ${INTERVAL_DAYS} 天，跳过"
    exit 0
  fi
fi

[ -n "${BACKUP_AGE_RECIPIENT:-}" ] || fail "未设置 BACKUP_AGE_RECIPIENT（age 公钥），不能生成未加密的备份"

ts=$(date +%Y%m%d-%H%M%S)
name="jikelog-$ts.tar.age"
work=$(mktemp -d)
trap 'rm -rf "$work" "$DIR/$name.part"' EXIT

log "导出数据库"
pg_dump -Fc -f "$work/db.dump" || fail "pg_dump 失败"

log "复制附件（存储桶 ${STORAGE_BUCKET}）"
mkdir -p "$work/objects"
rclone copy "src:${STORAGE_BUCKET}" "$work/objects" --quiet || fail "复制附件失败"

cp /config/env "$work/env" || fail "读取 .env 失败"

# 各表行数：直接从导出文件中数（与导出是同一个快照），恢复后据此校验。COPY 文本格式中每行一条记录。
counts="{}"
for t in $TABLES; do
  n=$(pg_restore --data-only --table="$t" -f - "$work/db.dump" | awk '/^COPY /{c=1; next} /^\\\.$/{c=0} c' | wc -l) ||
    fail "统计 $t 行数失败"
  counts=$(echo "$counts" | jq -c --arg t "$t" --argjson n "$n" '. + {($t): $n}')
done
objects=$(find "$work/objects" -type f | wc -l)
jq -n --arg at "$(date -Iseconds)" --argjson counts "$counts" --argjson objects "$objects" \
  '{createdAt: $at, counts: $counts, objectFiles: $objects}' >"$work/manifest.json"

log "加密打包"
# 先打包、再加密：sh 没有 pipefail，管道中 tar 的失败会被忽略
tar -C "$work" -cf "$work/backup.tar" manifest.json db.dump env objects || fail "打包失败"
age -r "$BACKUP_AGE_RECIPIENT" -o "$DIR/$name.part" "$work/backup.tar" || fail "加密失败"
mv "$DIR/$name.part" "$DIR/$name"
size=$(wc -c <"$DIR/$name")
log "已生成 $name（$size 字节，附件 $objects 个）"

# 本地只保留最近 KEEP 份
ls -1 "$DIR"/jikelog-*.tar.age 2>/dev/null | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f "$old" && log "删除本地旧备份 $(basename "$old")"
done

remote="未配置异地 OSS，只保留本地备份"
if [ -n "${BACKUP_OSS_BUCKET:-}" ]; then
  export RCLONE_CONFIG_OSS_ENDPOINT="${BACKUP_OSS_ENDPOINT:-}"
  export RCLONE_CONFIG_OSS_ACCESS_KEY_ID="${BACKUP_OSS_ACCESS_KEY_ID:-}"
  export RCLONE_CONFIG_OSS_SECRET_ACCESS_KEY="${BACKUP_OSS_ACCESS_KEY_SECRET:-}"
  log "上传到 OSS：${BACKUP_OSS_BUCKET}"
  # 只需要写入权限：不检查存储桶与目标文件是否存在
  rclone copyto "$DIR/$name" "oss:${BACKUP_OSS_BUCKET}/$name" --s3-no-check-bucket --no-check-dest --quiet ||
    fail "上传 OSS 失败（本地备份已保留：$name）"
  if [ "${BACKUP_OSS_PRUNE:-false}" = true ]; then
    rclone lsf "oss:${BACKUP_OSS_BUCKET}/" --include 'jikelog-*.tar.age' | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
      rclone deletefile "oss:${BACKUP_OSS_BUCKET}/$old" && log "删除 OSS 旧备份 $old"
    done
  fi
  remote="已上传到 OSS"
else
  log "警告：$remote"
fi

date +%s >"$LAST"
write_status ok "$name" "$remote"
log "完成：$remote"
