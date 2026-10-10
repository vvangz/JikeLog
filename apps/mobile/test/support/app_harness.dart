import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/config.dart';
import 'package:jikelog/app/app.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/storage/stores.dart';

import 'fake_backend.dart';
import 'fake_sync_server.dart';

/// 常用的假后端：登录、设置、账号信息均可用。
FakeBackend standardBackend({Map<String, dynamic>? user}) => FakeBackend()
  ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(user ?? userJson()))
  ..on(
    'POST',
    '/api/v1/auth/login/password',
    (_) => FakeResponse.ok(sessionJson(user: user)),
  )
  ..on('POST', '/api/v1/auth/logout', (_) => FakeResponse.ok({'ok': true}))
  ..on(
    'GET',
    '/api/v1/me/settings',
    (_) => FakeResponse.ok(const UserSettings().toJson()),
  )
  ..on('PUT', '/api/v1/me/settings', (req) => FakeResponse.ok(req.body))
  ..on(
    'POST',
    '/api/v1/auth/sms/send',
    (_) => FakeResponse.ok({'cooldownSeconds': 60, 'expiresInSeconds': 300}),
  )
  ..on(
    'POST',
    '/api/v1/me/sms/send',
    (_) => FakeResponse.ok({'cooldownSeconds': 60, 'expiresInSeconds': 300}),
  );

/// 启动完整应用。[signedIn] 为 true 时预置令牌与缓存的账号信息；[consented] 控制是否已同意隐私政策。
Future<FakeBackend> pumpApp(
  WidgetTester tester, {
  FakeBackend? backend,
  bool signedIn = true,
  bool consented = true,
  double width = 400,
  double height = 900,
  double textScale = 1,
  Map<String, dynamic>? user,
  FakeSyncServer? syncServer,
}) async {
  final b = backend ?? standardBackend(user: user);
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryStore({
    if (consented) 'consent.version': '${AppConfig.privacyPolicyVersion}',
    if (signedIn) 'auth.user': jsonEncode(user ?? userJson()),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: testOverrides(
        backend: b,
        store: store,
        tokens: MemoryTokenStore(signedIn ? testTokens : null),
        syncServer: syncServer,
      ),
      child: const JikeLogApp(),
    ),
  );
  await settleApp(tester);
  return b;
}

/// 让异步请求完成并结束动画。
Future<void> settleApp(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> enter(WidgetTester tester, Key key, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    text,
  );
}

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await settleApp(tester);
}
