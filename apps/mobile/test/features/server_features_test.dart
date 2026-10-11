import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';

FakeBackend _noSms() => standardBackend()
  ..on(
    'GET',
    '/api/v1/system/info',
    (_) => FakeResponse.ok({
      'name': 'jikelog-api',
      'version': '0.9.0',
      'commit': 'x',
      'buildTime': 'x',
      'serverTime': '2026-10-11T00:00:00Z',
      'features': {'sms': false, 'push': false},
    }),
  );

void main() {
  tearDown(TestHooks.reset);

  testWidgets('服务端未开通短信：登录页只有密码登录，没有找回密码；注册页提示牢记密码', (tester) async {
    await pumpApp(tester, backend: _noSms(), signedIn: false);
    expect(find.text('登录即刻日志'), findsOneWidget);
    expect(find.text('验证码登录'), findsNothing);
    expect(find.text('忘记密码'), findsNothing);
    await tapAndSettle(tester, find.text('注册新账号'));
    expect(find.textContaining('暂时无法通过手机号找回密码'), findsOneWidget);
  });

  testWidgets('服务端未开通短信：帐号页的手机号不可操作，修改密码只用当前密码', (tester) async {
    await pumpApp(
      tester,
      backend: _noSms(),
      user: userJson(phoneMasked: '138****5678'),
    );
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tapAndSettle(tester, find.byKey(const Key('nav-/account')));
    final tile = tester.widget<ListTile>(
      find.byKey(const Key('account-phone')),
    );
    expect(tile.enabled, isFalse);
    expect(find.textContaining('短信功能暂未开放'), findsOneWidget);
    await tapAndSettle(tester, find.text('修改密码'));
    expect(find.text('手机验证码'), findsNothing);
  });

  testWidgets('查询不到服务端功能时按全部开通处理', (tester) async {
    await pumpApp(tester, signedIn: false);
    expect(find.text('验证码登录'), findsOneWidget);
    expect(find.text('忘记密码'), findsOneWidget);
  });
}
