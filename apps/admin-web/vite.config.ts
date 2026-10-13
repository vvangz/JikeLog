import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    proxy: {
      // 本地开发时把接口请求转发到 Go 服务（同源，管理员 Refresh Cookie 才能发送）
      '/api': 'http://127.0.0.1:8080',
    },
  },
  preview: {
    // 明确监听 IPv4：Windows 上 localhost 可能只绑定到 ::1，浏览器用 127.0.0.1 访问时会被拒绝
    host: '127.0.0.1',
    port: 4173,
    proxy: {
      '/api': 'http://127.0.0.1:8080',
    },
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['./src/test/setup.ts'],
    testTimeout: 20000,
    css: false,
    coverage: {
      provider: 'v8',
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['src/**/*.gen.ts', 'src/main.tsx', 'src/test/**', 'src/**/*.test.{ts,tsx}'],
      thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
    },
  },
});
