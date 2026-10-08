// 生成 Flutter 端令牌：JkColorTokens（深浅两套） + JkTokens（与主题无关）
import { hexToDartColor } from './color.mjs';
import { camel, flatten, HEADER_LINES } from './flatten.mjs';

const header = () => HEADER_LINES.map((l) => `// ${l}`).join('\n');

function assertSameKeys(light, dark) {
  const l = Object.keys(light).sort();
  const d = Object.keys(dark).sort();
  const onlyLight = l.filter((k) => !d.includes(k));
  const onlyDark = d.filter((k) => !l.includes(k));
  if (onlyLight.length || onlyDark.length) {
    throw new Error(
      `深色与浅色主题字段不一致：仅浅色 [${onlyLight.join(', ')}]，仅深色 [${onlyDark.join(', ')}]`,
    );
  }
}

function colorClass(light, dark) {
  assertSameKeys(light, dark);
  const names = Object.keys(light);
  const instance = (colors) =>
    names.map((n) => `    ${n}: ${hexToDartColor(colors[n])},`).join('\n');
  return [
    '/// 主题颜色令牌，浅色与深色两套字段完全一致。',
    'final class JkColorTokens {',
    '  const JkColorTokens({',
    ...names.map((n) => `    required this.${n},`),
    '  });',
    '',
    ...names.map((n) => `  final Color ${n};`),
    '',
    `  static const light = JkColorTokens(\n${instance(light)}\n  );`,
    '',
    `  static const dark = JkColorTokens(\n${instance(dark)}\n  );`,
    '}',
  ].join('\n');
}

function dartConst(parts, value) {
  const name = camel(parts);
  const group = parts.slice(0, 2).join('.');
  if (group === 'font.family') return `static const String ${name} = '${value}';`;
  if (group === 'font.weight') {
    if (!Number.isInteger(value) || value < 100 || value > 900 || value % 100 !== 0) {
      throw new Error(`字重 ${parts.join('.')}=${value} 不合法，需为 100–900 的整百数`);
    }
    return `static const FontWeight ${name} = FontWeight.w${value};`;
  }
  if (group === 'motion.duration') {
    return `static const Duration ${name} = Duration(milliseconds: ${value});`;
  }
  return `static const double ${name} = ${value};`;
}

function sharedClass(shared) {
  const lines = flatten(shared).map(([parts, v]) => `  ${dartConst(parts, v)}`);
  return ['/// 与主题无关的字体、间距、圆角、动效、断点令牌。', 'abstract final class JkTokens {', ...lines, '}'].join('\n');
}

export function emitDart({ light, dark, shared }) {
  return [
    header(),
    '',
    "import 'dart:ui';",
    '',
    colorClass(light, dark),
    '',
    sharedClass(shared),
    '',
  ].join('\n');
}
