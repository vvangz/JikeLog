/// 编译期配置，通过 `--dart-define` 注入。
abstract final class AppConfig {
  /// API 地址。默认指向 Android 模拟器访问宿主机的 10.0.2.2；
  /// 真机调试或发布构建用 `--dart-define=JIKELOG_API_BASE=https://api.example.com` 覆盖。
  static const apiBaseUrl = String.fromEnvironment(
    'JIKELOG_API_BASE',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// 隐私政策版本：政策更新后递增，用户需重新同意。
  static const privacyPolicyVersion = 1;
}
