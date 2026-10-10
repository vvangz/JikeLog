import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/config.dart';

void main() {
  test('除调试构建外不能使用公开的开发示例公钥', () {
    const dev = AppConfig.devE2EPublicKey;
    const prod = 'cHJvZHVjdGlvbi1rZXktcHJvZHVjdGlvbi1rZXktMDA=';
    String? check({
      required bool release,
      required bool debug,
      String key = dev,
      bool allow = false,
    }) => AppConfig.e2eKeyProblem(
      release: release,
      debug: debug,
      key: key,
      allowDev: allow,
    );

    expect(check(release: false, debug: true), isNull);
    expect(check(release: true, debug: false), isNotNull);
    expect(
      check(release: true, debug: false, allow: true),
      isNotNull,
      reason: '正式构建不能放行',
    );
    expect(
      check(release: false, debug: false),
      isNotNull,
      reason: 'profile 构建默认拒绝',
    );
    expect(check(release: false, debug: false, allow: true), isNull);
    expect(check(release: true, debug: false, key: prod), isNull);
  });
}
