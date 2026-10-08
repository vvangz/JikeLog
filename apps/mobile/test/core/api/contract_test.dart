// 契约测试：手写的 Dart 客户端与 server/api/openapi.yaml 保持一致。
// - 每个接口发出的请求体字段都在契约中声明，契约要求的字段都已发送；
// - 每个响应模型能解析只包含契约必填字段的数据，序列化出的字段都在契约中声明。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/api/api_client.dart';
import 'package:jikelog/core/api/endpoints.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:yaml/yaml.dart';

import '../../support/fake_backend.dart';

late Map<dynamic, dynamic> _spec;

Map<dynamic, dynamic> _resolve(Map<dynamic, dynamic> schema) {
  final ref = schema[r'$ref'] as String?;
  if (ref != null) {
    final name = ref.split('/').last;
    return _resolve((_spec['components']['schemas'] as Map)[name] as Map);
  }
  final allOf = schema['allOf'] as List?;
  if (allOf == null) return schema;
  final props = <dynamic, dynamic>{};
  final required = <dynamic>{};
  for (final part in allOf) {
    final r = _resolve(part as Map);
    props.addAll((r['properties'] as Map?) ?? {});
    required.addAll((r['required'] as List?) ?? []);
  }
  return {'type': 'object', 'properties': props, 'required': required.toList()};
}

Map<dynamic, dynamic> _schema(String name) =>
    _resolve({r'$ref': '#/components/schemas/$name'});

Set<String> _props(Map<dynamic, dynamic> s) => {
  ...((s['properties'] as Map?) ?? {}).keys.cast<String>(),
};

Set<String> _required(Map<dynamic, dynamic> s) => {
  ...((s['required'] as List?) ?? []).cast<String>(),
};

/// 请求体 schema（application/json）。
Map<dynamic, dynamic> _requestSchema(String method, String path) {
  final op = (_spec['paths'][path] as Map)[method.toLowerCase()] as Map;
  return _resolve(
    op['requestBody']['content']['application/json']['schema'] as Map,
  );
}

/// 按契约生成只含必填字段的示例数据。
Object? _sample(Map<dynamic, dynamic> schema) {
  final s = _resolve(schema);
  if (s['enum'] != null) return (s['enum'] as List).first;
  switch (s['type']) {
    case 'object':
      final props = (s['properties'] as Map?) ?? {};
      return {for (final k in _required(s)) k: _sample(props[k] as Map)};
    case 'array':
      return [_sample(s['items'] as Map)];
    case 'boolean':
      return true;
    case 'integer':
      return 1;
    case 'number':
      return 1.0;
    default:
      return switch (s['format']) {
        'date-time' => '2026-10-09T08:00:00Z',
        'uuid' => '0192a000-0000-7000-8000-000000000001',
        _ => 'x',
      };
  }
}

void main() {
  setUpAll(() {
    _spec = loadYaml(
      File('../../server/api/openapi.yaml').readAsStringSync(),
    ) as Map;
  });

  test('请求体字段与契约一致', () async {
    final backend = FakeBackend();
    final client = ApiClient(
      baseUrl: 'http://t',
      tokenStore: MemoryTokenStore(testTokens),
      adapter: backend,
    );
    await client.restore();
    final auth = AuthApi(client, testDevice);
    final account = AccountApi(client);

    final calls = <(String, String, Future<void> Function())>[
      (
        'POST',
        '/api/v1/auth/register',
        () => auth.register(username: 'u', password: 'p', nickname: 'n'),
      ),
      (
        'POST',
        '/api/v1/auth/login/password',
        () => auth.loginWithPassword('u', 'p'),
      ),
      (
        'POST',
        '/api/v1/auth/sms/send',
        () => auth.sendSms('138', SmsPurpose.login),
      ),
      (
        'POST',
        '/api/v1/auth/login/sms',
        () => auth.loginWithSms('138', '123456'),
      ),
      (
        'POST',
        '/api/v1/auth/register/sms',
        () => auth.completeSmsRegistration(
          ticket: 't',
          username: 'u',
          password: 'p',
          nickname: 'n',
        ),
      ),
      (
        'POST',
        '/api/v1/auth/password/reset',
        () => auth.resetPassword('138', '123456', 'p'),
      ),
      ('PATCH', '/api/v1/me', () => account.updateNickname('n')),
      (
        'POST',
        '/api/v1/me/sms/send',
        () => account.sendSms(SmsPurpose.bindPhone, phone: '138'),
      ),
      (
        'PUT',
        '/api/v1/me/password',
        () => account.changePassword(
          newPassword: 'p',
          currentPassword: 'c',
          smsCode: '1',
        ),
      ),
      (
        'PUT',
        '/api/v1/me/phone',
        () => account.bindPhone(
          phone: '138',
          code: '1',
          currentPassword: 'p',
          currentCode: '2',
        ),
      ),
      (
        'POST',
        '/api/v1/me/deletion',
        () => account.deleteAccount(currentPassword: 'p', smsCode: '1'),
      ),
      (
        'PUT',
        '/api/v1/me/settings',
        () => account.saveSettings(const UserSettings()),
      ),
    ];
    for (final (method, path, call) in calls) {
      try {
        await call();
      } on Object {
        // 假后端对未注册路由返回 404，这里只检查请求体
      }
      final sent = backend.last(method, path).body ?? {};
      final schema = _requestSchema(method, path);
      expect(
        _props(schema).containsAll(sent.keys),
        isTrue,
        reason: '$method $path 发送了契约未声明的字段 ${sent.keys}',
      );
      expect(
        sent.keys.toSet().containsAll(_required(schema)),
        isTrue,
        reason: '$method $path 缺少必填字段',
      );
      if (sent['device'] is Map) {
        final dev = _schema('DeviceInfo');
        expect(_props(dev).containsAll((sent['device'] as Map).keys), isTrue);
      }
    }
  });

  test('响应模型能解析契约必填字段，序列化字段均在契约中', () {
    final user = User.fromJson(
      _sample(_schema('User'))! as Map<String, dynamic>,
    );
    expect(_props(_schema('User')).containsAll(user.toJson().keys), isTrue);

    final tokens = TokenPair.fromJson(
      _sample(_schema('TokenPair'))! as Map<String, dynamic>,
    );
    expect(
      _props(_schema('TokenPair')).containsAll(tokens.toJson().keys),
      isTrue,
    );

    AuthSession.fromJson(
      _sample(_schema('AuthSession'))! as Map<String, dynamic>,
    );
    Device.fromJson(_sample(_schema('Device'))! as Map<String, dynamic>);

    final settings = UserSettings.fromJson(
      (_sample(_schema('Settings'))! as Map<String, dynamic>)
        ..['weekStart'] = 1,
    );
    expect(
      _props(_schema('SettingsInput')).containsAll(settings.toJson().keys),
      isTrue,
    );
    expect(_required(_schema('SettingsInput')), settings.toJson().keys.toSet());

    final smsResult = _schema('SmsLoginResult');
    expect(
      (_resolve(smsResult['properties']['status'] as Map)['enum'] as List)
          .toSet(),
      {'authenticated', 'registration_required'},
    );
  });

  test('验证码用途与契约枚举一致', () {
    final auth = (_schema('SmsPurpose')['enum'] as List).toSet();
    final account = (_schema('AccountSmsPurpose')['enum'] as List).toSet();
    expect({...auth, ...account}, SmsPurpose.values.map((p) => p.wire).toSet());
  });
}
