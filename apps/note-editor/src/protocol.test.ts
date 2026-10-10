import { describe, expect, it } from 'vitest';

import { attachmentId, isSafeLink, MAX_MARKDOWN, parseInbound } from './protocol';

const ID = '0190a1b2-0000-7000-8000-000000000001';
const theme = { dark: false, colors: { text: '#2b211b', 'surface-variant': '#f1ebe2' } };

describe('parseInbound', () => {
  it.each([
    [{ type: 'init', markdown: '# 你好', placeholder: '写点什么', theme }],
    [{ type: 'setMarkdown', markdown: '' }],
    [{ type: 'theme', theme: { dark: true, colors: {} } }],
    [{ type: 'command', name: 'bold' }],
    [{ type: 'command', name: 'insertTable' }],
    [{ type: 'insertImage', id: ID, alt: '截图.png' }],
    [{ type: 'image', id: ID, dataUrl: 'data:image/png;base64,iVBORw0KGgo=' }],
    [{ type: 'image', id: ID, dataUrl: null }],
    [{ type: 'focus' }],
  ])('接受合法消息 %j', (m) => {
    expect(parseInbound(JSON.stringify(m))).toEqual(m);
  });

  it('链接去掉首尾空白', () => {
    expect(parseInbound(JSON.stringify({ type: 'setLink', href: ' https://example.com ' }))).toEqual({
      type: 'setLink',
      href: 'https://example.com',
    });
  });

  it.each([
    ['不是 JSON', '{'],
    ['不是对象', '[]'],
    ['未知类型', JSON.stringify({ type: 'eval', code: 'alert(1)' })],
    ['未知命令', JSON.stringify({ type: 'command', name: 'deleteEverything' })],
    ['正文不是字符串', JSON.stringify({ type: 'setMarkdown', markdown: 1 })],
    ['正文超长', JSON.stringify({ type: 'setMarkdown', markdown: 'a'.repeat(MAX_MARKDOWN + 1) })],
    ['主题颜色不是十六进制', JSON.stringify({ type: 'theme', theme: { dark: false, colors: { text: 'red;}' } } })],
    ['主题变量名非法', JSON.stringify({ type: 'theme', theme: { dark: false, colors: { 'a;b': '#000000' } } })],
    ['主题缺少 dark', JSON.stringify({ type: 'theme', theme: { colors: {} } })],
    ['初始化缺少主题', JSON.stringify({ type: 'init', markdown: '', placeholder: '' })],
    ['javascript 链接', JSON.stringify({ type: 'setLink', href: 'javascript:alert(1)' })],
    ['data 链接', JSON.stringify({ type: 'setLink', href: 'data:text/html,<script>' })],
    ['图片 ID 不是 UUID', JSON.stringify({ type: 'insertImage', id: '../etc/passwd', alt: '' })],
    ['图片不是 data 地址', JSON.stringify({ type: 'image', id: ID, dataUrl: 'https://evil.example/x.png' })],
    ['图片是 SVG', JSON.stringify({ type: 'image', id: ID, dataUrl: 'data:image/svg+xml;base64,PHN2Zz4=' })],
  ])('拒绝%s', (_, raw) => {
    expect(parseInbound(raw)).toBeNull();
  });
});

describe('attachmentId', () => {
  it('取出附件 ID', () => {
    expect(attachmentId(`attachment:${ID}`)).toBe(ID);
  });

  it.each([null, undefined, '', 'https://example.com/a.png', 'attachment:abc', `attachment:${ID}/x`])(
    '%j 不是附件引用',
    (src) => {
      expect(attachmentId(src)).toBeNull();
    },
  );
});

describe('isSafeLink', () => {
  it.each(['https://example.com', 'http://a.b', 'mailto:a@b.c', 'tel:10086', 'HTTPS://EXAMPLE.COM'])('%s 安全', (h) => {
    expect(isSafeLink(h)).toBe(true);
  });

  it.each(['javascript:alert(1)', 'file:///etc/passwd', 'attachment:x', 'https://a.b/' + 'x'.repeat(3000)])(
    '%s 不安全',
    (h) => {
      expect(isSafeLink(h)).toBe(false);
    },
  );
});
