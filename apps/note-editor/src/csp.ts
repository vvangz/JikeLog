import { createHash } from 'node:crypto';

/** CSP 中脚本哈希的占位符（见 index.html）。 */
export const CSP_PLACEHOLDER = '__CSP_SCRIPT_HASHES__';

/** 计算内联脚本的哈希写入 CSP：页面只能执行构建出来的这一段脚本（构建时在 Node 中运行）。 */
export function cspScriptHashes(html: string): string {
  const hashes = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(
    (m) => `'sha256-${createHash('sha256').update(m[1] ?? '').digest('base64')}'`,
  );
  if (hashes.length === 0) throw new Error('构建产物中没有内联脚本');
  if (!html.includes(CSP_PLACEHOLDER)) throw new Error('页面缺少 CSP 占位符');
  return html.replace(CSP_PLACEHOLDER, hashes.join(' '));
}
