import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/api/api_client.dart';
import 'package:jikelog/core/api/api_exception.dart';
import 'package:jikelog/core/api/endpoints.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/storage/stores.dart';

import '../../support/fake_backend.dart';

void main() {
  test('User 往返序列化与显示名', () {
    final u = User.fromJson(userJson(phoneMasked: '138****8000'));
    expect(u.displayName, '张三');
    expect(User.fromJson(u.toJson()).phoneMasked, '138****8000');
    expect(User.fromJson(userJson(nickname: '')).displayName, 'zhangsan');
  });

  test('缺字段时抛出 FormatException', () {
    expect(() => User.fromJson({'id': 1}), throwsFormatException);
    expect(
      () => SmsLoginResult.fromJson({'status': 'weird'}),
      throwsFormatException,
    );
  });

  test('短信登录结果两种状态', () {
    final ok = SmsLoginResult.fromJson({
      'status': 'authenticated',
      'session': sessionJson(),
    });
    expect(ok, isA<SmsAuthenticated>());
    final reg = SmsLoginResult.fromJson({
      'status': 'registration_required',
      'registrationTicket': 't',
      'phoneMasked': '138****8000',
    });
    expect(
      reg,
      isA<SmsRegistrationRequired>().having((r) => r.ticket, 'ticket', 't'),
    );
  });

  test('UserSettings 相等性与 copyWith', () {
    const a = UserSettings();
    expect(a, const UserSettings(defaultReminders: [0]));
    expect(a.hashCode, const UserSettings().hashCode);
    final b = a.copyWith(
      themeMode: 'dark',
      fontScale: 1.2,
      defaultReminders: [5],
      weekStart: 7,
    );
    expect(b, isNot(a));
    expect(UserSettings.fromJson(b.toJson()), b);
  });

  test('TokenStore 实现', () async {
    final m = MemoryTokenStore();
    expect(await m.read(), isNull);
    await m.write(testTokens);
    expect((await m.read())!.accessToken, 'access-1');
    await m.clear();
    expect(await m.read(), isNull);
    final kv = MemoryStore({'a': '1'});
    expect(kv.getString('a'), '1');
    await kv.setString('b', '2');
    await kv.remove('a');
    expect(kv.getString('a'), isNull);
  });

  test('ApiException 对无信封错误的处理', () {
    final e = ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(),
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 503,
          data: 'down',
        ),
      ),
    );
    expect(e.status, 503);
    expect(e.isNetwork, isFalse);
  });

  test('接口方法解析响应', () async {
    final b = FakeBackend()
      ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(userJson()))
      ..on(
        'GET',
        '/api/v1/me/devices',
        (_) => FakeResponse.ok([
          {
            'id': 'd1',
            'platform': 'android',
            'model': 'M',
            'osVersion': 'A',
            'appVersion': '1',
            'lastActiveAt': '2026-10-09T08:00:00Z',
            'createdAt': '2026-10-09T08:00:00Z',
            'current': true,
          },
        ]),
      )
      ..on(
        'GET',
        '/api/v1/me/settings',
        (_) => FakeResponse.ok(const UserSettings().toJson()),
      )
      ..on(
        'DELETE',
        '/api/v1/me/devices/d1',
        (_) => FakeResponse.ok({'ok': true}),
      )
      ..on('POST', '/api/v1/auth/logout', (_) => FakeResponse.ok({'ok': true}))
      ..on(
        'POST',
        '/api/v1/auth/sms/send',
        (_) =>
            FakeResponse.ok({'cooldownSeconds': 60, 'expiresInSeconds': 300}),
      );
    final c = ApiClient(
      baseUrl: 'http://t',
      tokenStore: MemoryTokenStore(testTokens),
      adapter: b,
    );
    await c.restore();
    final account = AccountApi(c);
    expect((await account.me()).username, 'zhangsan');
    expect((await account.devices()).single.current, isTrue);
    expect(await account.settings(), const UserSettings());
    await account.revokeDevice('d1');
    await AuthApi(c, testDevice).logout();
    expect(
      await AuthApi(c, testDevice).sendSms('13800000000', SmsPurpose.login),
      60,
    );
  });
}
