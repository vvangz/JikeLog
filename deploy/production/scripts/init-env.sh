#!/usr/bin/env bash
# 生成或补全正式环境的配置（ADR-012），可以重复执行：已有的值一律保留，只补上缺少或为空的项。
#   .env        全部服务的配置与机密
#   backup.env  异地 OSS 的 AccessKey，只提供给 backup 服务（接口服务看不到）
# 用法：cd /root/jikelog && bash scripts/init-env.sh [域名，须以 www. 开头] [证书联系邮箱]
# 新生成的机密只写入文件（权限 600），不输出到终端；只输出 App 构建需要的传输加密公钥。
set -euo pipefail
umask 077

DOMAIN="${1:-www.pingvv.top}"
EMAIL="${2:-}"
ENV_FILE="${ENV_FILE:-.env}"
BACKUP_ENV_FILE="${BACKUP_ENV_FILE:-backup.env}"
# Caddyfile 把不带 www 的域名跳转到正式域名，两者必须不同
[[ "$DOMAIN" == www.* ]] || { echo "域名须以 www. 开头（不带 www 的域名会跳转过来）：$DOMAIN"; exit 1; }

touch "$ENV_FILE" "$BACKUP_ENV_FILE"
chmod 600 "$ENV_FILE" "$BACKUP_ENV_FILE"

get() { grep -E "^$1=" "${2:-$ENV_FILE}" | tail -1 | cut -d= -f2- || true; }
# set_default 在缺少或为空时写入；默认值为空时只补上空行，供管理员填写
set_default() { # 名称 默认值 [文件]
  local file="${3:-$ENV_FILE}"
  if ! grep -qE "^$1=" "$file"; then
    printf '%s=%s\n' "$1" "$2" >>"$file"
  elif [ -z "$(get "$1" "$file")" ] && [ -n "$2" ]; then
    sed -i "s|^$1=.*|$1=$2|" "$file"
  fi
}
rand_hex() { openssl rand -hex "$1"; }
rand_b64() { openssl rand -base64 32 | tr -d '\n'; }

# X25519 私钥：DER 编码的最后 32 字节即原始私钥
x25519_private() { openssl genpkey -algorithm X25519 -outform DER | tail -c 32 | base64 | tr -d '\n'; }
# 由原始私钥计算公钥（拼回 PKCS#8 DER 头部后交给 openssl）
x25519_public() {
  { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'; printf '%s' "$1" | base64 -d; } |
    openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64 | tr -d '\n'
}

set_default SITE_DOMAIN "$DOMAIN"
set_default SITE_DOMAIN_APEX "${DOMAIN#www.}"
set_default ACME_EMAIL "$EMAIL"

set_default POSTGRES_PASSWORD "$(rand_hex 24)"
set_default REDIS_PASSWORD "$(rand_hex 24)"
set_default S3_ACCESS_KEY "jikelog$(rand_hex 6)"
set_default S3_SECRET_KEY "$(rand_hex 24)"

set_default JIKELOG_ENV production
set_default JIKELOG_HTTP_ADDR :8080
set_default JIKELOG_HTTP_TRUSTED_PROXIES 172.30.0.0/24
set_default JIKELOG_LOG_FORMAT json
set_default JIKELOG_DB_URL "postgres://jikelog:$(get POSTGRES_PASSWORD)@postgres:5432/jikelog?sslmode=disable"
set_default JIKELOG_REDIS_URL "redis://:$(get REDIS_PASSWORD)@redis:6379/0"
set_default JIKELOG_AUTH_JWT_SECRET "$(rand_hex 32)"
set_default JIKELOG_SMS_PROVIDER disabled
set_default JIKELOG_CAPTCHA_PROVIDER none
set_default JIKELOG_PUSH_PROVIDER log
set_default JIKELOG_E2E_PRIVATE_KEY "$(x25519_private)"
set_default JIKELOG_KMS_PROVIDER local
set_default JIKELOG_KMS_LOCAL_MASTER_KEY "$(rand_b64)"
set_default JIKELOG_STORAGE_ENDPOINT http://objectstore:9000
set_default JIKELOG_STORAGE_PUBLIC_ENDPOINT "https://$(get SITE_DOMAIN)"
set_default JIKELOG_STORAGE_BUCKET jikelog
set_default JIKELOG_STORAGE_PATH_STYLE true
set_default JIKELOG_STORAGE_ACCESS_KEY "$(get S3_ACCESS_KEY)"
set_default JIKELOG_STORAGE_SECRET_KEY "$(get S3_SECRET_KEY)"
set_default JIKELOG_ATTACHMENT_QUOTA 8589934592 # 每个账号 8GB

set_default BACKUP_INTERVAL_DAYS 14
set_default BACKUP_KEEP 6
set_default BACKUP_AGE_RECIPIENT ""
set_default BACKUP_OSS_ENDPOINT "" "$BACKUP_ENV_FILE"
set_default BACKUP_OSS_BUCKET "" "$BACKUP_ENV_FILE"
set_default BACKUP_OSS_ACCESS_KEY_ID "" "$BACKUP_ENV_FILE"
set_default BACKUP_OSS_ACCESS_KEY_SECRET "" "$BACKUP_ENV_FILE"

echo "已写入 $ENV_FILE 与 $BACKUP_ENV_FILE（权限 600）。"
echo "App 构建参数：--dart-define=JIKELOG_E2E_PUBLIC_KEY=$(x25519_public "$(get JIKELOG_E2E_PRIVATE_KEY)")"
[ -n "$(get BACKUP_AGE_RECIPIENT)" ] || echo "提醒：尚未设置 BACKUP_AGE_RECIPIENT，备份无法加密，backup 服务不会执行备份。"
[ -n "$(get ACME_EMAIL)" ] || echo "提醒：尚未设置 ACME_EMAIL（证书到期提醒的联系邮箱）。"
