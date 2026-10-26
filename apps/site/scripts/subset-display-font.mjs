// 构建后运行（pnpm build 的最后一步）：收集所有页面标题用到的中文字符，从思源黑体裁剪出
// .vitepress/dist/fonts/jk-display.woff2。源字体下载一次后缓存在 node_modules/.cache/jikelog-fonts/。
// 下载或裁剪失败时只给出警告：标题改用系统字体显示，不影响发布。
import { existsSync } from 'node:fs';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import subsetFont from 'subset-font';
import { cjkChars, DISPLAY_FONT, EXTRA_TEXT, headingText, verifySha256 } from '../lib/display-font.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const dist = path.join(root, '.vitepress', 'dist');
const cacheFile = path.join(root, 'node_modules', '.cache', 'jikelog-fonts', 'NotoSansSC-wght.ttf');

async function sourceFont() {
  if (existsSync(cacheFile)) {
    const cached = await readFile(cacheFile);
    try {
      verifySha256(cached, DISPLAY_FONT.sha256);
      return cached;
    } catch {
      // 缓存损坏：重新下载
    }
  }
  const res = await fetch(DISPLAY_FONT.url);
  if (!res.ok) throw new Error(`下载思源黑体失败：HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  verifySha256(buf, DISPLAY_FONT.sha256);
  await mkdir(path.dirname(cacheFile), { recursive: true });
  await writeFile(cacheFile, buf);
  return buf;
}

try {
  const pages = (await readdir(dist, { recursive: true })).filter((f) => f.endsWith('.html'));
  let text = EXTRA_TEXT.join('');
  for (const p of pages) text += headingText(await readFile(path.join(dist, p), 'utf8'));
  const chars = cjkChars(text);
  const font = await subsetFont(await sourceFont(), chars, {
    targetFormat: 'woff2',
    variationAxes: { wght: { min: DISPLAY_FONT.weight.min, max: DISPLAY_FONT.weight.max } },
  });
  const out = path.join(dist, DISPLAY_FONT.path);
  await mkdir(path.dirname(out), { recursive: true });
  await writeFile(out, font);
  console.log(`✔ 标题字体：${pages.length} 个页面、${[...chars].length} 个字，${(font.length / 1024).toFixed(0)} KB`);
} catch (err) {
  // GitHub Actions 的警告格式，显示在运行摘要中
  console.log(`::warning::没有生成标题字体（标题将使用系统字体）：${err.message}`);
}
