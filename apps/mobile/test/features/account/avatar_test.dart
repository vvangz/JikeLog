import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/app.dart';
import 'package:jikelog/app/shell/sidebar.dart';
import 'package:jikelog/app/theme/app_theme.dart';
import 'package:jikelog/core/api/api_client.dart';
import 'package:jikelog/core/api/api_exception.dart';
import 'package:jikelog/core/api/endpoints.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/config.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/features/account/avatar_service.dart';
import 'package:jikelog/shared/ui/user_avatar.dart';

import '../../support/fake_backend.dart';

/// 1×1 透明 PNG（标准合法 PNG，可在 Flutter 测试和服务端解码）。
final _tinyPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

/// 第二张合法 1×1 蓝色 PNG（用于区分更换前后的头像）。
final _bluePng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ),
);

void main() {
  tearDown(TestHooks.reset);

  group('sniffAvatarMime', () {
    test('识别 PNG、JPEG、WebP 并拒绝非法魔数', () {
      expect(sniffAvatarMime(_tinyPng), 'image/png');
      expect(
        sniffAvatarMime(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
        'image/jpeg',
      );
      expect(
        sniffAvatarMime(
          Uint8List.fromList(utf8.encode('RIFF\x10\x00\x00\x00WEBP')),
        ),
        'image/webp',
      );
      expect(
        sniffAvatarMime(Uint8List.fromList(utf8.encode('<svg/>'))),
        isNull,
      );
      expect(sniffAvatarMime(Uint8List(2)), isNull);
    });
  });

  group('AvatarService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('jikelog-avatar-test-');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    AvatarService makeService(FakeBackend backend) {
      final client = ApiClient(
        baseUrl: 'http://test',
        tokenStore: MemoryTokenStore(testTokens),
        adapter: backend,
      );
      return AvatarService(
        api: AccountApi(client),
        cacheDir: () async => tempDir,
        prepare: (raw) async {
          final mime = sniffAvatarMime(raw);
          return mime == null ? null : PreparedAvatar(raw, mime);
        },
      );
    }

    test('上传后立刻命中内存与磁盘缓存，离线重启仍可加载，清除后彻底删除', () async {
      final baseUser = userJson();
      final backend = FakeBackend()
        ..on(
          'PUT',
          '/api/v1/me/avatar',
          (_) => FakeResponse.ok({
            ...baseUser,
            'avatarVersion': 'ver0000000000001',
          }),
        )
        ..on('DELETE', '/api/v1/me/avatar', (_) => FakeResponse.ok(baseUser));

      final svc = makeService(backend);
      final updated = await svc.upload(_tinyPng);
      expect(updated.avatarVersion, 'ver0000000000001');
      expectRequestCount(backend, 'PUT', '/api/v1/me/avatar', 1);

      // 内存命中，不触发 GET
      final mem = await svc.load(updated.id, updated.avatarVersion!);
      expect(mem, _tinyPng);
      expectRequestCount(backend, 'GET', '/api/v1/me/avatar', 0);

      // 新建实例并模拟离线：命中磁盘缓存
      backend.offline = true;
      final coldSvc = makeService(backend);
      final fromDisk = await coldSvc.load(updated.id, updated.avatarVersion!);
      expect(fromDisk, _tinyPng);
      expectRequestCount(backend, 'GET', '/api/v1/me/avatar', 0);

      // 恢复在线并清除头像：内存与磁盘均清理
      backend.offline = false;
      final cleared = await coldSvc.remove(updated.id);
      expect(cleared.hasAvatar, isFalse);
      expectRequestCount(backend, 'DELETE', '/api/v1/me/avatar', 1);

      // 未注册 GET 路由返回 404 → load 优雅返回 null
      expect(await coldSvc.load(updated.id, 'ver0000000000001'), isNull);
    });

    test('无本地缓存时从接口下载并落盘；拒绝空文件与非法格式', () async {
      final backend = FakeBackend()
        ..on(
          'GET',
          '/api/v1/me/avatar',
          (_) => FakeResponse.bytes(_bluePng, contentType: 'image/png'),
        );
      final svc = makeService(backend);

      final loaded = await svc.load('u-1', 'v-abc');
      expect(loaded, _bluePng);
      expectRequestCount(backend, 'GET', '/api/v1/me/avatar', 1);

      // 再次加载直接走缓存
      expect(await svc.load('u-1', 'v-abc'), _bluePng);
      expectRequestCount(backend, 'GET', '/api/v1/me/avatar', 1);

      await expectLater(
        () => svc.upload(Uint8List(0)),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        () => svc.upload(Uint8List.fromList(utf8.encode('<svg/>'))),
        throwsA(isA<ApiException>()),
      );

      await svc.clearAll(disk: true);
      final dir = Directory(
        '${tempDir.path}${Platform.pathSeparator}jikelog-avatars',
      );
      expect(dir.existsSync(), isFalse);
    });
  });

  group('账号页、概览与侧栏自定义头像集成', () {
    testWidgets('在账号页上传、替换、恢复默认头像并同步展示到概览与侧栏', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final tempDir = Directory.systemTemp.createTempSync('jk-av-ui-');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      Map<String, dynamic> currentUser = userJson();
      Uint8List? storedAvatar;

      final backend = FakeBackend()
        ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(currentUser))
        ..on(
          'GET',
          '/api/v1/me/settings',
          (_) => FakeResponse.ok(const UserSettings().toJson()),
        )
        ..on(
          'GET',
          '/api/v1/system/info',
          (_) => FakeResponse.ok({
            'name': 'jikelog-api',
            'version': '1.8.0',
            'time': '2026-11-24T00:00:00Z',
            'features': {'sms': false, 'push': false},
          }),
        )
        ..on('PUT', '/api/v1/me/avatar', (req) {
          storedAvatar = base64Decode(req.body!['data'] as String);
          final ver = storedAvatar!.length == _tinyPng.length
              ? '1111222233334444'
              : '5555666677778888';
          currentUser = {...currentUser, 'avatarVersion': ver};
          return FakeResponse.ok(currentUser);
        })
        ..on('GET', '/api/v1/me/avatar', (_) {
          if (storedAvatar == null) {
            return FakeResponse.error(404, ApiErrorCode.avatarNotFound);
          }
          return FakeResponse.bytes(storedAvatar!, contentType: 'image/png');
        })
        ..on('DELETE', '/api/v1/me/avatar', (_) {
          storedAvatar = null;
          currentUser = userJson();
          return FakeResponse.ok(currentUser);
        });

      TestHooks.prepareAvatar = (raw) async {
        final mime = sniffAvatarMime(raw);
        return mime == null ? null : PreparedAvatar(raw, mime);
      };
      TestHooks.pickAvatar = () async => _tinyPng;

      final store = MemoryStore();
      await store.setString(
        'consent.version',
        '${AppConfig.privacyPolicyVersion}',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(
            backend: backend,
            store: store,
            tokens: MemoryTokenStore(testTokens),
            filesDir: () async => tempDir,
          ),
          child: const JikeLogApp(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      // 概览主卡应展示用户头像入口
      expect(find.byKey(const Key('overview-hero-avatar')), findsOneWidget);
      // 点击概览头像进入账号页
      await tester.tap(find.byKey(const Key('overview-hero-avatar')));
      await tester.pumpAndSettle();

      expect(find.text('使用默认首字母头像'), findsOneWidget);

      // 首次点击「头像」行直接触发选择并上传
      await tester.tap(find.byKey(const Key('account-avatar-tile')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expectRequestCount(backend, 'PUT', '/api/v1/me/avatar', 1);
      expect(find.text('已设置自定义头像'), findsOneWidget);
      expect(
        find.byKey(const Key('user-avatar-image-1111222233334444')),
        findsWidgets,
      );

      // 再次点击「头像」弹出操作面板，选择「恢复默认头像」
      await tester.tap(find.byKey(const Key('account-avatar-header')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar-action-pick')), findsOneWidget);
      expect(find.byKey(const Key('avatar-action-reset')), findsOneWidget);

      await tester.tap(find.byKey(const Key('avatar-action-reset')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expectRequestCount(backend, 'DELETE', '/api/v1/me/avatar', 1);
      expect(find.text('使用默认首字母头像'), findsOneWidget);
      expect(
        find.byKey(const Key('user-avatar-image-1111222233334444')),
        findsNothing,
      );
    });

    testWidgets('Sidebar 底部展示用户头像组件', (tester) async {
      final user = User.fromJson(userJson());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Sidebar(
                selectedPath: '/',
                onSelect: (_) {},
                expanded: true,
                onToggle: () {},
                onSearch: () {},
                user: user,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(UserAvatar), findsOneWidget);
      expect(find.text('张三 · 已登录'), findsOneWidget);
    });
  });
}
