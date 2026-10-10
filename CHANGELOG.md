# 变更记录

本文件从 v0.2.0 起由 [Release Please](https://github.com/googleapis/release-please) 根据 Conventional Commits 自动生成。每个版本的详细说明见 [开发日志](docs/开发日志)。

## [0.5.0](https://github.com/vvangz/JikeLog/compare/v0.4.0...v0.5.0) (2026-10-10)


### 新功能

* **mobile:** 备忘录、日历视图、本地提醒、推送登记与系统日历同步 ([6e6477e](https://github.com/vvangz/JikeLog/commit/6e6477edfe3b037f3bafe57bf72dd5d7da7499b1))
* **server:** 备忘录同步实体、提醒调度与推送登记（M4 服务端） ([4b2071b](https://github.com/vvangz/JikeLog/commit/4b2071b0cd5ac549a189e50f36924512f32d82b1))


### 问题修复

* 处理 M4 审查意见 ([571a6e2](https://github.com/vvangz/JikeLog/commit/571a6e2840dec9a8108601b575f2cd003743bac8))


### 文档

* v0.5.0 开发日志与审查记录；使用说明 06 备忘录 ([6cb0980](https://github.com/vvangz/JikeLog/commit/6cb09803200e5b66f5e762bd1ad810ebf6e27512))

## [0.4.0](https://github.com/vvangz/JikeLog/compare/v0.3.0...v0.4.0) (2026-10-10)


### 新功能

* **mobile:** 笔记数据层：实体、关联索引、文件夹树与筛选 ([fe62067](https://github.com/vvangz/JikeLog/commit/fe620676db84a08d1cc27bb5d5a9a60ced617d37))
* **mobile:** 笔记模块：双格式编辑、文件夹、标签、收藏、附件与关联工作日志 ([938b70f](https://github.com/vvangz/JikeLog/commit/938b70ff40507f733e188516d56085ea6da39942))
* **note-editor:** Tiptap 富文本编辑器，构建为单个 HTML 供 WebView 加载 ([e7550f1](https://github.com/vvangz/JikeLog/commit/e7550f19bc39b33e2a280ad5d04208cb94961a80))
* **server:** 笔记与笔记文件夹同步实体（M3 服务端） ([5514ac1](https://github.com/vvangz/JikeLog/commit/5514ac1c5d4a5c87222e210c72bbaae0f6ddd91d))


### 问题修复

* **mobile:** 处理 M3 审查意见 ([faf3f91](https://github.com/vvangz/JikeLog/commit/faf3f911f3a69acc9fcdb64aa2afc4748b569190))
* **note-editor:** 用自己的构建插件内联脚本与样式，去掉有高危漏洞公告的依赖 ([59ae52b](https://github.com/vvangz/JikeLog/commit/59ae52b8cc3f8427d5fb717490633b5096cd75f6))


### 文档

* v0.4.0 开发日志与审查记录；使用说明 05 笔记 ([8016609](https://github.com/vvangz/JikeLog/commit/801660971e78bd2795295f377ba0d25d7969dfeb))

## [0.3.0](https://github.com/vvangz/JikeLog/compare/v0.2.0...v0.3.0) (2026-10-10)


### 新功能

* **mobile:** 工作日志模块、附件、实时通知与同步生命周期 ([7439ad2](https://github.com/vvangz/JikeLog/commit/7439ad2d0d48bee60d271384e6ab597162b856c1))
* **mobile:** 本地数据库、HLC、传输加密、文本补丁与同步引擎 ([220bbee](https://github.com/vvangz/JikeLog/commit/220bbee12ee0f1c5b142cd40c63b62b2e50c5af0))
* **server:** 同步、传输加密、落库加密、附件与实时通知（M2 服务端） ([e3548ba](https://github.com/vvangz/JikeLog/commit/e3548ba2e6636bd9ff02b083ba08fbda1ffa0e61))


### 问题修复

* **mobile:** 处理 M2 审查意见 ([f3462e1](https://github.com/vvangz/JikeLog/commit/f3462e179169fca9ba9441e106a6e7e3e3f90f83))
* **server:** 修复 CI 中的数据竞争、密钥扫描与 TS 类型 ([77a78e4](https://github.com/vvangz/JikeLog/commit/77a78e4d38e2259e4f4390c4a0bc50242f4987ca))
* **server:** 合并结果使用新的服务端时钟 ([12f9164](https://github.com/vvangz/JikeLog/commit/12f91642e1acbf1eafcea69f828b3b473a4632ec))
* **server:** 处理 M2 审查意见 ([84c2c38](https://github.com/vvangz/JikeLog/commit/84c2c382076e551606c26651f90d369bc8346d01))


### 文档

* ADR 索引与本地开发环境补充 M2 配置 ([1cc075b](https://github.com/vvangz/JikeLog/commit/1cc075b309c65f36165616beade1963e8f2f3c10))
* v0.3.0 开发日志与审查记录；登录失效保留本机数据的说明 ([abe3f17](https://github.com/vvangz/JikeLog/commit/abe3f17e3ca55a6b30a3871a87813e67a822b97b))
* 使用说明 03 工作日志、04 多设备同步 ([0390a73](https://github.com/vvangz/JikeLog/commit/0390a7399ba7165ff92ed42fe1c2f6b68d122fe4))

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
