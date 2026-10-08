// 生成 Web 端令牌：CSS 变量（主题切换用 data-theme）与 TypeScript 常量（供 Ant Design 主题使用）
import { flatten, HEADER_LINES, kebab } from './flatten.mjs';

const PX_GROUPS = ['font.size', 'spacing', 'radius', 'breakpoint'];

function cssValue(parts, value) {
  const key = parts.join('.');
  if (PX_GROUPS.some((g) => key.startsWith(`${g}.`))) return `${value}px`;
  if (key.startsWith('motion.duration.')) return `${value}ms`;
  return String(value);
}

const colorVars = (colors) =>
  Object.entries(colors).map(([k, v]) => `  --jk-color-${kebab([k])}: ${v};`);

function sharedVars(shared) {
  const { latin, cjk } = shared.font.family;
  const vars = flatten(shared)
    .filter(([parts]) => parts.slice(0, 2).join('.') !== 'font.family')
    .map(([parts, v]) => `  --jk-${kebab(parts)}: ${cssValue(parts, v)};`);
  return [`  --jk-font-family: '${latin}', '${cjk}', sans-serif;`, ...vars];
}

export function emitCss({ light, dark, shared }) {
  return [
    `/* ${HEADER_LINES.join(' ')} */`,
    '',
    ':root {',
    '  color-scheme: light;',
    ...colorVars(light),
    ...sharedVars(shared),
    '}',
    '',
    ":root[data-theme='dark'] {",
    '  color-scheme: dark;',
    ...colorVars(dark),
    '}',
    '',
  ].join('\n');
}

export function emitTs({ light, dark, shared }) {
  const json = (v) => JSON.stringify(v, null, 2);
  return [
    ...HEADER_LINES.map((l) => `// ${l}`),
    '',
    `export const colors = ${json({ light, dark })} as const;`,
    '',
    'export type ThemeName = keyof typeof colors;',
    'export type ColorTokens = Record<keyof typeof colors.light, string>;',
    '',
    `export const tokens = ${json(shared)} as const;`,
    '',
  ].join('\n');
}
