# ADR-004 Dart 接口客户端手写，并用契约测试与 openapi.yaml 对齐

- 状态：已采纳
- 日期：2026-10-09

## 背景

ADR-001 计划由 `openapi.yaml` 生成 Go 服务端、TS 客户端和 Dart 客户端三端代码。M1 实现时评估了两种 Dart 生成方案：

- **openapi-generator（dart-dio）**：依赖 Java 运行时。生成的代码基于 built_value，体积大，风格也和项目里的 Riverpod 不可变模型不一致。
- **swagger_parser**：需要 build_runner、retrofit、json_serializable 一整套代码生成链。每次修改契约都要跑 build_runner，CI 时间也会增加。

M1 的移动端接口只有 18 个，模型字段也不多。

## 决策

- Dart 客户端在 `apps/mobile/lib/core/api/` 下手写，包括模型、`AuthApi` 和 `AccountApi`。统一信封的解包和令牌刷新集中在 `ApiClient` 中实现。
- 新增契约测试 `test/core/api/contract_test.dart`，它直接读取 `server/api/openapi.yaml`，校验三件事：
  - 每个接口发出的请求体字段都在契约中声明，并且契约要求的字段都已发送；
  - 每个响应模型都能解析只包含必填字段的示例数据，序列化后的字段也都在契约中；
  - 枚举值（如验证码用途）与契约一致。
- 契约变更后，如果 Dart 端没有同步修改，CI 的移动端测试会失败。

## 备选方案

- 先引入生成器，日后再迁移：现在接入的成本高于收益。
- 完全不做校验：三端字段一旦不一致，只能在联调时才发现。

## 影响

- 新增接口时，要同时更新 Dart 模型或方法，以及契约测试里的调用清单。
- 如果后续模块（同步、笔记等）让接口规模明显增大，再评估是否切换到代码生成，届时以新的 ADR 记录。
