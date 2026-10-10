import { fileURLToPath } from 'node:url';

import type { Plugin } from 'vite';
import { defineConfig } from 'vitest/config';
import { viteSingleFile } from 'vite-plugin-singlefile';

import { cspScriptHashes } from './src/csp.ts';

function csp(): Plugin {
  return {
    name: 'jikelog-csp',
    enforce: 'post',
    generateBundle(_, bundle) {
      for (const file of Object.values(bundle)) {
        if (file.type === 'asset' && file.fileName.endsWith('.html')) {
          file.source = cspScriptHashes(String(file.source));
        }
      }
    },
  };
}

export default defineConfig({
  plugins: [viteSingleFile({ removeViteModuleLoader: true }), csp()],
  build: {
    // 构建产物随 App 打包（apps/mobile/assets/editor），提交到仓库，CI 检查与源码一致
    outDir: fileURLToPath(new URL('../mobile/assets/editor', import.meta.url)),
    emptyOutDir: true,
    target: 'chrome100',
    reportCompressedSize: false,
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
