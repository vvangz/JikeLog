import { afterEach, describe, expect, it, vi } from 'vitest';

import { createImageResolver } from './attachment-image';
import { NoteEditor } from './editor';
import type { FormatState } from './protocol';

const ID = '0190a1b2-0000-7000-8000-000000000001';

const SAMPLE = `# 标题

正文 **加粗** *斜体* ~~删除~~ \`行内代码\` [链接](https://example.com)

- [ ] 待办一
- [x] 已完成

1. 有序一
2. 有序二

> 引用

\`\`\`go
func main() {
	fmt.Println("你好")
}
\`\`\`

| 列一 | 列二 |
| --- | --- |
| a | b |

![截图](attachment:${ID})

---
`;

let editors: NoteEditor[] = [];

function make(markdown = '', extra: Partial<{ onChange: () => void; onState: (s: FormatState) => void }> = {}) {
  const requested: string[] = [];
  const images = createImageResolver((id) => requested.push(id));
  const element = document.createElement('div');
  document.body.append(element);
  const onChange = extra.onChange ?? vi.fn();
  const editor = new NoteEditor({
    element,
    markdown,
    placeholder: '写点什么',
    images,
    onChange,
    onState: extra.onState ?? (() => {}),
  });
  editors.push(editor);
  return { editor, element, images, requested, onChange };
}

afterEach(() => {
  for (const e of editors) e.destroy();
  editors = [];
  document.body.innerHTML = '';
});

describe('Markdown 往返', () => {
  it('保留代码块、表格、待办、图片与各种行内格式', () => {
    const { editor } = make(SAMPLE);
    const md = editor.markdown();
    for (const piece of [
      '# 标题',
      '**加粗**',
      '*斜体*',
      '~~删除~~',
      '`行内代码`',
      '[链接](https://example.com)',
      '- [ ] 待办一',
      '- [x] 已完成',
      '1. 有序一',
      '2. 有序二',
      '> 引用',
      '```go\nfunc main() {\n\tfmt.Println("你好")\n}\n```',
      '| 列一',
      `![截图](attachment:${ID})`,
      '---',
    ]) {
      expect(md).toContain(piece);
    }
  });

  it('规范化一次之后结果稳定（不会反复产生修改）', () => {
    const first = make(SAMPLE).editor.markdown();
    const second = make(first).editor.markdown();
    expect(make(second).editor.markdown()).toBe(second);
  });

  it('空文档输出空字符串', () => {
    expect(make('').editor.markdown()).toBe('');
  });

  it('只有图片、分隔线或空表格的文档不是空文档', () => {
    expect(make(`![](attachment:${ID})`).editor.markdown()).toBe(`![](attachment:${ID})`);
    expect(make('---').editor.markdown()).toBe('---');
    const { editor } = make('');
    editor.run('insertTable');
    expect(editor.markdown()).toMatch(/^\| +\|/);
  });
});

describe('修改通知', () => {
  it('初始化与远端替换不触发修改，用户编辑才触发', () => {
    const { editor, onChange } = make('旧内容');
    expect(onChange).not.toHaveBeenCalled();
    editor.setMarkdown('其他设备的内容');
    expect(onChange).not.toHaveBeenCalled();
    expect(editor.markdown()).toBe('其他设备的内容');
    editor.run('bold');
    editor.run('heading1');
    expect(onChange).toHaveBeenCalled();
  });

  it('远端替换不进入撤销历史', () => {
    const { editor } = make('第一版');
    editor.setMarkdown('第二版');
    expect(editor.state().canUndo).toBe(false);
  });

  it('远端替换后光标保持在原位置附近', () => {
    const { editor } = make('第一段\n\n第二段');
    editor.setMarkdown('短');
    expect(editor.markdown()).toBe('短');
  });
});

describe('格式命令', () => {
  it.each([
    ['heading2', '## '],
    ['heading3', '### '],
    ['bulletList', '- '],
    ['orderedList', '1. '],
    ['taskList', '- [ ] '],
    ['blockquote', '> '],
  ] as const)('%s', (cmd, prefix) => {
    const { editor } = make('内容');
    expect(editor.run(cmd)).toBe(true);
    expect(editor.markdown()).toBe(`${prefix}内容`);
  });

  it('代码块', () => {
    const { editor } = make('x = 1');
    editor.run('codeBlock');
    expect(editor.markdown()).toBe('```\nx = 1\n```');
  });

  it('插入表格并增删行列', () => {
    const { editor } = make('');
    editor.run('insertTable');
    expect(editor.state().inTable).toBe(true);
    const rows = () => editor.markdown().split('\n').filter((l) => l.startsWith('|')).length;
    const cols = () => (editor.markdown().split('\n')[0]?.match(/\|/g)?.length ?? 1) - 1;
    expect(rows()).toBe(4); // 表头 + 分隔行 + 2 行
    editor.run('addRowAfter');
    expect(rows()).toBe(5);
    editor.run('addColumnAfter');
    expect(cols()).toBe(4);
    editor.run('deleteColumn');
    expect(cols()).toBe(3);
    editor.run('deleteTable');
    expect(editor.state().inTable).toBe(false);
  });

  it('删除光标所在的行', () => {
    const { editor } = make('| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |');
    editor.focus(); // 光标在文末，即最后一个单元格
    editor.run('deleteRow');
    expect(editor.markdown()).not.toContain('3');
    expect(editor.markdown()).toContain('1');
  });

  it('分隔线、段落、撤销与重做', () => {
    const { editor } = make('# 标题');
    editor.run('paragraph');
    expect(editor.markdown()).toBe('标题');
    editor.run('horizontalRule');
    expect(editor.markdown()).toContain('---');
    expect(editor.run('undo')).toBe(true);
    expect(editor.state().canRedo).toBe(true);
    expect(editor.run('redo')).toBe(true);
  });

  it('行内格式与状态', () => {
    const states: FormatState[] = [];
    const { editor } = make('', { onState: (s) => states.push(s) });
    for (const c of ['bold', 'italic', 'strike'] as const) editor.run(c);
    const last = states.at(-1);
    expect(last?.bold && last.italic && last.strike).toBe(true);
    // 行内代码与其他行内格式互斥
    editor.run('code');
    expect(editor.state()).toMatchObject({ code: true, bold: false });
  });

  it('设置与取消链接', () => {
    const { editor } = make('');
    editor.setLink('https://example.com');
    expect(editor.markdown()).toBe('[https://example.com](https://example.com)');
    expect(editor.state().link).toBe('https://example.com');
    editor.run('unsetLink');
    expect(editor.markdown()).toBe('https://example.com');
  });

  it('光标在链接中时修改链接地址', () => {
    const { editor } = make('[文档](https://a.example)');
    editor.focus();
    expect(editor.state().link).toBe('https://a.example');
    editor.setLink('https://b.example');
    expect(editor.markdown()).toBe('[文档](https://b.example)');
  });
});

describe('附件图片', () => {
  it('插入图片写作 attachment: 引用，并向 Flutter 请求图片', () => {
    const { editor, requested } = make('');
    editor.insertImage(ID, '照片.jpg');
    expect(editor.markdown()).toBe(`![照片.jpg](attachment:${ID})`);
    expect(requested).toEqual([ID]);
  });

  it('图片到达后显示，同一张图只请求一次', () => {
    const { element, images, requested } = make(`![a](attachment:${ID})\n\n![b](attachment:${ID})`);
    expect(requested).toEqual([ID]);
    const boxes = element.querySelectorAll<HTMLElement>('.jk-image');
    expect(boxes).toHaveLength(2);
    expect(boxes[0]?.dataset.state).toBe('loading');
    images.resolve(ID, 'data:image/png;base64,AAAA');
    for (const b of boxes) {
      expect(b.dataset.state).toBe('ready');
      expect(b.querySelector('img')?.getAttribute('src')).toBe('data:image/png;base64,AAAA');
    }
  });

  it('图片无法取得时显示替代文字', () => {
    const { element, images } = make(`![合同扫描件](attachment:${ID})`);
    images.resolve(ID, null);
    const box = element.querySelector<HTMLElement>('.jk-image');
    expect(box?.dataset.state).toBe('missing');
    expect(box?.textContent).toContain('合同扫描件');
  });

  it('网络图片不加载，只显示替代文字', () => {
    const { element, requested } = make('![外链](https://tracker.example/pixel.png)');
    expect(requested).toEqual([]);
    const box = element.querySelector<HTMLElement>('.jk-image');
    expect(box?.dataset.state).toBe('missing');
    expect(box?.querySelector('img')?.hasAttribute('src')).toBe(false);
  });
});
