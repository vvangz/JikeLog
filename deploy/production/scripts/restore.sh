#!/usr/bin/env bash
# 从加密备份恢复（ADR-012）。需要 age 私钥文件（离线保存，不在服务器上）；主机只需要 Docker。
#
#   演练（默认）：把备份恢复到一个临时的独立数据库，校验各表行数与附件数，不影响正式数据。
#     bash scripts/restore.sh backups/jikelog-20261011-033000.tar.age ~/jikelog-backup.key
#   正式恢复：停止 api，用备份覆盖正式数据库与附件，再启动。会要求输入 RESTORE 确认。
#     bash scripts/restore.sh <备份文件> <私钥文件> --production
set -euo pipefail

FILE="${1:?用法：restore.sh <备份文件> <age 私钥文件> [--production]}"
KEY="${2:?缺少 age 私钥文件}"
MODE="${3:-drill}"
cd "$(dirname "$0")/.."

VERSION=$(grep -E '^JIKELOG_VERSION=' .env | cut -d= -f2-)
IMAGE="jikelog-backup:${VERSION}"
WORK=$(mktemp -d "$PWD/restore-XXXXXX")
chmod 700 "$WORK"
cleanup() {
  docker rm -f jikelog-restore-db >/dev/null 2>&1 || true
  docker network rm jikelog-restore >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

log() { echo "[restore] $*"; }

log "解密并解包 $(basename "$FILE")"
docker run --rm -v "$(realpath "$FILE"):/in.tar.age:ro" -v "$(realpath "$KEY"):/key:ro" -v "$WORK:/work" \
  --entrypoint sh "$IMAGE" -c 'age -d -i /key /in.tar.age | tar -C /work -xf -'
log "备份内容：$(cat "$WORK/manifest.json")"

expected_counts=$(docker run --rm -v "$WORK:/work:ro" --entrypoint jq "$IMAGE" -c '.counts' /work/manifest.json)
expected_objects=$(docker run --rm -v "$WORK:/work:ro" --entrypoint jq "$IMAGE" -r '.objectFiles' /work/manifest.json)
actual_objects=$(find "$WORK/objects" -type f | wc -l | tr -d ' ')
[ "$actual_objects" = "$expected_objects" ] || { log "附件数不一致：备份中 $actual_objects，记录为 $expected_objects"; exit 1; }

# 与 backup.sh 统计的口径一致（各表全部行数）
COUNT_SQL="SELECT json_object_agg(t, n) FROM (
  SELECT 'users' AS t, count(*) AS n FROM users
  UNION ALL SELECT 'records', count(*) FROM records
  UNION ALL SELECT 'attachments', count(*) FROM attachments
  UNION ALL SELECT 'admin_users', count(*) FROM admin_users
) s"

verify_counts() { # 实际行数 JSON（按键排序后比较）
  local actual expected
  actual=$(docker run --rm -i --entrypoint jq "$IMAGE" -cS . <<<"$1")
  expected=$(docker run --rm -i --entrypoint jq "$IMAGE" -cS . <<<"$expected_counts")
  if [ "$actual" = "$expected" ]; then
    log "行数一致：$1；附件 $actual_objects 个"
  else
    log "行数不一致：恢复后 $1，备份时 $expected_counts"
    exit 1
  fi
}

if [ "$MODE" != "--production" ]; then
  log "演练：恢复到临时数据库"
  docker network create jikelog-restore >/dev/null
  docker run -d --name jikelog-restore-db --network jikelog-restore -e POSTGRES_PASSWORD=drill postgres:17-alpine >/dev/null
  for _ in $(seq 1 30); do
    # 镜像初始化期间的临时实例只监听本地套接字，用 TCP 检查才说明正式实例已就绪
    docker exec jikelog-restore-db pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1 && break
    sleep 1
  done
  actual=$(docker run --rm --network jikelog-restore -v "$WORK:/work:ro" \
    -e PGHOST=jikelog-restore-db -e PGUSER=postgres -e PGPASSWORD=drill --entrypoint sh "$IMAGE" -c "
      createdb jikelog && pg_restore -d jikelog --no-owner --exit-on-error /work/db.dump && psql -At -d jikelog -c \"$COUNT_SQL\"")
  verify_counts "$actual"
  log "演练完成：备份可以完整恢复（临时数据库已删除）。记得删除服务器上的私钥文件：rm $KEY"
  exit 0
fi

read -r -p "将用备份覆盖正式数据库与附件，当前数据会丢失。输入 RESTORE 确认：" answer
[ "$answer" = RESTORE ] || { log "已取消"; exit 1; }

log "停止 api 与 backup"
docker compose stop api backup
log "恢复数据库"
docker compose run --rm -T -v "$WORK:/work:ro" --entrypoint sh backup -c \
  "pg_restore -d jikelog --clean --if-exists --no-owner --exit-on-error /work/db.dump"
actual=$(docker compose run --rm -T --entrypoint psql backup -At -c "$COUNT_SQL")
verify_counts "$actual"
log "恢复附件"
docker compose run --rm -T -v "$WORK:/work:ro" --entrypoint sh backup -c \
  'rclone copy /work/objects "src:${STORAGE_BUCKET}"'
cp "$WORK/env" ".env.from-backup"
chmod 600 ".env.from-backup"
log "备份中的 .env 已保存为 .env.from-backup：如果服务器上的 .env 丢失或密钥不同，先用它替换 .env 再启动"
docker compose up -d
log "正式恢复完成。记得删除服务器上的私钥文件：rm $KEY"
