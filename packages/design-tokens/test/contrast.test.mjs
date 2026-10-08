import { test } from 'node:test';
import assert from 'node:assert/strict';
import { contrastRatio } from '../src/color.mjs';
import { loadTheme } from '../src/load.mjs';

// WCAG 2.2：正文 ≥ 4.5，非文本 UI 元素 ≥ 3
const TEXT = 4.5;
const UI = 3;
const STATUSES = ['success', 'warning', 'error', 'info'];

const pairs = (c) => [
  ['textPrimary', 'background', 7],
  ['textPrimary', 'surface', 7],
  ['textSecondary', 'background', TEXT],
  ['textSecondary', 'surface', TEXT],
  ['textSecondary', 'surfaceVariant', TEXT],
  ['onPrimary', 'primary', TEXT],
  ['onPrimaryContainer', 'primaryContainer', TEXT],
  ['primary', 'background', UI],
  ['primary', 'surface', UI],
  ['border', 'surface', 1.5],
  ...STATUSES.flatMap((s) => {
    const cap = s[0].toUpperCase() + s.slice(1);
    return [
      [`on${cap}`, s, TEXT],
      [`on${cap}Container`, `${s}Container`, TEXT],
      [s, 'surface', UI],
    ];
  }),
].map(([fg, bg, min]) => ({ fg, bg, min, ratio: contrastRatio(c[fg], c[bg]) }));

for (const theme of ['light', 'dark']) {
  test(`${theme} 主题颜色对比度满足 WCAG`, async () => {
    const { colors } = await loadTheme(theme);
    const failures = pairs(colors).filter((p) => p.ratio < p.min);
    assert.deepEqual(
      failures.map((f) => `${f.fg}/${f.bg}=${f.ratio.toFixed(2)} < ${f.min}`),
      [],
    );
  });
}

test('浅色与深色主题定义了完全相同的颜色字段', async () => {
  const light = Object.keys((await loadTheme('light')).colors).sort();
  const dark = Object.keys((await loadTheme('dark')).colors).sort();
  assert.deepEqual(dark, light);
});

test('未知主题名报错', async () => {
  await assert.rejects(() => loadTheme('sepia'), /未知主题/);
});
