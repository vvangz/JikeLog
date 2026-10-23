// 官网与管理后台、接口同源：页面上的脚本若被注入，就能以本域名身份调用接口。
// 因此官网的每个页面都带严格的 CSP：只允许本站脚本，VitePress 生成的内联脚本按内容哈希放行。
// 只放行已知的那几段：页面中出现其他内联脚本（例如混进文档 Markdown 的 <script>）时构建失败，而不是自动放行。
// （CSP 写在 <meta> 里；frame-ancestors 等 <meta> 不支持的指令由 Caddy 的响应头补上。）
import { createHash } from 'node:crypto';

const INLINE_SCRIPT = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
const CHARSET = /<meta charset="[^"]*">/i;

/**
 * VitePress 2.0.0-alpha.20 在每个页面 <head> 中的两段内联脚本：check-dark-mode（首次绘制前确定深浅主题）
 * 与 check-mac-os（快捷键提示）。升级 VitePress 后内容可能变化，构建会报"未知的内联脚本"：
 * 确认新脚本来自 VitePress 本身（查看构建出的 HTML）后，把报错中的哈希更新到这里。
 */
export const VITEPRESS_INLINE_SCRIPTS = new Set([
  "'sha256-CUFLjg0/PrsMf8xbok429Fq66aDGe3lUN/QY4rcXnT8='",
  "'sha256-ng8W1FnGVqbzCCV1hV2EGXSMN/WlYnkoQZy8x1kkcsM='",
]);

const sha256 = (s) => `'sha256-${createHash('sha256').update(s, 'utf8').digest('base64')}'`;

export function addCsp(html, { known = VITEPRESS_INLINE_SCRIPTS } = {}) {
  const charset = html.match(CHARSET);
  if (!charset) throw new Error('页面缺少 <meta charset>，无法插入 CSP');
  const hashes = new Set();
  for (const [tag, body] of html.matchAll(INLINE_SCRIPT)) {
    const h = sha256(body);
    if (!known.has(h)) {
      throw new Error(`页面中有未知的内联脚本 ${h}：${tag.slice(0, 120)}…（见 lib/csp.mjs 的 VITEPRESS_INLINE_SCRIPTS）`);
    }
    hashes.add(h);
  }
  const policy = [
    "default-src 'self'",
    ['script-src', "'self'", ...hashes].join(' '),
    // Vue 会写 style 属性（如过渡动画），样式放开内联不影响脚本安全
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "font-src 'self'",
    "connect-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join('; ');
  const meta = `<meta http-equiv="Content-Security-Policy" content="${policy}">`;
  return html.replace(CHARSET, `${charset[0]}${meta}`);
}
