// 用 Style Dictionary 解析令牌引用，返回扁平的纯对象，供各端生成器使用
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import StyleDictionary from 'style-dictionary';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Style Dictionary 的 source 使用 glob，Windows 下需要正斜杠
const tokenFile = (...p) => path.join(ROOT, 'tokens', ...p).split(path.sep).join('/');

export const THEMES = ['light', 'dark'];

async function resolve(sources) {
  const sd = new StyleDictionary({
    source: sources,
    usesDtcg: true,
    log: { verbosity: 'silent', warnings: 'disabled' },
    platforms: { raw: { transforms: [] } },
  });
  const { tokens } = await sd.getPlatformTokens('raw');
  return tokens;
}

// 把 DTCG 树还原为 { key: value }，去掉 $type/$description 等元数据
function toPlain(node) {
  if (node && typeof node === 'object' && '$value' in node) return node.$value;
  return Object.fromEntries(
    Object.entries(node)
      .filter(([k]) => !k.startsWith('$'))
      .map(([k, v]) => [k, toPlain(v)]),
  );
}

export async function loadTheme(theme) {
  if (!THEMES.includes(theme)) throw new Error(`未知主题：${theme}`);
  const tokens = await resolve([tokenFile('palette.json'), tokenFile('themes', `${theme}.json`)]);
  if (!tokens.color) throw new Error(`tokens/themes/${theme}.json 缺少顶层 color 节点`);
  return { colors: toPlain(tokens.color) };
}

export async function loadShared() {
  const plain = toPlain(await resolve([tokenFile('shared.json')]));
  return plain;
}
