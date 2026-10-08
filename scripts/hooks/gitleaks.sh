#!/usr/bin/env bash
# pre-commit：扫描暂存区中的密钥。未安装 gitleaks 时只提示，CI 仍会全量检查。
# 逻辑放在脚本里而不是 lefthook.yml 的多行 run 中：Windows 上 lefthook 把多行命令
# 作为参数传给 sh 时会破坏内嵌的双引号。
set -euo pipefail

if command -v gitleaks >/dev/null 2>&1; then
  exec gitleaks git --pre-commit --staged --redact --no-banner
fi
echo "⚠️  未安装 gitleaks，跳过本地密钥扫描（CI 仍会检查）。安装：winget install Gitleaks.Gitleaks"
