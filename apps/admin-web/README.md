# 即刻日志 Web 管理后台

```bash
pnpm dev             # http://localhost:5173，/api 代理到 http://127.0.0.1:8080
pnpm lint && pnpm typecheck && pnpm test:coverage
pnpm build
```

- 主题：`src/theme/antdTheme.ts`，把设计令牌（`tokens.gen.ts`）映射为 Ant Design 主题
- 接口：`src/api/client.ts`，类型由 `server/api/openapi.yaml` 生成（`pnpm gen:api`）
- 字体：`public/fonts/` 由 `scripts/fetch-fonts.sh` 下载，不入库
