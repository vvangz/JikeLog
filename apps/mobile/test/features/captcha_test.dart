import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/api/server_features.dart';
import 'package:jikelog/core/platform/platform_features.dart';
import 'package:jikelog/features/auth/captcha.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';

const _captcha = {'region': 'cn', 'prefix': 'pre1', 'sceneId': 'scene1'};

FakeBackend _withCaptcha({Map<String, dynamic>? user}) =>
    standardBackend(user: user)..on(
      'GET',
      '/api/v1/system/info',
      (_) => FakeResponse.ok({
        'name': 'jikelog-api',
        'version': '1.3.0',
        'commit': 'x',
        'buildTime': 'x',
        'serverTime': '2026-10-26T00:00:00Z',
        'features': {'sms': true, 'push': false, 'captcha': _captcha},
      }),
    );

void main() {
  tearDown(TestHooks.reset);

  testWidgets('需要人机验证：验证通过后带上验证结果发送登录验证码', (tester) async {
    final b = await pumpApp(tester, backend: _withCaptcha(), signedIn: false);
    await tapAndSettle(tester, find.text('验证码登录'));
    await enter(tester, const Key('login-phone'), '13800138000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(TestHooks.captchas.single.sceneId, 'scene1');
    expect(TestHooks.captchas.single.prefix, 'pre1');
    expect(b.last('POST', '/api/v1/auth/sms/send').body, {
      'phone': '13800138000',
      'purpose': 'login',
      'captchaVerifyParam': 'captcha-param',
    });
    expect(find.text('验证码已发送'), findsOneWidget);
  });

  testWidgets('关闭人机验证弹层时不发送验证码，也不进入倒计时', (tester) async {
    TestHooks.solveCaptcha = (_) => null;
    final b = await pumpApp(tester, backend: _withCaptcha(), signedIn: false);
    await tapAndSettle(tester, find.text('验证码登录'));
    await enter(tester, const Key('login-phone'), '13800138000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expectRequestCount(b, 'POST', '/api/v1/auth/sms/send', 0);
    expect(find.textContaining('秒后重发'), findsNothing);
    expect(find.text('获取验证码'), findsOneWidget);
  });

  testWidgets('找回密码同样需要人机验证', (tester) async {
    final b = await pumpApp(tester, backend: _withCaptcha(), signedIn: false);
    await tapAndSettle(tester, find.text('忘记密码'));
    await tester.enterText(find.byType(EditableText).at(0), '13800138000');
    await tapAndSettle(tester, find.text('获取验证码'));
    final body = b.last('POST', '/api/v1/auth/sms/send').body!;
    expect(body['purpose'], 'reset_password');
    expect(body['captchaVerifyParam'], 'captcha-param');
  });

  testWidgets('不需要人机验证时直接发送，不带验证结果', (tester) async {
    final b = await pumpApp(tester, signedIn: false);
    await tapAndSettle(tester, find.text('验证码登录'));
    await enter(tester, const Key('login-phone'), '13800138000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(TestHooks.captchas, isEmpty);
    expect(
      b
          .last('POST', '/api/v1/auth/sms/send')
          .body!
          .containsKey('captchaVerifyParam'),
      isFalse,
    );
  });

  testWidgets('Windows 没有 WebView：需要人机验证时只保留密码登录', (tester) async {
    await pumpApp(
      tester,
      backend: _withCaptcha(),
      signedIn: false,
      features: PlatformFeatures.windows,
    );
    expect(find.text('登录即刻日志'), findsOneWidget);
    expect(find.text('验证码登录'), findsNothing);
    expect(find.text('忘记密码'), findsNothing);
  });

  testWidgets('Windows 上不需要人机验证时仍可验证码登录', (tester) async {
    await pumpApp(tester, signedIn: false, features: PlatformFeatures.windows);
    expect(find.text('验证码登录'), findsOneWidget);
  });

  testWidgets('已登录后绑定手机号同样需要人机验证', (tester) async {
    final b = await pumpApp(tester, backend: _withCaptcha());
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tapAndSettle(tester, find.byKey(const Key('nav-/account')));
    await tapAndSettle(tester, find.byKey(const Key('account-phone')));
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'secret123');
    await tester.enterText(fields.at(1), '13900000000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(b.last('POST', '/api/v1/me/sms/send').body, {
      'purpose': 'bind_phone',
      'phone': '13900000000',
      'captchaVerifyParam': 'captcha-param',
    });
  });

  testWidgets('Windows 上需要人机验证时帐号页的手机号不可操作，并说明原因', (tester) async {
    await pumpApp(
      tester,
      backend: _withCaptcha(user: userJson(phoneMasked: '138****5678')),
      features: PlatformFeatures.windows,
    );
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tapAndSettle(tester, find.byKey(const Key('nav-/account')));
    final tile = tester.widget<ListTile>(
      find.byKey(const Key('account-phone')),
    );
    expect(tile.enabled, isFalse);
    expect(find.textContaining('电脑端暂不支持短信验证'), findsOneWidget);
  });

  group('验证码页面', () {
    const config = CaptchaConfig(
      region: 'cn',
      prefix: 'pre"</script>',
      sceneId: 'scene1',
    );

    test('参数经 JSON 编码写入页面', () {
      final html = captchaHtml(config);
      expect(html, contains('"region":"cn"'));
      expect(html, contains('SceneId: "scene1"'));
      expect(html, contains('aliyunCaptcha/AliyunCaptcha.js'));
      expect(html, contains(r'pre\"\x3c/script>'));
      expect('</script>'.allMatches(html).length, 2); // 只有页面自身的两个 script 结束标签
    });

    test('解析页面消息', () {
      expect(
        parseCaptchaMessage('{"type":"success","param":"p1"}'),
        isA<CaptchaPassed>().having((e) => e.param, 'param', 'p1'),
      );
      expect(parseCaptchaMessage('{"type":"ready"}'), isA<CaptchaReady>());
      expect(parseCaptchaMessage('{"type":"error"}'), isA<CaptchaLoadFailed>());
      expect(parseCaptchaMessage('{"type":"success"}'), isNull);
      expect(parseCaptchaMessage('{"type":"success","param":1}'), isNull);
      expect(parseCaptchaMessage('{"type":"other"}'), isNull);
      expect(parseCaptchaMessage('not json'), isNull);
      expect(parseCaptchaMessage('[1]'), isNull);
    });
  });

  test('解析服务端下发的人机验证参数', () {
    final f = ServerFeatures.fromJson({
      'sms': true,
      'push': false,
      'captcha': _captcha,
    });
    expect(f.captcha?.sceneId, 'scene1');
    expect(ServerFeatures.fromJson({'sms': true}).captcha, isNull);
    expect(
      ServerFeatures.fromJson({
        'sms': true,
        'captcha': {'region': 'cn', 'prefix': 1},
      }).captcha,
      isNull,
    );
  });
}
