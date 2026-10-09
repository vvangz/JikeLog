# 变更记录

本文件从 v0.2.0 起由 [Release Please](https://github.com/googleapis/release-please) 根据 Conventional Commits 自动生成。每个版本的详细说明见 [开发日志](docs/开发日志)。

## [0.2.0](https://github.com/vvangz/JikeLog/compare/v0.1.0...v0.2.0) (2026-10-09)


### 新功能

* M1 账号体系与 App 外壳（v0.2.0）([#1](https://github.com/vvangz/JikeLog/issues/1)) ([f739b44](https://github.com/vvangz/JikeLog/commit/f739b44d144b41022243f8b19da014c72382c051))
* **mobile:** 导航外壳、账号与设置（M1 移动端） ([2dc67a6](https://github.com/vvangz/JikeLog/commit/2dc67a6d787f6efb5c091ef857f2da149f02ec35))
* **server:** 账号认证与当前账号接口（M1 服务端） ([631907e](https://github.com/vvangz/JikeLog/commit/631907e2c7986a7637be8195e67e6cc7fa94a0cb))


### 问题修复

* **server:** 升级 Go 1.27.2 与 golang.org/x/net v0.60.0 修复漏洞 ([a9c4d37](https://github.com/vvangz/JikeLog/commit/a9c4d37bfe647c08ce95dfe1fa7478962c91d379))
* **server:** 处理 M1 代码审查与安全审查意见 ([9241a9d](https://github.com/vvangz/JikeLog/commit/9241a9d970617f28887555649d1860140e99c0c2))
* **server:** 镜像中构建 jikelog-migrate ([f19ba57](https://github.com/vvangz/JikeLog/commit/f19ba57ea6a4c048a03ac6f5ed91d5fc4e7d6a96))


### 文档

* v0.2.0 开发日志、使用说明与 ADR-003/004 ([d7b0bb1](https://github.com/vvangz/JikeLog/commit/d7b0bb1febe9cba53194f0c749e62eb17a4fbba4))

## 0.1.0 (2026-10-08)

### 新功能

* **仓库**：monorepo 骨架、pnpm workspace、lefthook 钩子、commitlint、Release Please、GitHub Actions CI、Dependabot
* **tokens**：咖色主题设计令牌（浅色/深色），生成 Flutter 与 Web 两端代码，自动校验 WCAG 对比度
* **server**：OpenAPI 契约与代码生成、统一响应信封、请求 ID、访问日志、错误恢复、存活/就绪探针、系统信息接口、配置校验、优雅关闭、Dockerfile
* **admin**：React 19 + Ant Design 6 管理后台骨架，主题切换与侧栏外壳原型，类型化接口客户端
* **mobile**：Flutter 工程（com.jikelog.app）、令牌驱动的浅色/深色主题、Space Grotesk + MiSans 字体、品牌标志
* **deploy**：本地开发依赖（PostgreSQL 17、Redis 7.4、RustFS）

### 文档

* README、贡献与版本规范、架构总览、ADR-001 技术选型、ADR-002 字体分发、设计规范、本地开发环境、v0.1.0 开发日志
