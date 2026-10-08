import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emitDart } from '../src/emit-dart.mjs';
import { emitCss, emitTs } from '../src/emit-web.mjs';

const input = {
  light: { primary: '#6F4E37', textPrimary: '#2A2420' },
  dark: { primary: '#C8A27C', textPrimary: '#EDE6DF' },
  shared: {
    font: { family: { latin: 'Space Grotesk', cjk: 'MiSans' }, size: { body: 14 } },
    spacing: { sm: 8 },
    radius: { md: 10 },
    motion: { duration: { slow: 320 } },
    breakpoint: { medium: 600 },
  },
};

test('emitDart 生成不可变颜色类及深浅两套常量', () => {
  const dart = emitDart(input);
  assert.match(dart, /GENERATED CODE - DO NOT MODIFY BY HAND/);
  assert.match(dart, /final class JkColorTokens/);
  assert.match(dart, /final Color primary;/);
  assert.match(dart, /static const light = JkColorTokens\(\s*primary: Color\(0xFF6F4E37\),/);
  assert.match(dart, /static const dark = JkColorTokens\(\s*primary: Color\(0xFFC8A27C\),/);
  assert.match(dart, /static const double spacingSm = 8;/);
  assert.match(dart, /static const String fontFamilyLatin = 'Space Grotesk';/);
  assert.match(dart, /static const Duration motionDurationSlow = Duration\(milliseconds: 320\);/);
});

test('emitCss 输出 :root 浅色与 data-theme=dark 深色变量', () => {
  const css = emitCss(input);
  assert.match(css, /:root \{[^}]*--jk-color-primary: #6F4E37;/s);
  assert.match(css, /:root\[data-theme='dark'\] \{[^}]*--jk-color-primary: #C8A27C;/s);
  assert.match(css, /--jk-spacing-sm: 8px;/);
  assert.match(css, /--jk-font-family: 'Space Grotesk', 'MiSans', sans-serif;/);
});

test('emitTs 输出带类型的只读常量', () => {
  const ts = emitTs(input);
  assert.match(ts, /export const colors = \{/);
  assert.match(ts, /"primary": "#6F4E37"/);
  assert.match(ts, /\} as const;/);
  assert.match(ts, /export type ColorTokens = Record<keyof typeof colors.light, string>;/);
});

test('emitDart 在深浅主题字段不一致时报错，而不是静默丢弃', () => {
  const broken = { ...input, dark: { primary: '#C8A27C', extra: '#000000' } };
  assert.throws(() => emitDart(broken), /深色与浅色主题字段不一致.*textPrimary.*extra/);
});

test('emitDart 拒绝非法字重', () => {
  const broken = { ...input, shared: { ...input.shared, font: { ...input.shared.font, weight: { odd: 450 } } } };
  assert.throws(() => emitDart(broken), /字重.*450/);
});
