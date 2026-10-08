#!/usr/bin/env bash
# 运行 Go 测试并校验覆盖率（排除生成代码与 cmd 入口）。
# 用法：bash scripts/go-coverage.sh [最低覆盖率，默认 80]
set -euo pipefail

MIN="${1:-80}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/server"

# 测试必须按宿主平台编译，即使全局 go env 设置了交叉编译目标
export GOOS="$(go env GOHOSTOS)" GOARCH="$(go env GOHOSTARCH)"

RACE=""
[[ "${CGO_ENABLED:-$(go env CGO_ENABLED)}" == "1" ]] && RACE="-race"

go test $RACE -covermode=atomic -coverprofile=coverage.raw.out ./...
grep -vE '/internal/apigen/|/cmd/' coverage.raw.out > coverage.out
rm -f coverage.raw.out

TOTAL="$(go tool cover -func=coverage.out | awk '/^total:/ {gsub("%","",$3); print $3}')"
echo "Go 覆盖率：${TOTAL}%（要求 ≥ ${MIN}%）"
awk -v t="$TOTAL" -v m="$MIN" 'BEGIN { exit (t + 0 >= m + 0) ? 0 : 1 }' || {
  echo "❌ 覆盖率不足" >&2
  exit 1
}
