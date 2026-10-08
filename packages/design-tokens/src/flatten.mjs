// 把嵌套令牌对象展开为 [[路径数组, 值], ...]
export function flatten(obj, prefix = []) {
  return Object.entries(obj).flatMap(([k, v]) =>
    v !== null && typeof v === 'object' ? flatten(v, [...prefix, k]) : [[[...prefix, k], v]],
  );
}

const cap = (s) => s[0].toUpperCase() + s.slice(1);

export const camel = (parts) => parts.map((p, i) => (i === 0 ? p : cap(p))).join('');

export const kebab = (parts) =>
  parts
    .map((p) => p.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase())
    .join('-');

export const HEADER_LINES = [
  'GENERATED CODE - DO NOT MODIFY BY HAND',
  '来源：packages/design-tokens/tokens，修改令牌后运行 `pnpm tokens` 重新生成。',
];
