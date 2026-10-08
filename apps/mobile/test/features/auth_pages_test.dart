import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/auth/login_page.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';

void main() {
  testWidgets('首次启动先显示隐私政策，同意后进入登录页', (tester) async {
    await pumpApp(tester, consented: false, signedIn: false);
    expect(find.text('欢迎使用即刻日志'), findsOneWidget);
    await tapAndSettle(tester, find.text('《隐私政策》'));
    expect(find.textContaining('我们收集的信息'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20)); // 关闭底部弹层
    await settleApp(tester);
    await tapAndSettle(tester, find.text('《用户协议》'));
    expect(find.textContaining('妥善保管账号'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await settleApp(tester);

    await tapAndSettle(tester, find.byKey(const Key('consent-accept')));
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('密码登录：本地校验、服务端错误提示、成功进入首页', (tester) async {
    final b = await pumpApp(tester, signedIn: false);
    await tapAndSettle(tester, find.byKey(const Key('login-submit')));
    expect(find.text('请输入用户名'), findsOneWidget);
    expectRequestCount(b, 'POST', '/api/v1/auth/login/password', 0);

    b.on(
      'POST',
      '/api/v1/auth/login/password',
      (_) =>
          FakeResponse.error(401, 'INVALID_CREDENTIALS', message: '用户名或密码错误'),
    );
    await enter(tester, const Key('login-username'), 'zhangsan');
    await enter(tester, const Key('login-password'), 'wrong');
    await tapAndSettle(tester, find.byKey(const Key('login-submit')));
    expect(find.text('用户名或密码错误'), findsOneWidget);

    b.on(
      'POST',
      '/api/v1/auth/login/password',
      (_) => FakeResponse.ok(sessionJson()),
    );
    await tapAndSettle(tester, find.byKey(const Key('login-submit')));
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('工作日志'), findsWidgets);
    expect(
      b.last('POST', '/api/v1/auth/login/password').body!['username'],
      'zhangsan',
    );
  });

  testWidgets('显示/隐藏密码', (tester) async {
    await pumpApp(tester, signedIn: false);
    final field = find.descendant(
      of: find.byKey(const Key('login-password')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).obscureText, isTrue);
    await tapAndSettle(tester, find.byTooltip('显示密码'));
    expect(tester.widget<EditableText>(field).obscureText, isFalse);
  });

  testWidgets('短信登录新号码：发送验证码倒计时 → 完善注册 → 进入首页', (tester) async {
    final b = await pumpApp(tester, signedIn: false);
    b
      ..on(
        'POST',
        '/api/v1/auth/login/sms',
        (_) => FakeResponse.ok({
          'status': 'registration_required',
          'registrationTicket': 'ticket-1',
          'phoneMasked': '138****8000',
        }),
      )
      ..on(
        'POST',
        '/api/v1/auth/register/sms',
        (_) => FakeResponse.ok(sessionJson(), status: 201),
      );
    await tapAndSettle(tester, find.text('验证码登录'));

    await tapAndSettle(tester, find.text('获取验证码'));
    expect(find.text('请输入正确的中国大陆手机号'), findsOneWidget);
    expectRequestCount(b, 'POST', '/api/v1/auth/sms/send', 0);

    await enter(tester, const Key('login-phone'), '138 0013 8000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(b.last('POST', '/api/v1/auth/sms/send').body, {
      'phone': '13800138000',
      'purpose': 'login',
    });
    expect(find.text('验证码已发送'), findsOneWidget);
    expect(find.textContaining('秒后重发'), findsOneWidget);

    await enter(tester, const Key('login-code'), '123456');
    await tapAndSettle(tester, find.byKey(const Key('login-submit')));
    expect(find.text('完善注册'), findsOneWidget);
    expect(find.textContaining('138****8000'), findsOneWidget);

    await enter(tester, const Key('reg-username'), 'zhangsan');
    await enter(tester, const Key('reg-password'), 'secret123');
    await enter(tester, const Key('reg-confirm'), 'secret124');
    await tapAndSettle(tester, find.byKey(const Key('complete-submit')));
    expect(find.text('两次输入的密码不一致'), findsOneWidget);

    await enter(tester, const Key('reg-confirm'), 'secret123');
    await tapAndSettle(tester, find.byKey(const Key('complete-submit')));
    expect(
      b.last('POST', '/api/v1/auth/register/sms').body!['registrationTicket'],
      'ticket-1',
    );
    expect(find.text('工作日志'), findsWidgets);
    await tester.pump(const Duration(minutes: 1)); // 结束倒计时定时器
  });

  testWidgets('发送验证码被限流时提示原因', (tester) async {
    final b = await pumpApp(tester, signedIn: false);
    b.on(
      'POST',
      '/api/v1/auth/sms/send',
      (_) => FakeResponse.error(
        429,
        'SMS_RATE_LIMITED',
        message: '验证码发送过于频繁，请稍后再试',
        details: {'retryAfterSeconds': 42},
      ),
    );
    await tapAndSettle(tester, find.text('验证码登录'));
    await enter(tester, const Key('login-phone'), '13800138000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(find.text('验证码发送过于频繁，请稍后再试'), findsOneWidget);
    expect(find.textContaining('秒后重发'), findsOneWidget); // 按服务端给出的剩余时间倒计时
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('注册：服务端字段错误显示在对应输入框', (tester) async {
    final b = await pumpApp(tester, signedIn: false);
    b.on(
      'POST',
      '/api/v1/auth/register',
      (_) => FakeResponse.error(
        422,
        'VALIDATION_FAILED',
        details: {
          'fields': {'username': '用户名已被占用'},
        },
      ),
    );
    await tapAndSettle(tester, find.text('注册新账号'));
    await enter(tester, const Key('reg-username'), 'zhangsan');
    await enter(tester, const Key('reg-password'), 'secret123');
    await enter(tester, const Key('reg-confirm'), 'secret123');
    await tapAndSettle(tester, find.byKey(const Key('register-submit')));
    expect(find.text('用户名已被占用'), findsOneWidget);

    b.on(
      'POST',
      '/api/v1/auth/register',
      (_) => FakeResponse.ok(sessionJson(), status: 201),
    );
    await tapAndSettle(tester, find.byKey(const Key('register-submit')));
    expect(find.text('工作日志'), findsWidgets);
  });

  testWidgets('找回密码', (tester) async {
    final b = await pumpApp(tester, signedIn: false);
    b.on(
      'POST',
      '/api/v1/auth/password/reset',
      (_) => FakeResponse.ok({'ok': true}),
    );
    await tapAndSettle(tester, find.text('忘记密码'));
    expect(find.text('找回密码'), findsOneWidget);
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(find.text('请输入正确的中国大陆手机号'), findsOneWidget);

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), '13800138000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(
      b.last('POST', '/api/v1/auth/sms/send').body!['purpose'],
      'reset_password',
    );
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'newsecret1');
    await tapAndSettle(tester, find.text('重置密码'));
    expect(b.last('POST', '/api/v1/auth/password/reset').body, {
      'phone': '13800138000',
      'code': '123456',
      'newPassword': 'newsecret1',
    });
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('会话失效回到登录页并说明原因', (tester) async {
    final b = await pumpApp(tester);
    b
      ..on(
        'GET',
        '/api/v1/me/devices',
        (_) => FakeResponse.error(401, 'UNAUTHORIZED'),
      )
      ..on(
        'POST',
        '/api/v1/auth/refresh',
        (_) => FakeResponse.error(401, 'REFRESH_INVALID'),
      );
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tapAndSettle(tester, find.byKey(const Key('nav-/account')));
    await tapAndSettle(tester, find.byKey(const Key('account-devices')));
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('登录已失效，请重新登录'), findsOneWidget);
  });
}
