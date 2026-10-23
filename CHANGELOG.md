# 变更记录

本文件从 v0.2.0 起由 [Release Please](https://github.com/googleapis/release-please) 根据 Conventional Commits 自动生成。每个版本的详细说明见 [开发日志](docs/开发日志)。

## [1.0.0](https://github.com/vvangz/JikeLog/compare/v0.9.0...v1.0.0) (2026-10-23)


### 新功能

* **ci:** 发布新版本时构建签名 APK 并附到 GitHub Release ([90fd409](https://github.com/vvangz/JikeLog/commit/90fd409cbdee1db22fd733f6ae2b5f75354d2650))
* **deploy:** 正式环境每个账号的附件配额默认 8GB ([b7ae5f7](https://github.com/vvangz/JikeLog/commit/b7ae5f78595c140c4aff537a67fcd22c0bfc9b8c))
* **mobile:** 正式版使用发布密钥签名 ([5c52d64](https://github.com/vvangz/JikeLog/commit/5c52d64cc135f47db7de8f7e5987db95003250ba))


### 问题修复

* **ci:** 发布后自动部署读不到 production 环境的 Secrets ([00175de](https://github.com/vvangz/JikeLog/commit/00175de76d2261d082376656481f5885c1b3b1c9))
* **ci:** 签名与构建分开，签名密钥不与仓库代码同处一台机器 ([073a72b](https://github.com/vvangz/JikeLog/commit/073a72b92d097d4deea83f23406a1027ea22cae5))
* **ci:** 部署前校验 SSH 私钥并先确认能登录服务器 ([7c44ef6](https://github.com/vvangz/JikeLog/commit/7c44ef625487099e0ec8202c1cbf23004f278433))
* **deploy:** 解包发布包时不保留包内属主 ([b29aea4](https://github.com/vvangz/JikeLog/commit/b29aea4df491b5f47bf9afce3aa6a819fabde573))
* **mobile:** 使用即刻日志的应用图标，替换 Flutter 默认图标 ([2678252](https://github.com/vvangz/JikeLog/commit/2678252fec2e2d872fb08100af44d3da9f65d0c1))
* **server:** 升级 Go 1.27.3 与 excelize 修复新公布的漏洞 ([20aac47](https://github.com/vvangz/JikeLog/commit/20aac470d12aa037b87b857c19bdad8e990d24a7))
* **server:** 阿里云验证码与 KMS 的错误提示不再提"v0.9.0 接入" ([7362843](https://github.com/vvangz/JikeLog/commit/73628435d3c207f658aeeba8cbf39040edcf0795))


### 文档

* v1.0.0 开发日志（正式发布） ([34cd3c5](https://github.com/vvangz/JikeLog/commit/34cd3c597e6fbab0b0cefc4b158d9dacf93f9a04))
* v1.0.0 文档定稿与发布说明 ([3f55f5d](https://github.com/vvangz/JikeLog/commit/3f55f5dc90b0e360152f93b689e982a8de3e836d))

## [0.9.0](https://github.com/vvangz/JikeLog/compare/v0.8.0...v0.9.0) (2026-10-13)


### 新功能

* **deploy:** 单机正式部署、GitHub Actions 发布与 14 天加密备份（ADR-012） ([196ec25](https://github.com/vvangz/JikeLog/commit/196ec25319495af928fa78917edf188daa144e2a))
* **mobile:** 正式版只信任 Let's Encrypt 根证书（锁定 CA） ([a89c42b](https://github.com/vvangz/JikeLog/commit/a89c42b5e767e1f430967bb4c6a09e39e05fd139))
* 短信未开通的模式与服务端功能开关 ([380e7ce](https://github.com/vvangz/JikeLog/commit/380e7ce0514081ec9b771e0d75b3764ad892dd2d))


### 问题修复

* **deploy:** 只能写入的 OSS AccessKey 上传备份时不做 HEAD 校验 ([40b55c0](https://github.com/vvangz/JikeLog/commit/40b55c03815f947bc3669acdb56000c1cdf21eaf))


### 性能优化

* **server:** 推送整批预读记录并以管道批量插入 ([4a230cd](https://github.com/vvangz/JikeLog/commit/4a230cd78e1f44c412e23aa4ee04c212f37e0865))


### 文档

* v0.9.0 开发日志（M8 上线准备） ([3b78b19](https://github.com/vvangz/JikeLog/commit/3b78b191693a4bf18a25c69848c09fdcd23af80d))
* 记录一次性准备已完成，推送 500 条暂时接受现状 ([5e791eb](https://github.com/vvangz/JikeLog/commit/5e791ebe3cac16cac7681fcebe8be42aafe0589c))

## [0.8.0](https://github.com/vvangz/JikeLog/compare/v0.7.0...v0.8.0) (2026-10-11)


### 新功能

* **admin:** Web 管理后台：登录、仪表盘、用户、审计日志、管理员管理 ([c046930](https://github.com/vvangz/JikeLog/commit/c0469309308c2b86da817748563c4d427824df70))
* **admin:** 侧栏改为点击左上角图标后从左向右展开，带过渡动画 ([e90a6e1](https://github.com/vvangz/JikeLog/commit/e90a6e164bd1ca0e69c73eb5262785eb31b3d86c))
* **server:** 管理后台接口：独立的管理员账号与会话、只读的用户配置、审计日志 ([230a3a4](https://github.com/vvangz/JikeLog/commit/230a3a4200dd2a2284cebbfc8457b1f6c342a13e))


### 问题修复

* **admin:** 侧栏与内容区改为左右排列，修复内容被挤出可视区域 ([8f5aff4](https://github.com/vvangz/JikeLog/commit/8f5aff4ec54b6a7c9149b1fd7191faaa4c04c980))
* **admin:** 本地预览与开发服务器明确监听 127.0.0.1 ([1ebfc76](https://github.com/vvangz/JikeLog/commit/1ebfc76288d31f0676059dab39f8577301beec1e))
* **server:** jikelog-admin 校验失败时显示具体原因 ([0c93073](https://github.com/vvangz/JikeLog/commit/0c930738c1d84b582d8bb52894555c5c1bf7f7c8))
* 处理 M7 审查意见 ([c6877b2](https://github.com/vvangz/JikeLog/commit/c6877b23d00480ba20a821ca65c9f6d666f28567))


### 文档

* v0.8.0 开发日志与审查记录 ([2a6b844](https://github.com/vvangz/JikeLog/commit/2a6b8447553f63b6c71395ae532267e9a8da6475))

## [0.7.0](https://github.com/vvangz/JikeLog/compare/v0.6.0...v0.7.0) (2026-10-11)


### 新功能

* **mobile:** 全局搜索：本地 FTS5 trigram 索引，按模块和时间筛选 ([dcd9051](https://github.com/vvangz/JikeLog/commit/dcd90510d60601606d29263bef21d81f32d8bd51))
* **mobile:** 数据导出页面：选择模块发起导出、查看进度、下载后分享或保存 ([27a2441](https://github.com/vvangz/JikeLog/commit/27a2441c544e90a862823907543d18db9f598d4c))
* **server:** 数据导出：后台生成 zip（xlsx、Markdown、ICS、CSV、JSON 与附件），保留 24 小时 ([7fe0b85](https://github.com/vvangz/JikeLog/commit/7fe0b85f60d5277517dea06560db5f6aec6a671e))


### 问题修复

* **deps:** excelize 升级到 v2.11.0（GO-2026-5960） ([4f82414](https://github.com/vvangz/JikeLog/commit/4f82414b1019461dfc38a9610f5146cdea676963))
* **mobile:** 处理 M6 审查意见 ([fa32575](https://github.com/vvangz/JikeLog/commit/fa325752d2dfc87769f814db98ba087e62c7c36c))
* **server:** 处理 M6 审查意见 ([31f85ff](https://github.com/vvangz/JikeLog/commit/31f85ffcd9e18015c72ff93f6dc36acf6ba5456f))


### 文档

* ADR-010 全局搜索与数据导出 ([f58e657](https://github.com/vvangz/JikeLog/commit/f58e657eb682615279accda0ba8b7cd079c35ed2))
* 使用说明 08 搜索与导出；架构总览补充搜索与导出 ([7fb05de](https://github.com/vvangz/JikeLog/commit/7fb05de7f6902ec337e82f1abf90d023d6f5d821))

## [0.6.0](https://github.com/vvangz/JikeLog/compare/v0.5.0...v0.6.0) (2026-10-10)


### 新功能

* **mobile:** 记账数据层：模型、金额工具、预置分类、仓储与统计计算 ([66848d9](https://github.com/vvangz/JikeLog/commit/66848d9da26cf0a3c7a367de89072fb98c0e6872))
* **mobile:** 记账界面：流水、统计图表、账户与借贷、分类管理 ([6057285](https://github.com/vvangz/JikeLog/commit/60572857d5907ac899a5162c255050e6272a0738))
* **server:** 记账同步实体：账户、分类、借贷、流水（M5 服务端） ([87aaa2b](https://github.com/vvangz/JikeLog/commit/87aaa2b5a7c26eca572b1ea75eee41480f103272))


### 问题修复

* 处理 M5 审查意见 ([e5a1147](https://github.com/vvangz/JikeLog/commit/e5a114755f97951f8405cc6e239dadb9a15f401f))


### 文档

* v0.6.0 开发日志与审查记录；ADR-009 补充审查结论 ([9c14153](https://github.com/vvangz/JikeLog/commit/9c1415314fd417ae0cf4fa995d1839765ab5f49c))
* 使用说明 07 记账；架构总览补充记账 ([3d1fc4f](https://github.com/vvangz/JikeLog/commit/3d1fc4fcd2cb75be1e9c325c4c3b6131cbbb350a))

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
