import { Editor, type ChainedCommands } from '@tiptap/core';
import { TaskItem, TaskList } from '@tiptap/extension-list';
import Placeholder from '@tiptap/extension-placeholder';
import { TableKit } from '@tiptap/extension-table';
import { Markdown } from '@tiptap/markdown';
import StarterKit from '@tiptap/starter-kit';

import { attachmentImage, type ImageResolver } from './attachment-image';
import { ATTACHMENT_SCHEME, type Command, type FormatState } from './protocol';

export interface NoteEditorOptions {
  element: HTMLElement;
  markdown: string;
  placeholder: string;
  images: ImageResolver;
  /** 用户编辑后调用（远端内容与初始化不会触发）。 */
  onChange: () => void;
  onState: (state: FormatState) => void;
}

/** 远端内容替换时打的标记：不触发保存、不进入撤销历史。 */
const REMOTE = 'jikelog-remote';

/** 富文本编辑器：Tiptap + Markdown 存储（ADR-007）。 */
export class NoteEditor {
  private readonly editor: Editor;

  constructor(opts: NoteEditorOptions) {
    this.editor = new Editor({
      element: opts.element,
      extensions: [
        StarterKit.configure({
          // Markdown 表达不了下划线
          underline: false,
          link: { openOnClick: false, autolink: true, linkOnPaste: true },
        }),
        Markdown,
        TableKit.configure({ table: { resizable: false } }),
        TaskList,
        TaskItem.configure({ nested: true }),
        attachmentImage(opts.images),
        Placeholder.configure({ placeholder: opts.placeholder }),
      ],
      content: opts.markdown,
      contentType: 'markdown',
      onUpdate: ({ transaction }) => {
        if (!transaction.getMeta(REMOTE)) opts.onChange();
      },
      onTransaction: () => opts.onState(this.state()),
    });
  }

  /**
   * 当前正文（去掉首尾空行）。只有"一个空段落"才算空文档：
   * Tiptap 的 isEmpty 把只有图片或空表格的文档也当成空的，用它会把图片丢掉。
   */
  markdown(): string {
    const doc = this.editor.state.doc;
    const first = doc.firstChild;
    if (doc.childCount === 1 && first?.type.name === 'paragraph' && first.content.size === 0) return '';
    return this.editor.getMarkdown().replace(/^\n+|\n+$/g, '');
  }

  /** 用其他设备的修改（或合并结果）替换内容，光标尽量留在原处。 */
  setMarkdown(markdown: string): void {
    const { from, to } = this.editor.state.selection;
    this.editor
      .chain()
      .setMeta(REMOTE, true)
      .setMeta('addToHistory', false)
      .setContent(markdown, { contentType: 'markdown', emitUpdate: true })
      .run();
    const size = this.editor.state.doc.content.size;
    const clamp = (n: number) => Math.max(1, Math.min(n, size - 1));
    try {
      this.editor.chain().setMeta(REMOTE, true).setTextSelection({ from: clamp(from), to: clamp(to) }).run();
    } catch {
      // 原位置已不存在（例如内容被大幅删减），保持默认光标
    }
  }

  run(name: Command): boolean {
    const c = this.editor.chain().focus();
    const chains: Record<Command, (c: ChainedCommands) => ChainedCommands> = {
      bold: (c) => c.toggleBold(),
      italic: (c) => c.toggleItalic(),
      strike: (c) => c.toggleStrike(),
      code: (c) => c.toggleCode(),
      paragraph: (c) => c.setParagraph(),
      heading1: (c) => c.toggleHeading({ level: 1 }),
      heading2: (c) => c.toggleHeading({ level: 2 }),
      heading3: (c) => c.toggleHeading({ level: 3 }),
      bulletList: (c) => c.toggleBulletList(),
      orderedList: (c) => c.toggleOrderedList(),
      taskList: (c) => c.toggleTaskList(),
      blockquote: (c) => c.toggleBlockquote(),
      codeBlock: (c) => c.toggleCodeBlock(),
      horizontalRule: (c) => c.setHorizontalRule(),
      insertTable: (c) => c.insertTable({ rows: 3, cols: 3, withHeaderRow: true }),
      addRowAfter: (c) => c.addRowAfter(),
      addColumnAfter: (c) => c.addColumnAfter(),
      deleteRow: (c) => c.deleteRow(),
      deleteColumn: (c) => c.deleteColumn(),
      deleteTable: (c) => c.deleteTable(),
      unsetLink: (c) => c.extendMarkRange('link').unsetLink(),
      undo: (c) => c.undo(),
      redo: (c) => c.redo(),
    };
    return chains[name](c).run();
  }

  /** 给选中的文字加链接；没有选中文字时插入链接地址本身。 */
  setLink(href: string): boolean {
    const { empty } = this.editor.state.selection;
    const chain = this.editor.chain().focus();
    if (empty && !this.editor.isActive('link')) {
      return chain
        .insertContent({ type: 'text', text: href, marks: [{ type: 'link', attrs: { href } }] })
        .run();
    }
    return chain.extendMarkRange('link').setLink({ href }).run();
  }

  insertImage(id: string, alt: string): boolean {
    return this.editor
      .chain()
      .focus()
      .setImage({ src: ATTACHMENT_SCHEME + id, alt })
      .run();
  }

  /** 聚焦到文末（新建笔记、点击空白处时继续往后写）。 */
  focus(): void {
    this.editor.commands.focus('end');
  }

  state(): FormatState {
    const e = this.editor;
    const heading = ([1, 2, 3] as const).find((level) => e.isActive('heading', { level })) ?? 0;
    return {
      bold: e.isActive('bold'),
      italic: e.isActive('italic'),
      strike: e.isActive('strike'),
      code: e.isActive('code'),
      heading,
      bulletList: e.isActive('bulletList'),
      orderedList: e.isActive('orderedList'),
      taskList: e.isActive('taskList'),
      blockquote: e.isActive('blockquote'),
      codeBlock: e.isActive('codeBlock'),
      inTable: e.isActive('table'),
      link: e.isActive('link') ? String(e.getAttributes('link').href ?? '') : null,
      canUndo: e.can().undo(),
      canRedo: e.can().redo(),
    };
  }

  destroy(): void {
    this.editor.destroy();
  }
}
