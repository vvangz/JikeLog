import { fileURLToPath } from 'node:url';

import type { Plugin } from 'vite';
import { defineConfig } from 'vitest/config';

import { cspScriptHashes } from './src/csp.ts';
import { inlineBuild } from './src/inline.ts';

/** 内联脚本与样式得到单个 HTML，再计算脚本哈希写入 CSP（见 src/inline.ts、src/csp.ts）。 */
function singleFile(): Plugin {
  return {
    name: 'jikelog-single-file',
    enforce: 'post',
    generateBundle(_, bundle) {
      const files = new Map<string, string>();
      for (const f of Object.values(bundle)) {
        files.set(f.fileName, f.type === 'chunk' ? f.code : String(f.source));
      }
      for (const f of Object.values(bundle)) {
        if (f.type !== 'asset' || !f.fileName.endsWith('.html')) continue;
        const { html, inlined } = inlineBuild(String(f.source), files);
        f.source = cspScriptHashes(html);
        for (const name of inlined) delete bundle[name];
      }
    },
  };
}

export default defineConfig({
  plugins: [singleFile()],
  build: {
    // 构建产物随 App 打包（apps/mobile/assets/editor），提交到仓库，CI 检查与源码一致
    outDir: fileURLToPath(new URL('../mobile/assets/editor', import.meta.url)),
    emptyOutDir: true,
    target: 'chrome100',
    reportCompressedSize: false,
    // 单文件：不拆分代码、不生成模块预加载脚本、样式合并为一个文件
    cssCodeSplit: false,
    modulePreload: false,
    assetsInlineLimit: Number.MAX_SAFE_INTEGER,
    rollupOptions: { output: { inlineDynamicImports: true } },
  },
  test: {
    environment: 'happy-dom',
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: ['src/main.ts', 'src/**/*.test.ts'],
      thresholds: { lines: 80, functions: 80, branches: 75, statements: 80 },
    },
  },
});
