#!/usr/bin/env bash
# 由 server/api/openapi.yaml 生成各端接口代码。
#   - Go：server/internal/apigen/apigen.gen.go（oapi-codegen，版本由 server/go.mod 的 tool 指令锁定）
#   - TypeScript：apps/admin-web/src/api/schema.gen.ts（openapi-typescript，管理后台存在时生成）
# 用法：bash scripts/gen-api.sh [all|go|ts]，默认 all
set -euo pipefail

TARGET="${1:-all}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/server"
SPEC="$SERVER/api/openapi.yaml"

log() { printf '\033[36m[gen-api]\033[0m %s\n' "$*"; }

gen_go() {
  # 代码生成器在本机运行：即使全局 go env 设置了交叉编译目标（如 GOOS=linux），也按宿主平台构建
  (
    cd "$SERVER/internal/apigen"
    GOOS="$(go env GOHOSTOS)" GOARCH="$(go env GOHOSTARCH)" \
      go tool oapi-codegen -config "$SERVER/api/oapi-codegen.yaml" "$SPEC"
  )
  log "Go → server/internal/apigen/apigen.gen.go"
}

gen_ts() {
  local web="$ROOT/apps/admin-web"
  if [[ ! -f "$web/package.json" ]]; then
    log "跳过 TypeScript：apps/admin-web 尚未创建"
    return
  fi
  (cd "$web" && pnpm exec openapi-typescript "$SPEC" -o src/api/schema.gen.ts)
  log "TypeScript → apps/admin-web/src/api/schema.gen.ts"
}

case "$TARGET" in
  go) gen_go ;;
  ts) gen_ts ;;
  all) gen_go; gen_ts ;;
  *) echo "未知目标：$TARGET（可选 all|go|ts）" >&2; exit 2 ;;
esac
