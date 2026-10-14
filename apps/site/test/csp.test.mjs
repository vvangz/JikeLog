import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { addCsp } from '../lib/csp.mjs';

const hash = (s) => `'sha256-${createHash('sha256').update(s, 'utf8').digest('base64')}'`;

const page = (body) =>
  `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>t</title>${body}</head><body></body></html>`;

// 测试中把这两段当作"已知的 VitePress 内联脚本"
const A = 'window.__a = 1;';
const B = '\n;(() => { document.documentElement.classList.add("dark") })()\n';
const KNOWN = new Set([hash(A), hash(B)]);

test('addCsp 在 charset 之后插入 CSP，并按哈希放行已知的内联脚本', () => {
  const html = addCsp(
    page(`<script>${A}</script><script id="check-dark-mode">${B}</script><script type="module" src="/assets/app.js"></script>`),
    { known: KNOWN },
  );
  const meta = html.match(/<meta http-equiv="Content-Security-Policy" content="([^"]+)">/);
  assert.ok(meta, '有 CSP');
  assert.ok(html.indexOf('<meta charset="utf-8">') < html.indexOf('Content-Security-Policy'), 'CSP 在 charset 之后');
  assert.ok(html.indexOf('Content-Security-Policy') < html.indexOf('<script'), 'CSP 在所有脚本之前');
  const policy = meta[1];
  assert.match(policy, /script-src 'self' /);
  assert.ok(policy.includes(hash(A)));
  assert.ok(policy.includes(hash(B)));
  assert.doesNotMatch(policy, /script-src[^;]*unsafe-inline/);
  assert.match(policy, /object-src 'none'/);
  assert.match(policy, /base-uri 'self'/);
});

test('addCsp 遇到未知的内联脚本时报错，不把它放进白名单（例如混进文档的 <script>）', () => {
  assert.throws(
    () => addCsp(page(`<script>${A}</script><script id="check-dark-mode">fetch('/api/admin/v1/auth/refresh')</script>`), { known: KNOWN }),
    /未知的内联脚本/,
  );
});

test('addCsp 默认使用内置的 VitePress 内联脚本哈希', () => {
  assert.throws(() => addCsp(page(`<script>${A}</script>`)), /未知的内联脚本/);
});

test('addCsp 没有内联脚本时只允许本站脚本', () => {
  const html = addCsp(page('<script type="module" src="/a.js"></script>'), { known: KNOWN });
  assert.match(html, /script-src 'self';/);
});

test('addCsp 找不到 charset 时报错，而不是生成没有 CSP 的页面', () => {
  assert.throws(() => addCsp('<html><head></head></html>', { known: KNOWN }), /charset/);
});
