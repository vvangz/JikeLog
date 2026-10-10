/**
 * WebView 与 Flutter 之间的消息（ADR-007）。两端都只交换 JSON：
 * Flutter → 编辑器：`window.jikelog.receive(json)`；编辑器 → Flutter：JavaScript 通道 `JikeLog.postMessage(json)`。
 */

/** 格式命令（由 Flutter 工具栏发出）。 */
export const COMMANDS = [
  'bold',
  'italic',
  'strike',
  'code',
  'paragraph',
  'heading1',
  'heading2',
  'heading3',
  'bulletList',
  'orderedList',
  'taskList',
  'blockquote',
  'codeBlock',
  'horizontalRule',
  'insertTable',
  'addRowAfter',
  'addColumnAfter',
  'deleteRow',
  'deleteColumn',
  'deleteTable',
  'unsetLink',
  'undo',
  'redo',
] as const;

export type Command = (typeof COMMANDS)[number];

/** Flutter 发给编辑器的消息。 */
export type Inbound =
  | { type: 'init'; markdown: string; placeholder: string; theme: Theme }
  /**
   * 用其他设备的修改（或合并结果）替换内容。expectRev 为 Flutter 已收到的最后一次修改的序号：
   * 编辑器中有 Flutter 尚未收到的修改时拒绝替换（回复 setRejected），由 Flutter 合并后重试。
   */
  | { type: 'setMarkdown'; markdown: string; expectRev: number }
  | { type: 'theme'; theme: Theme }
  | { type: 'command'; name: Command }
  | { type: 'setLink'; href: string }
  | { type: 'insertImage'; id: string; alt: string }
  | { type: 'image'; id: string; dataUrl: string | null }
  | { type: 'focus' };

/** 主题：CSS 变量名（不含前缀 --jk-）→ 颜色。 */
export interface Theme {
  dark: boolean;
  colors: Record<string, string>;
}

/** 当前光标处的格式状态，用于高亮工具栏按钮。 */
export interface FormatState {
  bold: boolean;
  italic: boolean;
  strike: boolean;
  code: boolean;
  heading: 0 | 1 | 2 | 3;
  bulletList: boolean;
  orderedList: boolean;
  taskList: boolean;
  blockquote: boolean;
  codeBlock: boolean;
  inTable: boolean;
  link: string | null;
  canUndo: boolean;
  canRedo: boolean;
}

/** 编辑器发给 Flutter 的消息。 */
export type Outbound =
  | { type: 'ready' }
  /** rev：本次修改的序号，每次初始化后从 1 开始递增。 */
  | { type: 'change'; markdown: string; rev: number }
  /** setMarkdown 已应用：之后的修改基于替换后的内容。 */
  | { type: 'setApplied' }
  | { type: 'setRejected' }
  | { type: 'state'; state: FormatState }
  | { type: 'requestImage'; id: string }
  | { type: 'error'; message: string };

/** 附件引用的形式：`attachment:<UUID>`。 */
export const ATTACHMENT_SCHEME = 'attachment:';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** 从图片地址中取出附件 ID；不是附件引用时返回 null。 */
export function attachmentId(src: string | null | undefined): string | null {
  if (!src?.startsWith(ATTACHMENT_SCHEME)) return null;
  const id = src.slice(ATTACHMENT_SCHEME.length);
  return UUID.test(id) ? id : null;
}

/** 正文上限与服务端 schema 一致（10 万字），超出时拒绝而不是截断。 */
export const MAX_MARKDOWN = 100_000 * 4;
const MAX_LINK = 2048;
const CSS_VAR = /^[a-z][a-z0-9-]{0,39}$/;
const CSS_COLOR = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;
const DATA_IMAGE = /^data:image\/(png|jpeg|gif|webp);base64,[A-Za-z0-9+/]+=*$/;
const LINK = /^(https?:|mailto:|tel:)/i;

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function str(v: unknown, max: number): string | null {
  return typeof v === 'string' && v.length <= max ? v : null;
}

function parseTheme(v: unknown): Theme | null {
  if (!isObject(v) || typeof v.dark !== 'boolean' || !isObject(v.colors)) return null;
  const colors: Record<string, string> = {};
  for (const [k, c] of Object.entries(v.colors)) {
    if (!CSS_VAR.test(k) || typeof c !== 'string' || !CSS_COLOR.test(c)) return null;
    colors[k] = c;
  }
  return { dark: v.dark, colors };
}

/** 只允许 http(s)、mailto、tel 链接，拒绝 javascript: 等。 */
export function isSafeLink(href: string): boolean {
  return href.length <= MAX_LINK && LINK.test(href.trim());
}

/** 解析并校验 Flutter 发来的消息；格式不对时返回 null。 */
export function parseInbound(raw: string): Inbound | null {
  let v: unknown;
  try {
    v = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!isObject(v)) return null;
  switch (v.type) {
    case 'init': {
      const markdown = str(v.markdown, MAX_MARKDOWN);
      const placeholder = str(v.placeholder, 200);
      const theme = parseTheme(v.theme);
      return markdown !== null && placeholder !== null && theme
        ? { type: 'init', markdown, placeholder, theme }
        : null;
    }
    case 'setMarkdown': {
      const markdown = str(v.markdown, MAX_MARKDOWN);
      const expectRev = v.expectRev;
      return markdown !== null && Number.isSafeInteger(expectRev) && (expectRev as number) >= 0
        ? { type: 'setMarkdown', markdown, expectRev: expectRev as number }
        : null;
    }
    case 'theme': {
      const theme = parseTheme(v.theme);
      return theme ? { type: 'theme', theme } : null;
    }
    case 'command':
      return COMMANDS.includes(v.name as Command) ? { type: 'command', name: v.name as Command } : null;
    case 'setLink': {
      const href = str(v.href, MAX_LINK);
      return href !== null && isSafeLink(href) ? { type: 'setLink', href: href.trim() } : null;
    }
    case 'insertImage': {
      const id = str(v.id, 36);
      const alt = str(v.alt, 255);
      return id && attachmentId(ATTACHMENT_SCHEME + id) && alt !== null
        ? { type: 'insertImage', id, alt }
        : null;
    }
    case 'image': {
      const id = str(v.id, 36);
      if (!id || !attachmentId(ATTACHMENT_SCHEME + id)) return null;
      if (v.dataUrl === null) return { type: 'image', id, dataUrl: null };
      const dataUrl = str(v.dataUrl, 16 * 1024 * 1024);
      return dataUrl && DATA_IMAGE.test(dataUrl) ? { type: 'image', id, dataUrl } : null;
    }
    case 'focus':
      return { type: 'focus' };
    default:
      return null;
  }
}
