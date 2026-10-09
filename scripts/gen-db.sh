#!/usr/bin/env bash
# 由 server/db/queries 与 server/db/migrations 生成类型安全的数据库访问代码（sqlc）。
#   输出：server/internal/dbgen
# sqlc 版本在此固定，不加入 server/go.mod，避免把它的大量依赖带进服务端模块。
# 用法：bash scripts/gen-db.sh
set -euo pipefail

SQLC_VERSION="v1.31.1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/server"

# 按宿主平台构建并运行（即使全局 go env 设置了交叉编译目标）；sqlc 的 PostgreSQL 解析器在无 cgo 时使用 wasm 版本
GOOS="$(go env GOHOSTOS)" GOARCH="$(go env GOHOSTARCH)" CGO_ENABLED=0 \
  go run "github.com/sqlc-dev/sqlc/cmd/sqlc@${SQLC_VERSION}" generate

printf '\033[36m[gen-db]\033[0m %s\n' "Go → server/internal/dbgen"
