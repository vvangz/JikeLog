import Image from '@tiptap/extension-image';

import { attachmentId } from './protocol';

/** 解析附件图片：编辑器向 Flutter 请求，Flutter 以 data: 地址返回（ADR-007）。 */
export interface ImageResolver {
  /** 已取得的图片；undefined 表示尚未请求，null 表示无法显示。 */
  get(id: string): string | null | undefined;
  request(id: string): void;
  /** 某张图片到达后，更新所有引用它的节点。 */
  subscribe(id: string, onReady: (dataUrl: string | null) => void): () => void;
}

/** 内存中的图片缓存，同一张图片只请求一次。 */
export function createImageResolver(post: (id: string) => void): ImageResolver & {
  resolve(id: string, dataUrl: string | null): void;
} {
  const cache = new Map<string, string | null>();
  const pending = new Set<string>();
  const listeners = new Map<string, Set<(d: string | null) => void>>();
  return {
    get: (id) => cache.get(id),
    request(id) {
      if (cache.has(id) || pending.has(id)) return;
      pending.add(id);
      post(id);
    },
    subscribe(id, onReady) {
      const set = listeners.get(id) ?? new Set();
      set.add(onReady);
      listeners.set(id, set);
      return () => set.delete(onReady);
    },
    resolve(id, dataUrl) {
      pending.delete(id);
      cache.set(id, dataUrl);
      for (const l of listeners.get(id) ?? []) l(dataUrl);
    },
  };
}

/**
 * 图片节点：Markdown 中保持 `attachment:<id>`，显示时换成 Flutter 提供的 data: 地址。
 * 其他地址（例如网络图片）不加载，只显示替代文字：页面的 CSP 只允许 data: 图片。
 */
export function attachmentImage(resolver: ImageResolver) {
  return Image.extend({
    addNodeView() {
      return ({ node }) => {
        const dom = document.createElement('span');
        dom.className = 'jk-image';
        const img = document.createElement('img');
        img.alt = String(node.attrs.alt ?? '');
        const caption = document.createElement('span');
        caption.className = 'jk-image-caption';
        dom.append(img, caption);

        const id = attachmentId(node.attrs.src as string | null);
        const show = (dataUrl: string | null | undefined) => {
          dom.dataset.state = dataUrl ? 'ready' : dataUrl === null ? 'missing' : 'loading';
          if (dataUrl) img.src = dataUrl;
          else img.removeAttribute('src');
          caption.textContent = dataUrl
            ? ''
            : dataUrl === null || !id
              ? `图片无法显示${img.alt ? `：${img.alt}` : ''}`
              : '图片加载中…';
        };
        if (!id) {
          show(null);
          return { dom };
        }
        const unsubscribe = resolver.subscribe(id, show);
        show(resolver.get(id));
        resolver.request(id);
        return { dom, destroy: unsubscribe };
      };
    },
  }).configure({ inline: false, allowBase64: false });
}
