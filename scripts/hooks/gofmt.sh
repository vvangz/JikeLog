#!/usr/bin/env bash
# pre-commit：检查暂存的 Go 文件是否已 gofmt。用法：gofmt.sh <file>...
set -euo pipefail

out="$(gofmt -l "$@")"
if [ -n "$out" ]; then
  echo "以下文件未 gofmt："
  echo "$out"
  exit 1
fi
