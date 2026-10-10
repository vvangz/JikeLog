import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { CHANGE_DEBOUNCE_MS, createBridge, type Bridge } from './bridge';
import { cspScriptHashes } from './csp';
import { inlineBuild } from './inline';
import { fontFaceCss, installFonts } from './fonts';
import type { Outbound } from './protocol';

const ID = '0190a1b2-0000-7000-8000-000000000001';
const theme = { dark: true, colors: { text: '#f5efe8', primary: '#c8a27c' } };

let sent: Outbound[];
let bridge: Bridge;
let root: HTMLElement;

const send = (m: object) => bridge.receive(JSON.stringify(m));
const last = (type: Outbound['type']) => sent.filter((m) => m.type === type).at(-1);

beforeEach(() => {
  vi.useFakeTimers();
  sent = [];
  root = document.createElement('div');
  const element = document.createElement('div');
  document.body.append(element);
  bridge = createBridge({ element, post: (json) => sent.push(JSON.parse(json) as Outbound), root });
});

afterEach(() => {
  vi.useRealTimers();
  document.body.innerHTML = '';
});

describe('bridge', () => {
  it('加载后通知 Flutter 已就绪', () => {
    expect(sent[0]).toEqual({ type: 'ready' });
  });

  it('初始化：应用主题并上报格式状态', () => {
    send({ type: 'init', markdown: '# 标题', placeholder: '写点什么', theme });
    expect(root.dataset.theme).toBe('dark');
    expect(root.style.getPropertyValue('--jk-primary')).toBe('#c8a27c');
    expect(last('state')).toMatchObject({ state: { heading: 1, canUndo: false } });
  });

  it('切换主题', () => {
    send({ type: 'theme', theme: { dark: false, colors: { text: '#000000' } } });
    expect(root.dataset.theme).toBe('light');
  });

  it('用户编辑后防抖发送 Markdown', () => {
    send({ type: 'init', markdown: '内容', placeholder: '', theme });
    send({ type: 'command', name: 'heading2' });
    send({ type: 'command', name: 'bold' });
    expect(last('change')).toBeUndefined();
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    expect(sent.filter((m) => m.type === 'change')).toEqual([{ type: 'change', markdown: '## 内容', rev: 1 }]);
  });

  it('flush 立即返回尚未发送的修改并计入序号；没有修改时返回 null', () => {
    send({ type: 'init', markdown: '内容', placeholder: '', theme });
    expect(bridge.flush()).toBeNull();
    send({ type: 'command', name: 'blockquote' });
    expect(bridge.flush()).toEqual({ md: '> 内容', rev: 1 });
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    expect(last('change')).toBeUndefined();
  });

  it('没有 Flutter 尚未收到的修改时，按序号替换为远端内容', () => {
    send({ type: 'init', markdown: '内容', placeholder: '', theme });
    send({ type: 'setMarkdown', markdown: '其他设备的内容', expectRev: 0 });
    expect(last('setRejected')).toBeUndefined();
    expect(sent.at(-1)).toEqual({ type: 'setApplied' });
    send({ type: 'command', name: 'heading1' });
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    expect(last('change')).toEqual({ type: 'change', markdown: '# 其他设备的内容', rev: 1 });
    send({ type: 'setMarkdown', markdown: '合并后', expectRev: 1 });
    expect(bridge.flush()).toBeNull();
    send({ type: 'command', name: 'heading2' });
    expect(bridge.flush()).toEqual({ md: '## 合并后', rev: 2 });
  });

  it('有尚未发出的修改时拒绝替换：先发出修改，再回复 setRejected', () => {
    send({ type: 'init', markdown: '内容', placeholder: '', theme });
    send({ type: 'command', name: 'bulletList' });
    send({ type: 'setMarkdown', markdown: '其他设备的内容', expectRev: 0 });
    const tail = sent.slice(-2);
    expect(tail).toEqual([{ type: 'change', markdown: '- 内容', rev: 1 }, { type: 'setRejected' }]);
    expect(bridge.flush()).toBeNull();
    // Flutter 收到修改后带上新的序号重试
    send({ type: 'setMarkdown', markdown: '- 内容\n\n其他设备的内容', expectRev: 1 });
    expect(sent.filter((m) => m.type === 'setRejected')).toHaveLength(1);
    send({ type: 'command', name: 'paragraph' });
    expect(bridge.flush()?.md).toBe('内容\n\n其他设备的内容');
  });

  it('Flutter 的序号落后（修改已发出但尚未被处理）时同样拒绝', () => {
    send({ type: 'init', markdown: '内容', placeholder: '', theme });
    send({ type: 'command', name: 'blockquote' });
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    send({ type: 'setMarkdown', markdown: '远端', expectRev: 0 });
    expect(last('setRejected')).toEqual({ type: 'setRejected' });
  });

  it('重新初始化后序号归零', () => {
    send({ type: 'init', markdown: '内容', placeholder: '', theme });
    send({ type: 'command', name: 'blockquote' });
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    send({ type: 'init', markdown: '新的', placeholder: '', theme });
    send({ type: 'command', name: 'blockquote' });
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    expect(last('change')).toEqual({ type: 'change', markdown: '> 新的', rev: 1 });
  });

  it('插入图片，并显示 Flutter 返回的图片', () => {
    send({ type: 'init', markdown: '', placeholder: '', theme });
    send({ type: 'insertImage', id: ID, alt: '图' });
    expect(last('requestImage')).toEqual({ type: 'requestImage', id: ID });
    send({ type: 'image', id: ID, dataUrl: 'data:image/png;base64,AAAA' });
    expect(document.querySelector('.jk-image img')?.getAttribute('src')).toBe('data:image/png;base64,AAAA');
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    expect(last('change')).toEqual({ type: 'change', markdown: `![图](attachment:${ID})`, rev: 1 });
  });

  it('聚焦后在光标处插入链接', () => {
    send({ type: 'init', markdown: '见', placeholder: '', theme });
    send({ type: 'focus' });
    send({ type: 'setLink', href: 'https://example.com' });
    vi.advanceTimersByTime(CHANGE_DEBOUNCE_MS);
    expect(last('change')).toEqual({ type: 'change', markdown: '见[https://example.com](https://example.com)', rev: 1 });
  });

  it('非法消息与未初始化时的命令回报错误，不执行', () => {
    bridge.receive('not json');
    expect(last('error')).toMatchObject({ message: '无法识别的消息' });
    send({ type: 'command', name: 'bold' });
    expect(last('error')).toMatchObject({ message: '编辑器尚未初始化' });
    expect(bridge.flush()).toBeNull();
  });

  it('重新初始化替换编辑器', () => {
    send({ type: 'init', markdown: '第一篇', placeholder: '', theme });
    send({ type: 'init', markdown: '第二篇', placeholder: '', theme });
    expect(document.querySelectorAll('.ProseMirror')).toHaveLength(1);
    send({ type: 'command', name: 'heading1' });
    expect(bridge.flush()).toEqual({ md: '# 第二篇', rev: 1 });
  });
});

describe('cspScriptHashes', () => {
  it('把每段内联脚本的哈希写入 CSP', () => {
    const html = `<meta content="script-src __CSP_SCRIPT_HASHES__"><script type="module">alert(1)</script>`;
    expect(cspScriptHashes(html)).toBe(
      `<meta content="script-src 'sha256-bhHHL3z2vDgxUt0W3dWQOrprscmda2Y5pLsLg4GF+pI='"><script type="module">alert(1)</script>`,
    );
  });

  it('没有内联脚本或缺少占位符时构建失败', () => {
    expect(() => cspScriptHashes('<meta content="__CSP_SCRIPT_HASHES__">')).toThrow();
    expect(() => cspScriptHashes('<script>x</script>')).toThrow();
  });
});

describe('fonts', () => {
  it('从 App 自带的字体目录加载', () => {
    expect(fontFaceCss()).toContain("url('../fonts/MiSans-Regular.ttf')");
    installFonts();
    const css = [...document.head.querySelectorAll('style')].map((s) => s.textContent).join('');
    expect(css).toContain("font-family:'Space Grotesk'");
  });
});

describe('inlineBuild', () => {
  it('把引用的脚本与样式内联进页面，并转义提前结束标签的内容', () => {
    const html =
      '<head><link rel="stylesheet" crossorigin href="/assets/a.css"></head>' +
      '<body><script type="module" crossorigin src="/assets/a.js"></script></body>';
    const files = new Map([
      ['assets/a.css', 'p{color:red}</style>'],
      ['assets/a.js', 'const s="</script>";'],
    ]);
    const { html: out, inlined } = inlineBuild(html, files);
    expect(out).toBe(
      '<head><style>p{color:red}<\\/style></style></head>' +
        '<body><script type="module">const s="<\\/script>";</script></body>',
    );
    expect(inlined).toEqual(['assets/a.css', 'assets/a.js']);
  });

  it('引用了不存在的文件时报错', () => {
    expect(() => inlineBuild('<script type="module" src="/x.js"></script>', new Map())).toThrow();
  });
});
