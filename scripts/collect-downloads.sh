#!/usr/bin/env bash
# 部署工作流调用（ADR-014）：从某个版本的 GitHub Release 取安装包，核对后生成 latest.json，打包为 downloads.tar.gz。
#   bash scripts/collect-downloads.sh <版本> <输出目录>
#
# 环境变量：
#   GH_TOKEN、GITHUB_REPOSITORY        读取 Release
#   APK_CERT_SHA256                    APK 签名证书的 SHA-256（仓库变量，必填）
#   WINDOWS_CERT_THUMBPRINT            Windows 证书的 SHA-1 指纹（仓库变量，必填）
#   EXPECT_APK_SHA256、EXPECT_MSIX_SHA256
#                                      签名任务计算的安装包校验值（发布时由 release-please.yml 传入；手动部署时为空）
#
# Release 中没有任何安装包时只给出警告，不生成 downloads.tar.gz（官网下载页保持上一个版本）。
# 安装包被替换、证书不符时失败：宁可不部署，也不能把来历不明的安装包放到官网上。
set -euo pipefail

VERSION="${1:?用法：collect-downloads.sh <版本> <输出目录>}"
OUT="${2:?用法：collect-downloads.sh <版本> <输出目录>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "::error::版本号不合法：$VERSION"; exit 1; }

norm() { tr -d ': \r\n' | tr '[:upper:]' '[:lower:]'; } # 去掉冒号与空白，统一小写
apk_cert=$(printf '%s' "${APK_CERT_SHA256:-}" | norm)
win_cert=$(printf '%s' "${WINDOWS_CERT_THUMBPRINT:-}" | norm)
# 变量为空时任何证书都会"通过"核对
[ -n "$apk_cert" ] && [ -n "$win_cert" ] ||
  { echo "::error::未设置仓库变量 APK_CERT_SHA256 或 WINDOWS_CERT_THUMBPRINT"; exit 1; }

# 只取这几个文件；Release 中的其他附件不会进入下载目录
NAMES=("jikelog-$VERSION.apk" "jikelog-$VERSION.apk.sha256" "jikelog-$VERSION.msix" "jikelog-$VERSION.msix.sha256" "jikelog-windows.cer")

# 先列出 Release 中的附件：区分"没有安装包"（跳过）与"下载失败"（报错）
assets=$(gh release view "v$VERSION" --repo "$GITHUB_REPOSITORY" --json assets -q '.assets[].name')
published=$(gh release view "v$VERSION" --repo "$GITHUB_REPOSITORY" --json publishedAt -q '.publishedAt')
patterns=()
for n in "${NAMES[@]}"; do
  if grep -qxF "$n" <<<"$assets"; then patterns+=(--pattern "$n"); fi
done
if [ ${#patterns[@]} -eq 0 ]; then
  echo "::warning::v$VERSION 的 Release 中没有安装包，官网下载页保持上一个版本"
  exit 0
fi

dl=$(mktemp -d)
trap 'rm -rf "$dl"' EXIT
gh release download "v$VERSION" --repo "$GITHUB_REPOSITORY" --dir "$dl" "${patterns[@]}"

# 与签名任务输出的校验值核对：.sha256 与安装包同在 Release 中，不能证明安装包在签名后没有被替换
expect() { # 文件名 期望的 SHA-256
  local file="$dl/$1" want
  [ -f "$file" ] || return 0
  want=$(printf '%s' "$2" | norm)
  if [ -z "$want" ]; then
    echo "::warning::没有签名任务提供的 $1 校验值（手动部署），只核对 Release 中的 .sha256 与签名证书"
    return 0
  fi
  [[ "$want" =~ ^[0-9a-f]{64}$ ]] || { echo "::error::$1 的期望校验值格式不对"; exit 1; }
  [ "$(sha256sum "$file" | cut -d' ' -f1)" = "$want" ] ||
    { echo "::error::$1 与签名任务输出的校验值不符，Release 中的文件可能被替换"; exit 1; }
}
expect "jikelog-$VERSION.apk" "${EXPECT_APK_SHA256:-}"
expect "jikelog-$VERSION.msix" "${EXPECT_MSIX_SHA256:-}"

apk="$dl/jikelog-$VERSION.apk"
if [ -f "$apk" ]; then
  apksigner=$(find "${ANDROID_HOME:?未设置 ANDROID_HOME}/build-tools" -name apksigner -type f | sort -V | tail -1)
  # apksigner 输出"Signer #1 certificate SHA-256 digest: <小写十六进制>"，整行比对。
  # 先取完整输出再匹配：直接接 grep -q 时，grep 匹配后退出，apksigner 继续写入会被 SIGPIPE 终止，
  # 在 pipefail 下整条管道算作失败（v1.2.0 部署因此误报证书不符）
  certs=$("$apksigner" verify --print-certs "$apk") ||
    { echo "::error::apksigner 校验 APK 签名失败"; exit 1; }
  grep -qxF "Signer #1 certificate SHA-256 digest: $apk_cert" <<<"$certs" ||
    { echo "::error::APK 的签名证书与 APK_CERT_SHA256 不符：$(grep 'SHA-256 digest' <<<"$certs" || echo 无)"; exit 1; }
fi
cer="$dl/jikelog-windows.cer"
if [ -f "$cer" ]; then
  got=$(openssl x509 -inform DER -in "$cer" -noout -fingerprint -sha1 | cut -d= -f2 | norm)
  [ "$got" = "$win_cert" ] ||
    { echo "::error::证书 jikelog-windows.cer 的指纹 $got 与 WINDOWS_CERT_THUMBPRINT 不符"; exit 1; }
fi

node "$(dirname "$0")/../apps/site/scripts/make-manifest.mjs" "$dl" "$VERSION" "$published"
mkdir -p "$OUT"
tar -czf "$OUT/downloads.tar.gz" -C "$dl" .
echo "✔ downloads.tar.gz：$(ls "$dl" | tr '\n' ' ')"
