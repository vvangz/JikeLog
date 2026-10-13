#!/usr/bin/env bash
# 检查备份是否按时完成（ADR-012）：超过 BACKUP_INTERVAL_DAYS + 1 天没有成功备份时返回 1，可接入监控或定时任务。
set -euo pipefail
cd "$(dirname "$0")/.."

interval=$(grep -E '^BACKUP_INTERVAL_DAYS=' .env | cut -d= -f2- || true)
interval=${interval:-14}
if [ ! -f backups/last-success ]; then
  echo "还没有成功的备份"
  exit 1
fi
age_days=$(( ($(date +%s) - $(cat backups/last-success)) / 86400 ))
echo "最近一次成功备份在 ${age_days} 天前；最新状态：$(cat backups/status.json 2>/dev/null || echo '无')"
[ "$age_days" -le $((interval + 1)) ] || { echo "超过 $((interval + 1)) 天没有成功备份"; exit 1; }
