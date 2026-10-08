import { test } from 'node:test';
import assert from 'node:assert/strict';
import { contrastRatio, hexToDartColor, parseHex } from '../src/color.mjs';

test('parseHex 支持 6 位与 8 位十六进制', () => {
  assert.deepEqual(parseHex('#6F4E37'), { r: 0x6f, g: 0x4e, b: 0x37, a: 0xff });
  assert.deepEqual(parseHex('#0000007A'), { r: 0, g: 0, b: 0, a: 0x7a });
});

test('parseHex 拒绝非法输入', () => {
  assert.throws(() => parseHex('red'), /非法颜色/);
  assert.throws(() => parseHex('#12345'), /非法颜色/);
});

test('hexToDartColor 输出 0xAARRGGBB', () => {
  assert.equal(hexToDartColor('#6F4E37'), 'Color(0xFF6F4E37)');
  assert.equal(hexToDartColor('#0000007A'), 'Color(0x7A000000)');
});

test('contrastRatio 黑白为 21，同色为 1', () => {
  assert.equal(contrastRatio('#000000', '#FFFFFF').toFixed(2), '21.00');
  assert.equal(contrastRatio('#6F4E37', '#6F4E37'), 1);
});

test('contrastRatio 与参数顺序无关', () => {
  assert.equal(contrastRatio('#6F4E37', '#FFFFFF'), contrastRatio('#FFFFFF', '#6F4E37'));
});

test('深色主题文字色引用色板而非硬编码', async () => {
  const { readFile } = await import('node:fs/promises');
  const dark = JSON.parse(await readFile(new URL('../tokens/themes/dark.json', import.meta.url), 'utf8'));
  const literals = Object.entries(dark.color)
    .filter(([k, v]) => !k.startsWith('$') && !v.$value.startsWith('{') && k !== 'scrim')
    .map(([k]) => k);
  assert.deepEqual(literals, []);
});
