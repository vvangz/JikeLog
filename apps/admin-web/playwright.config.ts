import { defineConfig, devices } from '@playwright/test';

/**
 * 端到端测试（ADR-011）：在构建产物上跑登录 → 仪表盘 → 用户 → 详情 → 审计日志等流程。
 * 接口由 e2e/mockApi.ts 在浏览器层拦截模拟，不依赖后端；服务端接口由 Go 集成测试覆盖。
 * 本机默认使用已安装的 Chrome；CI 中使用 Playwright 下载的 Chromium。
 */
export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'retain-on-failure',
    locale: 'zh-CN',
  },
  projects: [
    {
      name: 'desktop',
      use: { ...devices['Desktop Chrome'], channel: process.env.CI ? undefined : 'chrome' },
      testIgnore: /responsive\.spec\.ts/,
    },
    {
      name: 'mobile',
      use: { ...devices['Pixel 7'], channel: process.env.CI ? undefined : 'chrome' },
      testMatch: /responsive\.spec\.ts/,
    },
  ],
  webServer: {
    command: 'pnpm build && pnpm preview --host 127.0.0.1 --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
});
