#!/usr/bin/env bash
# 为压测生成传输加密所需的密钥（ADR-006），只依赖 OpenSSL 3：
#   - 服务端私钥（写入压测环境的 JIKELOG_E2E_PRIVATE_KEY）
#   - 客户端临时密钥对，以及与 App 相同的派生方式算出的会话密钥：
#     HKDF-SHA256(X25519(客户端私钥, 服务端公钥), salt = 客户端公钥 ‖ 服务端公钥, info = "jikelog-e2e-v1")
# 输出 shell 变量赋值，供 run.sh 用 eval 读入。压测脚本用会话密钥直接做 AES-256-GCM，不需要在 k6 中实现 X25519。
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

raw_pub() { openssl pkey -in "$1" -pubout -outform DER | tail -c 32; }
raw_priv() { openssl pkey -in "$1" -outform DER | tail -c 32; }

openssl genpkey -algorithm X25519 -out "$work/server.pem" 2>/dev/null
openssl genpkey -algorithm X25519 -out "$work/client.pem" 2>/dev/null
raw_pub "$work/server.pem" >"$work/server.pub"
raw_pub "$work/client.pem" >"$work/client.pub"
openssl pkey -in "$work/server.pem" -pubout -out "$work/server-pub.pem"

openssl pkeyutl -derive -inkey "$work/client.pem" -peerkey "$work/server-pub.pem" -out "$work/shared"
hex() { od -An -v -tx1 "$1" | tr -d ' \n'; }
salt="$(hex "$work/client.pub")$(hex "$work/server.pub")"
session_hex=$(openssl kdf -keylen 32 -kdfopt digest:SHA256 -kdfopt "hexkey:$(hex "$work/shared")" \
  -kdfopt "hexsalt:$salt" -kdfopt info:jikelog-e2e-v1 HKDF | tr -d ':\n' | tr 'A-F' 'a-f')

echo "E2E_SERVER_PRIVATE_KEY=$(raw_priv "$work/server.pem" | base64 | tr -d '\n')"
echo "E2E_SERVER_KEY_ID=$(openssl dgst -sha256 -binary "$work/server.pub" | head -c 8 | od -An -v -tx1 | tr -d ' \n')"
echo "E2E_CLIENT_PUBLIC_KEY=$(base64 <"$work/client.pub" | tr -d '\n')"
echo "E2E_SESSION_KEY=$(printf '%s' "$session_hex" | xxd -r -p | base64 | tr -d '\n')"
