// 标题字体：思源黑体（Noto Sans SC，OFL 许可）完整文件有 17 MB，构建后按全站标题实际用到的中文字符裁剪，
// 整站只有一个约百 KB 的字体文件。正文仍用系统字体，西文与数字用 Geist。
import { createHash } from 'node:crypto';

export const DISPLAY_FONT = {
  // google/fonts 仓库中固定提交的可变字体（字重轴 100–900）；更换版本时同时更新 sha256
  url: 'https://raw.githubusercontent.com/google/fonts/a85815a42757630ce188fdad368c2dfc444d4773/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf',
  sha256: 'a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da',
  // 标题用到的字重：大标题 500，小标题 600；只保留这一段可减小文件
  weight: { min: 500, max: 600 },
  // 构建产物中的路径（VitePress 配置中的 @font-face 与预加载引用它）
  path: '/fonts/jk-display.woff2',
};

// 导航栏的站点名等不在标题标签中、但使用标题字体的文字
export const EXTRA_TEXT = ['即刻日志'];

const HEADING = /<h[1-3]\b[^>]*>([\s\S]*?)<\/h[1-3]>/gi;
const TAG = /<[^>]*>/g;

/** 页面中所有 h1–h3 的文字（去掉标签）。 */
export function headingText(html) {
  let out = '';
  for (const [, inner] of html.matchAll(HEADING)) out += inner.replace(TAG, '');
  return out;
}

/** 文本中的中文字符与全角标点（U+2E80 起），去重并排序；西文由 Geist 显示，不放进中文字体。 */
export function cjkChars(text) {
  const set = new Set();
  for (const ch of text) if (ch.codePointAt(0) >= 0x2e80) set.add(ch);
  return [...set].sort().join('');
}

/** 校验字体文件的 SHA-256，不一致时抛出错误（防止下载被篡改或版本不符）。 */
export function verifySha256(buf, expected) {
  const actual = createHash('sha256').update(buf).digest('hex');
  if (actual !== expected) throw new Error(`字体文件校验失败：SHA-256 为 ${actual}，应为 ${expected}`);
}
