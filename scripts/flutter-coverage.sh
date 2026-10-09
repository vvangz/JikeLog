#!/usr/bin/env bash
# 运行 Flutter 测试并校验覆盖率（不含 *.g.dart）。
# flutter 的 lcov 只包含被测试引用到的文件，因此先生成一个引用 lib 下全部文件的辅助测试，
# 让没有任何测试的文件以 0% 计入，而不是被忽略。
# 用法：bash scripts/flutter-coverage.sh [最低覆盖率，默认 80]
# 额外参数通过 FLUTTER_TEST_ARGS 传入；Windows 上并行启动测试进程偶尔会失败，可设为 --concurrency=1
set -euo pipefail

MIN="${1:-80}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/apps/mobile"

PKG="$(awk '/^name:/ {print $2; exit}' pubspec.yaml)"
HELPER="test/coverage_helper_test.dart"
trap 'rm -f "$HELPER"' EXIT

{
  echo "// 由 scripts/flutter-coverage.sh 生成，勿提交。"
  echo "// ignore_for_file: unused_import, directives_ordering"
  find lib -name '*.dart' ! -name '*.g.dart' | sort | sed "s#^lib/\(.*\)#import 'package:${PKG}/\1';#"
  echo "void main() {}"
} > "$HELPER"

# shellcheck disable=SC2086 # 允许传入多个参数
flutter test --coverage ${FLUTTER_TEST_ARGS:-}

awk -F: -v min="$MIN" '
  /^SF:/ { skip = ($2 ~ /\.g\.dart$/) }
  /^LF:/ { if (!skip) lf += $2 }
  /^LH:/ { if (!skip) lh += $2 }
  END {
    p = (lf > 0) ? lh * 100 / lf : 0
    printf "Flutter 覆盖率：%.1f%%（%d/%d 行，要求 ≥ %s%%）\n", p, lh, lf, min
    exit (p >= min) ? 0 : 1
  }' coverage/lcov.info
