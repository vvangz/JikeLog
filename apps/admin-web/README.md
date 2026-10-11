# 即刻日志 Web 管理后台

```bash
pnpm dev             # http://localhost:5173，/api 代理到 http://127.0.0.1:8080
pnpm lint && pnpm typecheck && pnpm test:coverage
pnpm build && pnpm preview   # http://localhost:4173，同样代理 /api
pnpm e2e             # Playwright 端到端测试（本机用已安装的 Chrome，接口在浏览器层模拟）
```

- 设计与安全：见 [ADR-011](../../docs/架构/ADR/ADR-011-管理后台.md)；使用说明见[管理员手册](../../docs/管理员手册.md)
- 结构：
  - `src/auth/`：管理员会话。Access Token 只在内存中，Refresh Token 在 HttpOnly Cookie 中；接口返回 401 时自动刷新并重试
  - `src/app/`：外壳（左上角入口图标 + 侧栏，窄屏为浮层）与导航
  - `src/pages/`：登录、仪表盘、用户、用户详情、审计日志、管理员、设置、账号
  - `src/test/fakeApi.ts`：内存中的模拟接口，单元测试与端到端测试共用
- 主题：`src/theme/antdTheme.ts`，把设计令牌（`tokens.gen.ts`）映射为 Ant Design 主题
- 接口：`src/api/client.ts`，类型由 `server/api/openapi.yaml` 生成（`pnpm gen:api`）
- 字体：`public/fonts/` 由 `scripts/fetch-fonts.sh` 下载，不入库
