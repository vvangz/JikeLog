import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/auth/login_page.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';

Future<void> _open(WidgetTester tester, String path) async {
  await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
  await tapAndSettle(tester, find.byKey(Key('nav-$path')));
}

Map<String, dynamic> _device(String id, {bool current = false}) => {
  'id': id,
  'platform': 'android',
  'model': current ? 'Pixel 9' : 'Xiaomi 14',
  'osVersion': 'Android 16',
  'appVersion': '0.2.0',
  'lastActiveAt': '2026-10-09T08:00:00Z',
  'createdAt': '2026-10-01T08:00:00Z',
  'current': current,
};

void main() {
  testWidgets('设置：切换深色主题、字号、一周起始与默认提醒并同步', (tester) async {
    final b = await pumpApp(tester);
    await _open(tester, '/settings');

    await tapAndSettle(tester, find.text('深色'));
    expect(
      Theme.of(tester.element(find.text('主题'))).brightness,
      Brightness.dark,
    );
    expect(b.last('PUT', '/api/v1/me/settings').body!['themeMode'], 'dark');

    await tapAndSettle(tester, find.text('周日'));
    expect(b.last('PUT', '/api/v1/me/settings').body!['weekStart'], 7);

    await tapAndSettle(tester, find.byKey(const Key('reminder-15')));
    expect(b.last('PUT', '/api/v1/me/settings').body!['defaultReminders'], [
      0,
      15,
    ]);

    final slider = find.byKey(const Key('font-scale'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(200, 0));
    await settleApp(tester);
    expect(
      (b.last('PUT', '/api/v1/me/settings').body!['fontScale'] as num) > 1.0,
      isTrue,
    );
  });

  testWidgets('设置：离线修改提示已保存在本机', (tester) async {
    final b = await pumpApp(tester);
    await _open(tester, '/settings');
    b.offline = true;
    await tapAndSettle(tester, find.text('浅色'));
    expect(find.text('已保存在本机，联网登录后自动同步'), findsOneWidget);
  });

  testWidgets('关于页面：版本、字体说明与政策', (tester) async {
    await pumpApp(tester);
    await _open(tester, '/settings');
    await tapAndSettle(tester, find.text('关于即刻日志'));
    expect(find.textContaining('MiSans'), findsOneWidget);
    expect(find.textContaining('版本'), findsOneWidget);
    await tapAndSettle(tester, find.text('隐私政策'));
    expect(find.textContaining('我们收集的信息'), findsOneWidget);
    await tester.pageBack();
    await settleApp(tester);
    await tapAndSettle(tester, find.text('开源许可'));
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('帐号：修改昵称', (tester) async {
    final b = await pumpApp(tester);
    b.on(
      'PATCH',
      '/api/v1/me',
      (req) =>
          FakeResponse.ok(userJson(nickname: req.body!['nickname'] as String)),
    );
    await _open(tester, '/account');
    expect(find.text('@zhangsan'), findsOneWidget);
    await tapAndSettle(tester, find.text('昵称'));
    await tester.enterText(find.byKey(const Key('nickname-input')), '小张');
    await tapAndSettle(tester, find.text('保存'));
    expect(find.text('昵称已更新'), findsOneWidget);
    expect(find.text('小张'), findsWidgets);
  });

  testWidgets('帐号：退出登录需确认', (tester) async {
    final b = await pumpApp(tester);
    await _open(tester, '/account');
    await tapAndSettle(tester, find.byKey(const Key('account-logout')));
    await tapAndSettle(tester, find.text('取消'));
    expect(find.byType(LoginPage), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('account-logout')));
    await tapAndSettle(tester, find.text('退出'));
    expect(find.byType(LoginPage), findsOneWidget);
    expectRequestCount(b, 'POST', '/api/v1/auth/logout', 1);
  });

  testWidgets('登录设备：加载、下线其他设备、加载失败重试', (tester) async {
    final b = await pumpApp(tester);
    var devices = [_device('d-self', current: true), _device('d-other')];
    var fail = true;
    b
      ..on(
        'GET',
        '/api/v1/me/devices',
        (_) => fail
            ? FakeResponse.error(503, 'SERVICE_UNAVAILABLE', message: '服务暂时不可用')
            : FakeResponse.ok(devices),
      )
      ..on('DELETE', '/api/v1/me/devices/d-other', (_) {
        devices = [devices.first];
        return FakeResponse.ok({'ok': true});
      });
    await _open(tester, '/account');
    await tapAndSettle(tester, find.byKey(const Key('account-devices')));
    expect(find.text('加载失败'), findsOneWidget);

    fail = false;
    await tapAndSettle(tester, find.text('重试'));
    expect(find.text('本机'), findsOneWidget);
    expect(find.text('Xiaomi 14'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('revoke-d-other')));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '下线'));
    expect(find.text('设备已下线'), findsOneWidget);
    expect(find.text('Xiaomi 14'), findsNothing);
  });

  testWidgets('绑定手机号', (tester) async {
    final b = await pumpApp(tester);
    b.on(
      'PUT',
      '/api/v1/me/phone',
      (_) => FakeResponse.ok(userJson(phoneMasked: '139****0000')),
    );
    await _open(tester, '/account');
    await tapAndSettle(tester, find.byKey(const Key('account-phone')));
    expect(find.text('绑定手机号'), findsWidgets);

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'secret123');
    await tester.enterText(fields.at(1), '13900000000');
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(b.last('POST', '/api/v1/me/sms/send').body, {
      'purpose': 'bind_phone',
      'phone': '13900000000',
    });
    await tester.enterText(fields.at(2), '123456');
    await tapAndSettle(tester, find.text('确认绑定'));
    expect(b.last('PUT', '/api/v1/me/phone').body, {
      'phone': '13900000000',
      'code': '123456',
      'currentPassword': 'secret123',
    });
    expect(find.text('139****0000'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('换绑手机号需要当前号码验证码', (tester) async {
    final b = await pumpApp(tester, user: userJson(phoneMasked: '138****8000'));
    b.on(
      'PUT',
      '/api/v1/me/phone',
      (_) => FakeResponse.ok(userJson(phoneMasked: '139****0000')),
    );
    await _open(tester, '/account');
    await tapAndSettle(tester, find.byKey(const Key('account-phone')));
    expect(find.text('换绑手机号'), findsWidgets);
    final fields = find.byType(EditableText);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'secret123');
    await tester.enterText(fields.at(1), '111111');
    await tester.enterText(fields.at(2), '13900000000');
    await tester.enterText(fields.at(3), '222222');
    await tapAndSettle(tester, find.text('确认换绑'));
    expect(b.last('PUT', '/api/v1/me/phone').body!['currentCode'], '111111');
    expect(find.text('手机号已换绑'), findsOneWidget);
  });

  testWidgets('修改密码：当前密码或手机验证码', (tester) async {
    final b = await pumpApp(tester, user: userJson(phoneMasked: '138****8000'));
    b.on(
      'PUT',
      '/api/v1/me/password',
      (_) => FakeResponse.error(400, 'INVALID_CREDENTIALS', message: '当前密码错误'),
    );
    await _open(tester, '/account');
    await tapAndSettle(tester, find.text('修改密码'));
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'wrong');
    await tester.enterText(fields.at(1), 'newsecret1');
    await tapAndSettle(tester, find.text('确认修改'));
    expect(find.text('当前密码错误'), findsOneWidget);

    b.on('PUT', '/api/v1/me/password', (_) => FakeResponse.ok({'ok': true}));
    await tapAndSettle(tester, find.text('手机验证码'));
    await tapAndSettle(tester, find.text('获取验证码'));
    expect(b.last('POST', '/api/v1/me/sms/send').body, {
      'purpose': 'verify_current',
    });
    await tester.enterText(find.byType(EditableText).at(0), '123456');
    await tapAndSettle(tester, find.text('确认修改'));
    expect(b.last('PUT', '/api/v1/me/password').body, {
      'newPassword': 'newsecret1',
      'smsCode': '123456',
    });
    expect(find.text('密码已修改，其他设备需重新登录'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('注销账号：二次确认后回到登录页', (tester) async {
    final b = await pumpApp(tester);
    b.on('POST', '/api/v1/me/deletion', (_) => FakeResponse.ok({'ok': true}));
    await _open(tester, '/account');
    await tapAndSettle(tester, find.text('注销账号'));
    await tapAndSettle(tester, find.byKey(const Key('delete-submit')));
    expect(find.text('请输入当前密码'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'secret123');
    await tapAndSettle(tester, find.byKey(const Key('delete-submit')));
    expect(find.text('确认注销账号？'), findsOneWidget);
    await tapAndSettle(tester, find.text('永久注销'));
    expect(b.last('POST', '/api/v1/me/deletion').body, {
      'currentPassword': 'secret123',
    });
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('账号已注销'), findsOneWidget);
  });
}
