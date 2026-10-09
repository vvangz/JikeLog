/// 编译期配置，通过 `--dart-define` 注入。
abstract final class AppConfig {
  /// API 地址。默认指向 Android 模拟器访问宿主机的 10.0.2.2；
  /// 真机调试或发布构建用 `--dart-define=JIKELOG_API_BASE=https://api.example.com` 覆盖。
  static const apiBaseUrl = String.fromEnvironment(
    'JIKELOG_API_BASE',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// 服务端传输加密公钥（X25519，base64），用于工作日志的应用层加密（ADR-006）。
  /// 默认值为公开的开发示例公钥，正式构建必须用
  /// `--dart-define=JIKELOG_E2E_PUBLIC_KEY=…` 换成生产公钥（启动时校验）。
  static const e2ePublicKey = String.fromEnvironment(
    'JIKELOG_E2E_PUBLIC_KEY',
    defaultValue: devE2EPublicKey,
  );

  /// 开发示例公钥，对应 deploy/.env.example 中的 JIKELOG_E2E_PRIVATE_KEY。
  static const devE2EPublicKey = 'hzHoYda9NBwh0f7KEN0UVflj0FcozpvvPh4esvLPnhM=';

  /// 隐私政策版本：政策更新后递增，用户需重新同意。
  static const privacyPolicyVersion = 1;
}
