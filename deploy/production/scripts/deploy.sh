#!/usr/bin/env bash
# 部署一个版本（ADR-012），由 GitHub Actions 的"部署"工作流通过 SSH 调用，也可以手动执行：
#   cd /root/jikelog && bash scripts/deploy.sh 0.9.0
# 发布包事先上传到 releases/<版本>/：api.tar.gz、backup.tar.gz（镜像），admin.tar.gz（管理后台），
# config.tar.gz（compose.yml、caddy/、scripts/），以及服务器缺少的第三方镜像 base.tar.gz（可选）。
# 步骤：部署前备份数据库 → 载入镜像 → 更新配置与管理后台 → 迁移 → 启动 → 就绪检查；失败时切回上一个版本。
set -euo pipefail

VERSION="${1:?用法：deploy.sh <版本，如 0.9.0>}"
# 版本会出现在路径、镜像标签与 .env 中，只接受语义化版本
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "版本号不合法：$VERSION"; exit 1; }
cd "$(dirname "$0")/.."
ROOT=$PWD
REL="releases/$VERSION"
[ -d "$REL" ] || { echo "找不到发布包 $REL"; exit 1; }
[ -f backup.env ] || (umask 077 && touch backup.env) # 异地 OSS 的密钥，未配置时为空
[ -f .env ] || { echo "缺少 .env：首次部署先执行 bash scripts/init-env.sh <域名> <邮箱>，填好备份配置后重新部署"; exit 1; }

log() { echo "$(date '+%H:%M:%S') [deploy $VERSION] $*"; }
get_env() { grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true; }
set_env() {
  if grep -qE "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >>.env; fi
}

[ -n "$(get_env ACME_EMAIL)" ] || { echo ".env 中的 ACME_EMAIL 为空：Caddy 申请证书需要联系邮箱"; exit 1; }
[ -n "$(get_env SITE_DOMAIN)" ] || { echo ".env 中的 SITE_DOMAIN 为空"; exit 1; }
[ -n "$(get_env BACKUP_AGE_RECIPIENT)" ] || log "警告：BACKUP_AGE_RECIPIENT 为空，定期备份不会执行（见 docs/部署运维/备份与恢复.md）"

PREV=$(get_env JIKELOG_VERSION)
# 上一个版本的镜像已不在时（例如首次部署），没有可以切回的版本
docker image inspect "jikelog-api:$PREV" >/dev/null 2>&1 || PREV=""
PREV_ADMIN=$(readlink admin/current 2>/dev/null || true)
log "当前版本 ${PREV:-无}"

log "载入镜像"
[ -f "$REL/base.tar.gz" ] && docker load -i "$REL/base.tar.gz" >/dev/null
docker load -i "$REL/api.tar.gz" >/dev/null
docker load -i "$REL/backup.tar.gz" >/dev/null

# .env 中可能还没有 JIKELOG_VERSION（首次部署、从验收环境迁移），compose 解析镜像名时需要它
if JIKELOG_VERSION="${PREV:-$VERSION}" docker compose ps --status running postgres 2>/dev/null | grep -q postgres; then
  log "部署前备份数据库"
  mkdir -p backups/predeploy
  chmod 700 backups/predeploy
  dump="backups/predeploy/db-before-$VERSION-$(date +%Y%m%d-%H%M%S).dump"
  (umask 077 && JIKELOG_VERSION="${PREV:-$VERSION}" docker compose exec -T postgres pg_dump -Fc -U jikelog jikelog >"$dump") ||
    { rm -f "$dump"; log "部署前备份失败，停止部署"; exit 1; }
  ls -1t backups/predeploy/*.dump | tail -n +6 | xargs -r rm -f
fi

log "更新配置与管理后台"
# 保存当前配置，失败时连同镜像版本一起切回（不含 scripts/：不能覆盖正在执行的本脚本）
saved=$(mktemp -d)
trap 'rm -rf "$saved"' EXIT
for p in compose.yml caddy; do if [ -e "$p" ]; then cp -a "$p" "$saved/"; fi; done
tar -xzf "$REL/config.tar.gz" -C "$ROOT"
mkdir -p "admin/$VERSION"
tar -xzf "$REL/admin.tar.gz" -C "admin/$VERSION"
ln -sfn "$VERSION" admin/current
set_env JIKELOG_VERSION "$VERSION"

rollback() {
  log "失败，切回 ${PREV:-（无）}"
  if [ -n "$PREV" ]; then
    set_env JIKELOG_VERSION "$PREV"
    [ -n "$PREV_ADMIN" ] && ln -sfn "$PREV_ADMIN" admin/current
    [ -f "$saved/compose.yml" ] && cp -a "$saved/." "$ROOT/"
    docker compose up -d --remove-orphans
    docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
  fi
  log "数据库迁移只向前；如需回到部署前的数据，见 backups/predeploy/ 与 docs/部署运维/生产部署.md 第 3 节"
  exit 1
}
trap rollback ERR

log "数据库迁移"
docker compose run --rm -T --entrypoint jikelog-migrate api

log "启动服务"
docker compose up -d --remove-orphans
# backup 以单个文件挂载 .env：.env 被 sed -i 等替换后，容器看到的仍是旧文件，重建一次
docker compose up -d --force-recreate --no-deps backup
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

log "等待就绪"
ready=0
for _ in $(seq 1 30); do
  if docker compose exec -T api wget -qO- http://127.0.0.1:8080/readyz >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
[ "$ready" = 1 ] || false
trap - ERR

log "清理旧版本（保留最近 3 个发布包、管理后台与镜像）"
current=$(readlink admin/current)
# 只列真实目录（find -type d 不跟随软链接，不会碰到 admin/current）
prune_old() { # 目录 要保留的最新个数
  find "$1" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | tail -n +$(($2 + 1)) | cut -d' ' -f2- |
    while read -r d; do
      [ "$(basename "$d")" = "$current" ] || rm -rf -- "$d"
    done
}
prune_old releases 3
prune_old admin 3
# 镜像：只保留仍有发布包的版本
for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^jikelog-(api|backup):'); do
  [ -d "releases/${img#*:}" ] || docker rmi "$img" >/dev/null 2>&1 || true
done
docker image prune -f >/dev/null

log "完成：$(docker compose exec -T api wget -qO- http://127.0.0.1:8080/api/v1/system/info | head -c 200)"
