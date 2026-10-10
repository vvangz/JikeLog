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

  /// 本地联调时允许 profile 构建使用开发示例公钥（`--dart-define=JIKELOG_ALLOW_DEV_E2E_KEY=true`）。
  /// 对正式（release）构建无效。
  static const allowDevE2EKey = bool.fromEnvironment(
    'JIKELOG_ALLOW_DEV_E2E_KEY',
  );

  /// 检查传输加密公钥，返回错误说明（没有问题时为 null）。
  /// 示例私钥是公开的，除调试构建外都不能使用：release 一律拒绝，profile 需显式允许。
  static String? e2eKeyProblem({
    required bool release,
    required bool debug,
    String key = e2ePublicKey,
    bool allowDev = allowDevE2EKey,
  }) {
    if (debug || key != devE2EPublicKey) return null;
    if (!release && allowDev) return null;
    return '非调试构建必须通过 --dart-define=JIKELOG_E2E_PUBLIC_KEY=… 指定服务器的传输加密公钥';
  }

  /// 隐私政策版本：政策更新后递增，用户需重新同意。
  static const privacyPolicyVersion = 2;
}
