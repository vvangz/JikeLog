# 开发与版本规范

## 分支模型（Git Flow 简化版 + Release Please）

| 分支 | 用途 | 规则 |
|---|---|---|
| `main` | 已发布版本 | 受保护；只接受来自 `develop` 的发版合并、`hotfix/*` 和 Release Please 的发布 PR |
| `develop` | 日常集成 | 受保护；功能分支通过 PR 合入，CI 必须通过 |
| `feature/<模块>-<描述>` | 新功能 | 从 `develop` 拉出，例如 `feature/worklog-attachments` |
| `fix/<描述>` | 非紧急缺陷修复 | 从 `develop` 拉出 |
| `hotfix/<描述>` | 线上紧急修复 | 从 `main` 拉出，完成后合入 `main`，再同步回 `develop` |

### 发版流程

1. 里程碑功能全部合入 `develop`，并且 CI 通过
2. 发起 PR：`develop` → `main`（标题如 `chore(release): v0.2.0 里程碑`），审查后合并
3. Release Please 在 `main` 上自动创建或更新发布 PR `chore(main): release x.y.z`，其中包含 CHANGELOG 和各端版本号的修改
4. 合并发布 PR 后，Release Please 自动打 tag `vX.Y.Z` 并创建 GitHub Release
5. 把 `main` 合并回 `develop`，使版本号保持同步

> 发布 PR 默认用 `GITHUB_TOKEN` 创建，这样创建的 PR 不会触发 CI。如果 `main` 要求 CI 必须通过，需要在仓库 Secrets 中配置 `RELEASE_PLEASE_TOKEN`（细粒度 PAT，只授予本仓库 Contents 与 Pull requests 的写权限）。

## 提交信息（Conventional Commits）

```
<type>(<scope>): <描述>

<可选正文：为什么改、怎么改>

<可选脚注：Closes #12 / BREAKING CHANGE: ...>
```

- **type**：`feat` 新功能 · `fix` 修复 · `refactor` 重构 · `perf` 性能 · `docs` 文档 · `test` 测试 · `build` 构建/依赖 · `ci` 持续集成 · `chore` 杂项 · `style` 格式 · `revert` 回滚
- **scope**：`server` · `mobile` · `admin` · `tokens` · `deploy` · `docs` · `ci` · `deps` · `release`
- 由 commitlint 在 `commit-msg` 钩子中校验，钩子在执行 `pnpm install` 时自动安装

示例：`feat(server): 新增短信验证码登录接口`

## 版本号（SemVer）

- 版本号格式为 `MAJOR.MINOR.PATCH`，全仓库（服务端、客户端、管理后台）共用一个产品版本号
- 1.0.0 之前，每个里程碑递增 MINOR（v0.2.0、v0.3.0…），修复递增 PATCH
- 版本号与 `CHANGELOG.md` 由 [Release Please](https://github.com/googleapis/release-please) 根据提交记录自动维护。根目录 `version.txt` 以及以下文件里带 `x-release-please-version` 注释的版本行会被同步更新：
  - `server/internal/version/version.go`、`server/api/openapi.yaml`
  - `apps/mobile/lib/app/version.dart`、`apps/mobile/pubspec.yaml`
  - `apps/admin-web/package.json`

## 开发流程

1. **先写测试（TDD）**：先写会失败的测试，再写最小实现让它通过，最后重构
2. **覆盖率 ≥ 80%**：生成代码（`*.gen.go`、`*.g.dart`、`*.gen.ts`）不计入，CI 会强制检查
3. **契约优先**：接口先改 `server/api/openapi.yaml`，再执行 `pnpm gen:api`；颜色、字号等先改设计令牌，再执行 `pnpm tokens`。生成文件必须与源一致，CI 会校验
4. **代码审查**：每个 PR 至少需要一次审查；涉及认证、加密、文件上传的改动还要单独做安全审查
5. **文档**：每个里程碑在 `docs/开发日志/` 写一篇开发日志；用户可见的功能要同步更新 `docs/使用说明/`

## 代码风格

| 端 | 工具 |
|---|---|
| Go | `gofmt` + `goimports` + `golangci-lint`（配置见 `server/.golangci.yml`） |
| Dart | `dart format` + `flutter analyze`（配置见 `apps/mobile/analysis_options.yaml`） |
| TypeScript | ESLint + `tsc --noEmit` |

通用约定：函数尽量少于 50 行，文件少于 800 行，嵌套不超过 4 层；数据对象优先不可变；错误要显式处理，不能静默吞掉。

## 安全（公开仓库）

- **严禁提交**：`.env`、密钥、证书、keystore、`key.properties`，以及 MiSans 字体文件
- 本地 `pre-commit` 钩子和 CI 都会运行 gitleaks 扫描密钥。如果误提交了密钥，**立即轮换该密钥**；仅仅删除提交是不够的
- 生产配置只放在服务器环境变量或 GitHub Actions Secrets 中
- 日志中不得记录手机号全号、验证码、密码、工作日志正文

## 依赖与镜像

- Flutter 的 `pubspec.lock` 记录的是国内镜像地址 `https://pub.flutter-io.cn`，CI 也使用同一镜像，并以 `--enforce-lockfile` 校验每个包的 sha256。**本地请设置 `PUB_HOSTED_URL=https://pub.flutter-io.cn`**，否则 `flutter pub get` 会改写锁文件
- Go 依赖完整性由 `go.sum` 与 sumdb 保证，代理可以自由选择（goproxy.cn 或 proxy.golang.org）
- 漏洞扫描：CI 会运行 govulncheck 和 `pnpm audit`。即使代码没变，新公布的漏洞也可能让 CI 变红，这时请升级依赖。本地运行 govulncheck 需要用 Go 1.27.1 构建：`GOTOOLCHAIN=go1.27.1 go run golang.org/x/vuln/cmd/govulncheck@v1.8.0 ./...`

## 本机注意事项

如果全局 `go env` 设置了 `GOOS=linux`（用于交叉编译），本地运行测试需要临时覆盖：`GOOS=windows go test ./...`。`scripts/go-coverage.sh` 和 `scripts/gen-api.sh` 已经自动处理。
