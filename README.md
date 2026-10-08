# 即刻日志 JikeLog

面向个人和企业员工的高效记录工具，包含四个核心模块：**工作日志**、**笔记**、**备忘录**、**记账**。支持多设备实时同步、离线使用、全局搜索、浅色/深色主题。

| 端 | 技术栈 | 目录 | 状态 |
|---|---|---|---|
| Android 客户端 | Flutter 3.47 / Dart 3.13 | [`apps/mobile`](apps/mobile) | 🚧 开发中 |
| Web 管理后台 | React 19 + Ant Design 6 + Vite 8 | [`apps/admin-web`](apps/admin-web) | 🚧 开发中 |
| 服务端 | Go 1.27 + Gin + PostgreSQL + Redis | [`server`](server) | 🚧 开发中 |
| Windows 客户端 | Flutter（与 Android 同一代码库） | — | 📅 后续版本 |

> 当前版本：**v0.1.0（基础设施）**。各里程碑见下方的[路线图](#路线图)。

## 功能概览

- **账号**：用户名+密码登录、手机号+短信验证码登录；一个手机号只能绑定一个账号；可通过短信找回密码
- **工作日志**：日期、工作地点、工作内容、附件，可随时修改并自动保存；可以关联笔记；传输时在应用层额外加密
- **笔记**：支持 Markdown 和富文本，包括代码块、表格、待办清单；有文件夹、标签、收藏；附件可以是图片、PDF、音频或文件
- **备忘录**：日期时间加内容，可设置提前提醒，与日历关联，通过 App 推送提醒
- **记账**：收入、支出、转账、借贷；按分类统计占比，统计各账户余额
- **通用**：多设备实时同步（字段级合并与冲突版本保留）、全局搜索、数据导出、14 天周期备份

## 仓库结构

```
JikeLog/
├─ apps/mobile/              Flutter 客户端
├─ apps/admin-web/           React 管理后台
├─ server/                   Go 后端（api/openapi.yaml 是接口契约）
├─ packages/design-tokens/   设计令牌（颜色、字体、间距等），生成 Dart 与 CSS/TS 代码
├─ deploy/                   Docker Compose 与部署脚本
├─ scripts/                  字体下载、代码生成、覆盖率检查
└─ docs/                     需求、架构、开发日志、使用说明
```

## 快速开始

环境要求：Go 1.27+、Node.js 22+、pnpm 10+、Flutter 3.47+、JDK 17、Docker。完整步骤见 [本地开发环境](docs/部署运维/本地开发环境.md)。

```bash
pnpm install                 # 安装前端依赖，同时安装 Git 钩子
bash scripts/fetch-fonts.sh  # 下载 Space Grotesk 与 MiSans 字体（不入库）

# 启动依赖：PostgreSQL / Redis / S3 兼容存储
cp deploy/.env.example deploy/.env
docker compose -f deploy/docker-compose.dev.yml --env-file deploy/.env up -d

# 服务端
cd server && go run ./cmd/api                 # http://localhost:8080/healthz

# 管理后台
pnpm --filter @jikelog/admin-web dev          # http://localhost:5173

# Android 客户端
cd apps/mobile && flutter run
```

常用命令：

| 命令 | 作用 |
|---|---|
| `pnpm tokens` | 修改 `packages/design-tokens/tokens` 后重新生成两端主题代码 |
| `pnpm gen:api` | 修改 `server/api/openapi.yaml` 后重新生成 Go 和 TS 接口代码 |
| `bash scripts/go-coverage.sh` | 运行 Go 测试并检查覆盖率是否 ≥ 80% |

## 路线图

| 版本 | 里程碑 | 内容 |
|---|---|---|
| **v0.1.0** | M0 基础设施 | monorepo、CI、设计令牌、开发环境、接口契约 ✅ |
| v0.2.0 | M1 账号 + App 外壳 | 登录注册、短信、导航外壳、主题、设置 |
| v0.3.0 | M2 同步 + 工作日志 | 同步引擎、附件、工作日志（加密） |
| v0.4.0 | M3 笔记 | 编辑器、文件夹/标签/收藏、附件 |
| v0.5.0 | M4 备忘录 | 提醒、日历、推送 |
| v0.6.0 | M5 记账 | 账户、分类、转账、借贷、统计 |
| v0.7.0 | M6 搜索 + 导出 | 全局搜索、数据导出 |
| v0.8.0 | M7 管理后台 | 仪表盘、用户配置查看、审计日志 |
| v0.9.0 | M8 上线准备 | 阿里云部署、备份、安全与性能 |
| v1.0.0 | 正式发布 | — |

## 文档

- [需求文档](docs/需求文档.md)
- [架构总览](docs/架构/总览.md) · [架构决策记录](docs/架构/ADR)
- [设计规范](docs/设计规范.md)
- [开发日志](docs/开发日志)
- [使用说明](docs/使用说明)
- [贡献与版本规范](CONTRIBUTING.md) · [变更记录](CHANGELOG.md)

## 致谢与许可

- 字体：[Space Grotesk](https://github.com/floriankarsten/space-grotesk)（SIL OFL 1.1），以及 [MiSans](https://hyperos.mi.com/font)（小米 MiSans 字体知识产权许可协议）。本软件使用了 MiSans 字体。按 MiSans 许可，仓库中不包含其字体文件。
- 本仓库公开源代码供查阅，但**未授予开源许可**，保留所有权利。
