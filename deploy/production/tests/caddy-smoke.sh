#!/usr/bin/env bash
# 正式环境 Caddyfile 的路由冒烟测试：用真实的 Caddy 镜像加载 caddy/Caddyfile（只开 HTTP），
# 放入假的官网、安装包与管理后台文件，逐条检查路由与响应头。CI 与本机（需要 Docker）都可以运行：
#   bash deploy/production/tests/caddy-smoke.sh
# 排查时设 CADDY_SMOKE_KEEP=1：结束后保留容器与临时文件（端口 18080）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="$(grep -oE 'image: caddy:[^ ]+' "$HERE/compose.yml" | head -1 | cut -d' ' -f2)"
PORT="${CADDY_SMOKE_PORT:-18080}"
NAME="jikelog-caddy-smoke-$$"

work="$(mktemp -d)"
cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
[ -n "${CADDY_SMOKE_KEEP:-}" ] && trap - EXIT

# 假的发布内容：current 都是指向版本目录的相对软链接，与 deploy.sh 一致
mkdir -p "$work/site/1.1.0/guide" "$work/site/1.1.0/assets" "$work/downloads/1.1.0" "$work/admin/1.1.0"
echo '<p>site-home</p>' >"$work/site/1.1.0/index.html"
echo '<p>site-download</p>' >"$work/site/1.1.0/download.html"
echo '<p>site-guide</p>' >"$work/site/1.1.0/guide/index.html"
echo '<p>site-quick-start</p>' >"$work/site/1.1.0/guide/quick-start.html"
echo '<p>site-404</p>' >"$work/site/1.1.0/404.html"
echo 'console.log(1)' >"$work/site/1.1.0/assets/app.js"
echo '{"version":"1.1.0"}' >"$work/downloads/1.1.0/latest.json"
echo 'apk' >"$work/downloads/1.1.0/jikelog-1.1.0.apk"
echo 'msix' >"$work/downloads/1.1.0/jikelog-1.1.0.msix"
echo '<p>admin</p>' >"$work/admin/1.1.0/index.html"
for d in site downloads admin; do ln -s 1.1.0 "$work/$d/current"; done

# Git Bash 下 docker 需要 Windows 路径
host_path() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }

MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" -p "127.0.0.1:$PORT:80" \
  -e SITE_DOMAIN=:80 -e SITE_DOMAIN_APEX=:81 -e ACME_EMAIL=smoke@example.com -e STORAGE_BUCKET=jikelog \
  -v "$(host_path "$HERE/caddy"):/etc/caddy:ro" \
  -v "$(host_path "$work/site"):/srv/site:ro" \
  -v "$(host_path "$work/downloads"):/srv/downloads:ro" \
  -v "$(host_path "$work/admin"):/srv/admin:ro" \
  "$IMAGE" >/dev/null

base="http://127.0.0.1:$PORT"
for _ in $(seq 1 30); do
  curl -s -o /dev/null --noproxy '*' "$base/" && break
  sleep 0.5
done

fail=0
# check <说明> <路径> <期望状态码> [响应中应包含的文字（正文或响应头）]...
check() {
  local desc="$1" path="$2" status="$3"
  shift 3
  local out code
  out="$(curl -s -i --noproxy '*' "$base$path")"
  code="$(awk 'NR == 1 {print $2}' <<<"$out")"
  if [ "$code" != "$status" ]; then
    echo "✘ $desc：$path 返回 $code，期望 $status"
    fail=1
    return
  fi
  # 用 bash 自己做不区分大小写的子串匹配（Git Bash 的 grep -iF 遇到某些输入会异常退出）
  local lower="${out,,}"
  for want in "$@"; do
    if [[ "$lower" != *"${want,,}"* ]]; then
      echo "✘ $desc：$path 的响应中没有「$want」"
      fail=1
      return
    fi
  done
  echo "✔ $desc"
}

check '官网首页' / 200 site-home 'X-Frame-Options: DENY' "frame-ancestors 'none'" 'Cache-Control: no-cache'
check '不带 .html 的页面地址' /download 200 site-download
check '目录页' /guide/ 200 site-guide
check '目录不带斜杠' /guide 200 site-guide
check '教程章节' /guide/quick-start 200 site-quick-start
check '静态资源长期缓存' /assets/app.js 200 'immutable'
check '找不到的页面显示 404 页' /no-such-page 404 site-404 'Strict-Transport-Security'
check '下载清单不缓存' /download/latest.json 200 '"version":"1.1.0"' 'Cache-Control: no-cache'
check 'APK 作为下载' /download/jikelog-1.1.0.apk 200 'Content-Disposition: attachment' 'application/vnd.android.package-archive' 'Cache-Control: no-cache'
check 'MSIX 作为下载' /download/jikelog-1.1.0.msix 200 'Content-Disposition: attachment' 'application/msix'
check '下载目录不列出文件' /download/ 404
check '不存在的安装包' /download/jikelog-0.0.1.apk 404
check '管理后台' /admin/ 200 admin
check '管理后台不带斜杠时跳转' /admin 308 'Location: /admin/'
check '管理后台缺少的静态资源不被长期缓存' /admin/assets/missing.js 404 'X-Frame-Options: DENY' 'Cache-Control: no-store'
check '不存在的安装包返回网页而不是下载' /download/jikelog-9.9.9.apk 404 'Content-Type: text/html' site-404
check '404 页不能被嵌入' /no-such-page 404 'X-Frame-Options: DENY' "frame-ancestors 'none'"

if [ "$fail" != 0 ]; then
  echo "---- caddy 日志 ----"
  docker logs "$NAME" 2>&1 | tail -20
  exit 1
fi
echo "Caddyfile 路由检查全部通过"
