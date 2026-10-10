/**
 * 把构建出的脚本与样式内联进 HTML，得到可离线加载的单个文件（构建时在 Node 中运行）。
 * 不用 vite-plugin-singlefile：它依赖的 micromatch → braces 有未修复的高危漏洞公告。
 */

/** 构建产物中的一个文件：路径与内容。 */
export interface BuiltFile {
  fileName: string;
  code: string;
}

const SCRIPT = /<script\b[^>]*\bsrc="\/?([^"]+\.js)"[^>]*><\/script>/g;
const STYLE = /<link\b[^>]*\brel="stylesheet"[^>]*\bhref="\/?([^"]+\.css)"[^>]*>/g;

/** `</script` 与 `</style` 出现在内联内容中会提前结束标签，需要转义。 */
function escapeClosing(code: string, tag: 'script' | 'style'): string {
  return code.replace(new RegExp(`</(${tag})`, 'gi'), '<\\/$1');
}

/**
 * 把 HTML 中引用的脚本与样式替换为内联内容，返回新的 HTML 与已内联的文件名（之后从产物中删除）。
 * 引用了产物中不存在的文件时报错，避免生成加载不了的页面。
 */
export function inlineBuild(
  html: string,
  files: Map<string, string>,
): { html: string; inlined: string[] } {
  const inlined: string[] = [];
  const take = (name: string): string => {
    const code = files.get(name);
    if (code === undefined) throw new Error(`构建产物中找不到 ${name}`);
    inlined.push(name);
    return code;
  };
  let out = html.replace(STYLE, (_, name: string) => `<style>${escapeClosing(take(name), 'style')}</style>`);
  // 脚本放到 body 末尾执行（内联的 module 脚本同样是延迟执行的）
  out = out.replace(
    SCRIPT,
    (_, name: string) => `<script type="module">${escapeClosing(take(name), 'script')}</script>`,
  );
  return { html: out, inlined };
}
