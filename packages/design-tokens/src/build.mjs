// 入口：读取令牌 → 生成 Flutter 与 Web 两端代码
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadShared, loadTheme } from './load.mjs';
import { emitDart } from './emit-dart.mjs';
import { emitCss, emitTs } from './emit-web.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

const OUTPUTS = [
  ['apps/mobile/lib/app/theme/jk_tokens.g.dart', emitDart],
  ['apps/admin-web/src/theme/tokens.gen.css', emitCss],
  ['apps/admin-web/src/theme/tokens.gen.ts', emitTs],
];

async function main() {
  const input = {
    light: (await loadTheme('light')).colors,
    dark: (await loadTheme('dark')).colors,
    shared: await loadShared(),
  };
  for (const [rel, emit] of OUTPUTS) {
    const file = path.join(REPO, rel);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, emit(input), 'utf8');
    console.log(`✔ ${rel}`);
  }
}

main().catch((err) => {
  console.error('设计令牌生成失败：', err);
  process.exitCode = 1;
});
