#!/bin/sh
# backup 容器入口：daemon（默认）每天 03:30 由 crond 检查是否需要备份；
# backup-now 立即备份一次；其他参数原样执行（便于排查，例如 sh）。
set -eu

case "${1:-daemon}" in
  daemon)
    echo "备份服务已启动：每天 03:30 检查，间隔 ${BACKUP_INTERVAL_DAYS:-14} 天，保留 ${BACKUP_KEEP:-6} 份"
    exec crond -f -l 8
    ;;
  backup-now)
    exec /usr/local/bin/backup.sh now
    ;;
  *)
    exec "$@"
    ;;
esac
