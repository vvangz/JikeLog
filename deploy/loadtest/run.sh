#!/usr/bin/env bash
# 运行压测（docs/部署运维/压测.md）：启动独立的压测环境 → 迁移 → k6 → 删除环境（含数据）。
# 用法：bash run.sh <API 镜像，如 jikelog-api:0.9.0>
# 可用环境变量调整负载：DURATION（默认 2m）、API_RATE（默认 30 组/秒）、SYNC_RATE（默认 1 轮/秒）、USERS（默认 8）。
# 结果：results/summary.json 与终端输出；任何阈值未达标时退出码非零。
set -euo pipefail

cd "$(dirname "$0")"
export JIKELOG_API_IMAGE="${1:?用法：run.sh <API 镜像>}"
eval "$(bash e2e-keys.sh | sed 's/^/export /')"
KMS_MASTER_KEY=$(openssl rand -base64 32)
export KMS_MASTER_KEY
mkdir -p results
chmod 777 results   # k6 容器以非 root 用户运行，需要能写入结果

dc() { docker compose -f compose.yml "$@"; }
cleanup() { dc --profile run down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

dc up -d postgres redis objectstore
dc run --rm -T --entrypoint jikelog-migrate api
dc up -d api
for _ in $(seq 1 30); do
  dc exec -T api wget -qO- http://127.0.0.1:8080/readyz >/dev/null 2>&1 && break
  sleep 2
done

status=0
dc --profile run run --rm k6 || status=$?
echo "== 资源占用（压测结束时）=="
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' $(dc ps -q) || true
exit "$status"
