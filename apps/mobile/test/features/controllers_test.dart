import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/router.dart';
import 'package:jikelog/core/api/api_exception.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/features/auth/auth_controller.dart';
import 'package:jikelog/features/consent/consent_controller.dart';
import 'package:jikelog/features/settings/settings_controller.dart';

import '../support/fake_backend.dart';

/// 等待登录态恢复完成。
Future<AuthState> _restored(ProviderContainer c) async {
  c.read(authControllerProvider);
  await eventually(
    () => c.read(authControllerProvider) is! AuthLoading,
    reason: '登录态恢复',
  );
  return c.read(authControllerProvider);
}

ProviderContainer _container(
  FakeBackend b, {
  KeyValueStore? store,
  TokenStore? tokens,
  bool consented = true,
}) {
  final kv = store ?? MemoryStore();
  if (consented) unawaited(kv.setString('consent.version', '1'));
  final c = ProviderContainer(
    overrides: testOverrides(backend: b, store: kv, tokens: tokens),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('AuthController 恢复登录态', () {
    test('没有令牌 → 未登录', () async {
      final c = _container(FakeBackend());
      expect(c.read(authControllerProvider), isA<AuthLoading>());
      expect(await _restored(c), isA<SignedOut>());
    });

    test('有令牌 → 拉取账号信息并缓存', () async {
      final b = FakeBackend()
        ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(userJson()));
      final store = MemoryStore();
      final c = _container(
        b,
        store: store,
        tokens: MemoryTokenStore(testTokens),
      );
      await _restored(c);
      expect(c.read(authControllerProvider), isA<SignedIn>());
      expect(store.getString('auth.user'), contains('zhangsan'));
    });

    test('离线时使用缓存的账号信息进入应用', () async {
      final b = FakeBackend()..offline = true;
      final store = MemoryStore({
        'auth.user': jsonEncode(userJson(nickname: '缓存')),
      });
      final c = _container(
        b,
        store: store,
        tokens: MemoryTokenStore(testTokens),
      );
      await _restored(c);
      final s = c.read(authControllerProvider);
      expect(
        s,
        isA<SignedIn>().having((s) => s.user.nickname, 'nickname', '缓存'),
      );
    });

    test('离线且无缓存 → 未登录；服务端拒绝 → 未登录并清除令牌', () async {
      final offline = FakeBackend()..offline = true;
      final c1 = _container(offline, tokens: MemoryTokenStore(testTokens));
      await _restored(c1);
      expect(c1.read(authControllerProvider), isA<SignedOut>());

      final tokens = MemoryTokenStore(testTokens);
      final rejected = FakeBackend()
        ..on(
          'GET',
          '/api/v1/me',
          (_) => FakeResponse.error(401, ApiErrorCode.unauthorized),
        )
        ..on(
          'POST',
          '/api/v1/auth/refresh',
          (_) => FakeResponse.error(401, ApiErrorCode.refreshInvalid),
        );
      final c2 = _container(rejected, tokens: tokens);
      await _restored(c2);
      expect(c2.read(authControllerProvider), isA<SignedOut>());
      expect(await tokens.read(), isNull);
    });

    test('服务端 5xx 但有缓存 → 保持登录', () async {
      final b = FakeBackend()
        ..on(
          'GET',
          '/api/v1/me',
          (_) => FakeResponse.error(503, 'SERVICE_UNAVAILABLE'),
        );
      final store = MemoryStore({'auth.user': jsonEncode(userJson())});
      final c = _container(
        b,
        store: store,
        tokens: MemoryTokenStore(testTokens),
      );
      await _restored(c);
      expect(c.read(authControllerProvider), isA<SignedIn>());
    });

    test('缓存损坏时忽略', () async {
      final b = FakeBackend()..offline = true;
      final c = _container(
        b,
        store: MemoryStore({'auth.user': '{bad'}),
        tokens: MemoryTokenStore(testTokens),
      );
      await _restored(c);
      expect(c.read(authControllerProvider), isA<SignedOut>());
    });
  });

  group('AuthController 登录与退出', () {
    late FakeBackend b;
    late MemoryTokenStore tokens;
    late ProviderContainer c;

    setUp(() async {
      b = FakeBackend()
        ..on(
          'POST',
          '/api/v1/auth/login/password',
          (_) => FakeResponse.ok(sessionJson()),
        )
        ..on(
          'POST',
          '/api/v1/auth/register',
          (_) => FakeResponse.ok(sessionJson(), status: 201),
        )
        ..on(
          'POST',
          '/api/v1/auth/register/sms',
          (_) => FakeResponse.ok(sessionJson(), status: 201),
        )
        ..on(
          'POST',
          '/api/v1/auth/logout',
          (_) => FakeResponse.ok({'ok': true}),
        )
        ..on(
          'GET',
          '/api/v1/me/settings',
          (_) => FakeResponse.ok(const UserSettings().toJson()),
        );
      tokens = MemoryTokenStore();
      c = _container(b, tokens: tokens);
      await _restored(c);
    });

    test('密码登录保存令牌并进入已登录', () async {
      await c
          .read(authControllerProvider.notifier)
          .loginWithPassword('zhangsan', 'secret123');
      expect(c.read(authControllerProvider), isA<SignedIn>());
      expect((await tokens.read())!.accessToken, 'access-1');
      expect(
        b.last('POST', '/api/v1/auth/login/password').body!['device'],
        testDevice.toJson(),
      );
    });

    test('注册与完善注册', () async {
      await c
          .read(authControllerProvider.notifier)
          .register(username: 'zhangsan', password: 'secret123');
      expect(c.read(authControllerProvider), isA<SignedIn>());
      await c
          .read(authControllerProvider.notifier)
          .completeSmsRegistration(
            ticket: 't',
            username: 'zhangsan',
            password: 'secret123',
          );
      expect(
        b.last('POST', '/api/v1/auth/register/sms').body!['registrationTicket'],
        't',
      );
    });

    test('短信登录：新号码返回注册凭证，已注册直接登录', () async {
      b.on(
        'POST',
        '/api/v1/auth/login/sms',
        (_) => FakeResponse.ok({
          'status': 'registration_required',
          'registrationTicket': 't1',
          'phoneMasked': '138****8000',
        }),
      );
      final pending = await c
          .read(authControllerProvider.notifier)
          .loginWithSms('13800138000', '123456');
      expect(pending!.ticket, 't1');
      expect(c.read(authControllerProvider), isA<SignedOut>());

      b.on(
        'POST',
        '/api/v1/auth/login/sms',
        (_) => FakeResponse.ok({
          'status': 'authenticated',
          'session': sessionJson(),
        }),
      );
      expect(
        await c
            .read(authControllerProvider.notifier)
            .loginWithSms('13800138000', '123456'),
        isNull,
      );
      expect(c.read(authControllerProvider), isA<SignedIn>());
    });

    test('退出登录：网络失败也清除本地登录态', () async {
      await c
          .read(authControllerProvider.notifier)
          .loginWithPassword('zhangsan', 'secret123');
      b.offline = true;
      await c.read(authControllerProvider.notifier).logout();
      expect(c.read(authControllerProvider), isA<SignedOut>());
      expect(await tokens.read(), isNull);
    });

    test('会话失效回调带原因回到登录页', () async {
      await c
          .read(authControllerProvider.notifier)
          .loginWithPassword('zhangsan', 'secret123');
      await c
          .read(authControllerProvider.notifier)
          .signOutLocally(reason: '账号已注销');
      expect(
        c.read(authControllerProvider),
        isA<SignedOut>().having((s) => s.reason, 'reason', '账号已注销'),
      );
    });
  });

  group('SettingsController', () {
    test('未登录时只保存在本机并标记待同步，登录后上传', () async {
      final store = MemoryStore();
      final b = FakeBackend()
        ..on(
          'POST',
          '/api/v1/auth/login/password',
          (_) => FakeResponse.ok(sessionJson()),
        )
        ..on('PUT', '/api/v1/me/settings', (req) => FakeResponse.ok(req.body));
      final c = _container(b, store: store);
      await _restored(c);
      final ctrl = c.read(settingsControllerProvider.notifier);
      expect(await ctrl.update(const UserSettings(themeMode: 'dark')), isFalse);
      expect(
        await ctrl.update(const UserSettings(themeMode: 'dark')),
        isTrue,
      ); // 未变化
      expect(store.getString('settings.dirty'), '1');
      expect(themeModeOf(c.read(settingsControllerProvider)), ThemeMode.dark);

      await c.read(authControllerProvider.notifier).loginWithPassword('u', 'p');
      await eventually(
        () =>
            b.count('PUT', '/api/v1/me/settings') > 0 &&
            store.getString('settings.dirty') == null,
      );
      expect(b.last('PUT', '/api/v1/me/settings').body!['themeMode'], 'dark');
      expect(store.getString('settings.dirty'), isNull);
    });

    test('无本地修改时以服务端为准；同步失败保持本地值', () async {
      final b = FakeBackend()
        ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(userJson()))
        ..on(
          'GET',
          '/api/v1/me/settings',
          (_) => FakeResponse.ok(
            const UserSettings(themeMode: 'light', weekStart: 7).toJson(),
          ),
        );
      final c = _container(b, tokens: MemoryTokenStore(testTokens));
      c.read(settingsControllerProvider);
      await _restored(c);
      await eventually(() => c.read(settingsControllerProvider).weekStart == 7);
      expect(themeModeOf(c.read(settingsControllerProvider)), ThemeMode.light);

      b.offline = true;
      final ok = await c
          .read(settingsControllerProvider.notifier)
          .update(const UserSettings(fontScale: 1.2));
      expect(ok, isFalse);
      expect(c.read(settingsControllerProvider).fontScale, 1.2);
    });

    test('本地设置损坏时使用默认值', () {
      final c = _container(
        FakeBackend(),
        store: MemoryStore({'settings.local': 'oops'}),
      );
      expect(c.read(settingsControllerProvider), const UserSettings());
      expect(themeModeOf(const UserSettings()), ThemeMode.system);
    });
  });

  test('ConsentController 记录同意的政策版本', () async {
    final store = MemoryStore();
    final c = _container(FakeBackend(), store: store, consented: false);
    expect(c.read(consentControllerProvider), isFalse);
    await c.read(consentControllerProvider.notifier).accept();
    expect(c.read(consentControllerProvider), isTrue);
    expect(
      _container(FakeBackend(), store: store).read(consentControllerProvider),
      isTrue,
    );
  });

  test('同意隐私政策前不恢复登录态、不发请求；同意后才恢复', () async {
    final b = FakeBackend()
      ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(userJson()));
    final c = _container(
      b,
      tokens: MemoryTokenStore(testTokens),
      consented: false,
    );
    c.read(authControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(authControllerProvider), isA<AuthLoading>());
    expect(b.requests, isEmpty);
    await c.read(consentControllerProvider.notifier).accept();
    await eventually(() => c.read(authControllerProvider) is SignedIn);
  });

  test('读取令牌抛出平台异常时按未登录处理，不会卡在启动页', () async {
    final c = _container(FakeBackend(), tokens: _ThrowingTokenStore());
    expect(await _restored(c), isA<SignedOut>());
  });

  test('账号信息响应格式异常时使用缓存', () async {
    final b = FakeBackend()
      ..on('GET', '/api/v1/me', (_) => FakeResponse.ok({'weird': true}));
    final store = MemoryStore({
      'auth.user': jsonEncode(userJson(nickname: '缓存')),
    });
    final c = _container(b, store: store, tokens: MemoryTokenStore(testTokens));
    expect(await _restored(c), isA<SignedIn>());
  });

  test('退出登录清除未同步设置标记，避免上传到下一个账号', () async {
    final store = MemoryStore({'settings.dirty': '1'});
    final b = FakeBackend()
      ..on('POST', '/api/v1/auth/logout', (_) => FakeResponse.ok({'ok': true}));
    final c = _container(b, store: store, tokens: MemoryTokenStore(testTokens));
    b.on('GET', '/api/v1/me', (_) => FakeResponse.ok(userJson()));
    b.on('PUT', '/api/v1/me/settings', (req) => FakeResponse.ok(req.body));
    await _restored(c);
    await c.read(authControllerProvider.notifier).logout();
    expect(store.getString('settings.dirty'), isNull);
  });

  test('设置连续修改：较早的同步结果不会覆盖较新的本地值', () async {
    final gate = Completer<void>();
    var puts = 0;
    final b = FakeBackend()
      ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(userJson()))
      ..on(
        'GET',
        '/api/v1/me/settings',
        (_) => FakeResponse.ok(const UserSettings().toJson()),
      )
      ..on('PUT', '/api/v1/me/settings', (req) async {
        if (puts++ == 0) await gate.future;
        return FakeResponse.ok(req.body);
      });
    final c = _container(b, tokens: MemoryTokenStore(testTokens));
    c.read(settingsControllerProvider);
    await _restored(c);
    await eventually(() => b.count('GET', '/api/v1/me/settings') > 0);
    final ctrl = c.read(settingsControllerProvider.notifier);
    final first = ctrl.update(const UserSettings(themeMode: 'light'));
    await eventually(() => b.count('PUT', '/api/v1/me/settings') == 1);
    final second = ctrl.update(const UserSettings(themeMode: 'dark'));
    gate.complete();
    await Future.wait([first, second]);
    expect(c.read(settingsControllerProvider).themeMode, 'dark');
    expect(b.last('PUT', '/api/v1/me/settings').body!['themeMode'], 'dark');
  });

  group('路由守卫', () {
    final user = User.fromJson(userJson());
    String? go(
      String loc, {
      bool consented = true,
      AuthState auth = const SignedOut(),
    }) => redirectFor(consented: consented, auth: auth, location: loc);

    test('未同意隐私政策一律进入同意页', () {
      expect(go('/worklog', consented: false), '/consent');
      expect(go('/consent', consented: false), isNull);
    });

    test('恢复登录态期间显示启动页', () {
      expect(go('/worklog', auth: const AuthLoading()), '/splash');
      expect(go('/splash', auth: const AuthLoading()), isNull);
    });

    test('未登录只能访问登录类页面', () {
      expect(go('/worklog'), '/login');
      expect(go('/account/devices'), '/login');
      for (final p in [
        '/login',
        '/register',
        '/register/complete',
        '/password/reset',
      ]) {
        expect(go(p), isNull, reason: p);
      }
    });

    test('已登录访问登录类页面回到首页', () {
      final signedIn = SignedIn(user);
      expect(go('/login', auth: signedIn), homePath);
      expect(go('/splash', auth: signedIn), homePath);
      expect(go('/consent', auth: signedIn), homePath);
      expect(go('/notes', auth: signedIn), isNull);
    });
  });
}

class _ThrowingTokenStore implements TokenStore {
  @override
  Future<TokenPair?> read() => Future.error(Exception('Keystore 不可用'));

  @override
  Future<void> write(TokenPair tokens) async {}

  @override
  Future<void> clear() async {}
}
