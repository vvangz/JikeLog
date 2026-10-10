import { createImageResolver } from './attachment-image';
import { NoteEditor } from './editor';
import { parseInbound, type Outbound, type Theme } from './protocol';

/** 内容变化后等待多久再把 Markdown 发给 Flutter（长文档序列化有开销）。 */
export const CHANGE_DEBOUNCE_MS = 250;

export interface BridgeOptions {
  element: HTMLElement;
  /** 发消息给 Flutter（JavaScript 通道）。 */
  post: (json: string) => void;
  root?: HTMLElement;
}

/** 暴露给 Flutter 的接口：`window.jikelog`。 */
export interface Bridge {
  /** 处理 Flutter 发来的一条消息（JSON 字符串）。 */
  receive(json: string): void;
  /**
   * 立即返回尚未发出的修改（离开页面、切换格式前调用），同时计入修改序号。
   * 没有尚未发出的修改时返回 null。
   */
  flush(): { md: string; rev: number } | null;
}

export function applyTheme(root: HTMLElement, theme: Theme): void {
  for (const [name, color] of Object.entries(theme.colors)) {
    root.style.setProperty(`--jk-${name}`, color);
  }
  root.dataset.theme = theme.dark ? 'dark' : 'light';
}

export function createBridge({ element, post, root = document.documentElement }: BridgeOptions): Bridge {
  let editor: NoteEditor | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  /** 已发给 Flutter 的修改次数。 */
  let rev = 0;
  const send = (m: Outbound) => post(JSON.stringify(m));
  const images = createImageResolver((id) => send({ type: 'requestImage', id }));

  /** 取出尚未发出的修改并计入序号。 */
  const takeChange = (): { md: string; rev: number } | null => {
    if (!editor || timer === undefined) return null;
    clearTimeout(timer);
    timer = undefined;
    rev += 1;
    return { md: editor.markdown(), rev };
  };

  const emitChange = () => {
    const c = takeChange();
    if (c) send({ type: 'change', markdown: c.md, rev: c.rev });
  };

  const handlers = {
    init(markdown: string, placeholder: string, theme: Theme) {
      applyTheme(root, theme);
      editor?.destroy();
      clearTimeout(timer);
      timer = undefined;
      rev = 0;
      editor = new NoteEditor({
        element,
        markdown,
        placeholder,
        images,
        onChange: () => {
          clearTimeout(timer);
          timer = setTimeout(emitChange, CHANGE_DEBOUNCE_MS);
        },
        onState: (state) => send({ type: 'state', state }),
      });
      send({ type: 'state', state: editor.state() });
    },
  };

  send({ type: 'ready' });

  return {
    receive(json) {
      const m = parseInbound(json);
      if (!m) {
        send({ type: 'error', message: '无法识别的消息' });
        return;
      }
      if (m.type === 'init') {
        handlers.init(m.markdown, m.placeholder, m.theme);
        return;
      }
      if (m.type === 'theme') {
        applyTheme(root, m.theme);
        return;
      }
      if (m.type === 'image') {
        images.resolve(m.id, m.dataUrl);
        return;
      }
      if (!editor) {
        send({ type: 'error', message: '编辑器尚未初始化' });
        return;
      }
      switch (m.type) {
        case 'setMarkdown':
          // 有 Flutter 尚未收到的修改：先发出这些修改并拒绝替换，Flutter 合并后重试，
          // 否则替换会抹掉这些修改
          emitChange();
          if (rev !== m.expectRev) {
            send({ type: 'setRejected' });
            break;
          }
          editor.setMarkdown(m.markdown);
          send({ type: 'setApplied' });
          break;
        case 'command':
          editor.run(m.name);
          break;
        case 'setLink':
          editor.setLink(m.href);
          break;
        case 'insertImage':
          editor.insertImage(m.id, m.alt);
          break;
        case 'focus':
          editor.focus();
          break;
      }
    },
    flush: takeChange,
  };
}
