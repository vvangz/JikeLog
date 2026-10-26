import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { cjkChars, DISPLAY_FONT, headingText, verifySha256 } from '../lib/display-font.mjs';

test('headingText 只取 h1–h3 的文字，去掉内部标签', () => {
  const html =
    '<h1 class="t">下载<span>即刻</span>日志</h1><p>正文不算</p>' +
    '<h2 id="a">安装 <a class="header-anchor" href="#a">#</a></h2><h4>四级不算</h4>' +
    '<H3>大写标签</H3>';
  assert.equal(headingText(html), '下载即刻日志安装 #大写标签');
});

test('cjkChars 只保留中文与全角标点，去重排序', () => {
  assert.equal(cjkChars('日志 Android，日志！abc 123·—'), '！，志日'.split('').sort().join(''));
  assert.equal(cjkChars('only latin'), '');
});

test('verifySha256 一致时通过，不一致时报错', () => {
  const buf = Buffer.from('font');
  verifySha256(buf, createHash('sha256').update(buf).digest('hex'));
  assert.throws(() => verifySha256(buf, '0'.repeat(64)), /校验失败/);
});

test('源字体固定到具体提交并带校验值', () => {
  assert.match(DISPLAY_FONT.url, /\/google\/fonts\/[0-9a-f]{40}\//);
  assert.match(DISPLAY_FONT.sha256, /^[0-9a-f]{64}$/);
  assert.ok(DISPLAY_FONT.weight.min <= 500 && DISPLAY_FONT.weight.max >= 600);
});
