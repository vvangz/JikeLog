#!/usr/bin/env bash
# 下载项目字体并复制到各端目录。
#
# MiSans 许可协议禁止单独再分发字体文件（允许打包进 App 使用，但需在软件中注明），
# 因此字体不入库，统一由本脚本从官方渠道下载：
#   - Space Grotesk 2.0.0（SIL OFL 1.1）：github.com/floriankarsten/space-grotesk
#   - MiSans（小米 MiSans 字体知识产权许可协议）：hyperos.mi.com/font
#
# 用法：bash scripts/fetch-fonts.sh       （已有缓存时不会重复下载）
#       FONT_CACHE_DIR=/path bash scripts/fetch-fonts.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${FONT_CACHE_DIR:-$ROOT/.cache/fonts}"

SG_VERSION="2.0.0"
SG_URL="https://github.com/floriankarsten/space-grotesk/releases/download/${SG_VERSION}/SpaceGrotesk-${SG_VERSION}.zip"
MISANS_URL="https://hyperos.mi.com/font-download/MiSans.zip"

# 固定校验和：官方文件变化时脚本会失败，需人工确认后更新（MiSans.zip 于 2025-07-14 发布）
SG_SHA256="53b415577d4139248555300710bea0d268c7a5be67b93de53b716a9736cabffd"
MISANS_SHA256="b6aa1fc827035922612df8edf36e5609bca1c5441e25cd57572204569b7b81d9"

MOBILE_DIR="$ROOT/apps/mobile/assets/fonts"
WEB_DIR="$ROOT/apps/admin-web/public/fonts"

# 移动端只打包常用字重以控制 APK 体积（MiSans 单个字重约 8MB）
SG_WEIGHTS=(Regular Medium Bold)
MISANS_WEIGHTS=(Regular Semibold)

log() { printf '\033[36m[fonts]\033[0m %s\n' "$*"; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# 下载并校验；缓存文件校验失败时删除重下
download() {
  local url="$1" out="$2" want="$3"
  if [[ -s "$out" && "$(sha256_of "$out")" == "$want" ]]; then
    log "使用缓存 $(basename "$out")"
    return
  fi
  rm -f "$out"
  log "下载 $url"
  curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$out.part" "$url"
  local got
  got="$(sha256_of "$out.part")"
  if [[ "$got" != "$want" ]]; then
    rm -f "$out.part"
    echo "❌ 校验失败：$(basename "$out") sha256=$got，期望 $want" >&2
    exit 1
  fi
  mv "$out.part" "$out"
}

# 从 zip 中按路径解压单个文件到目标目录
extract() {
  local zip="$1" entry="$2" dest="$3"
  unzip -o -j -q "$zip" "$entry" -d "$dest"
}

main() {
  mkdir -p "$CACHE" "$MOBILE_DIR" "$WEB_DIR"
  local sg_zip="$CACHE/SpaceGrotesk-${SG_VERSION}.zip"
  local mi_zip="$CACHE/MiSans.zip"
  download "$SG_URL" "$sg_zip" "$SG_SHA256"
  download "$MISANS_URL" "$mi_zip" "$MISANS_SHA256"

  for w in "${SG_WEIGHTS[@]}"; do
    extract "$sg_zip" "SpaceGrotesk-${SG_VERSION}/ttf/static/SpaceGrotesk-${w}.ttf" "$MOBILE_DIR"
    extract "$sg_zip" "SpaceGrotesk-${SG_VERSION}/woff2/static/SpaceGrotesk-${w}.woff2" "$WEB_DIR"
  done
  extract "$sg_zip" "SpaceGrotesk-${SG_VERSION}/OFL.txt" "$MOBILE_DIR"

  for w in "${MISANS_WEIGHTS[@]}"; do
    extract "$mi_zip" "MiSans/ttf/MiSans-${w}.ttf" "$MOBILE_DIR"
    extract "$mi_zip" "MiSans/woff2/MiSans-${w}.woff2" "$WEB_DIR"
  done

  log "完成：$MOBILE_DIR"
  log "完成：$WEB_DIR"
}

main "$@"
