import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/platform/platform_features.dart';
import 'package:jikelog/features/update/update_installer.dart';
import 'package:jikelog/features/update/update_models.dart';
import 'package:jikelog/features/update/update_service.dart';
import 'package:path/path.dart' as p;

import '../../support/app_harness.dart';
import '../../support/fake_backend.dart';

/// 内存 HTTP 适配器，支持返回 JSON 清单和二进制安装包流。
class _UpdateHttpAdapter implements HttpClientAdapter {
  _UpdateHttpAdapter({
    this.manifestJson,
    this.packageBytes,
    this.manifestStatus = 200,
  });

  final Map<String, dynamic>? manifestJson;
  final Uint8List? packageBytes;
  final int manifestStatus;
  int manifestRequests = 0;
  int packageRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/download/latest.json')) {
      manifestRequests++;
      if (manifestStatus != 200 || manifestJson == null) {
        return ResponseBody.fromString('error', manifestStatus);
      }
      return ResponseBody.fromString(
        jsonEncode(manifestJson),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path.contains('/download/')) {
      packageRequests++;
      if (packageBytes == null) {
        return ResponseBody.fromString('not found', 404);
      }
      return ResponseBody.fromBytes(
        packageBytes!,
        200,
        headers: {
          Headers.contentLengthHeader: ['${packageBytes!.length}'],
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      );
    }
    return ResponseBody.fromString('not found', 404);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _manifest({
  required String version,
  required String apkHash,
  required int apkSize,
  required String msixHash,
  required int msixSize,
}) => {
  'version': version,
  'publishedAt': '2026-11-24T02:00:00.000Z',
  'releaseUrl': 'https://github.com/vvangz/JikeLog/releases/tag/v$version',
  'files': {
    'android': {
      'name': 'jikelog-$version.apk',
      'size': apkSize,
      'sha256': apkHash,
    },
    'windows': {
      'name': 'jikelog-$version.msix',
      'size': msixSize,
      'sha256': msixHash,
    },
  },
};

Future<void> _waitForFinder(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  tearDown(TestHooks.reset);

  group('update_models', () {
    test('compareSemVer 与 isNewerVersion 正确比较版本号', () {
      expect(isNewerVersion('1.7.0', '1.6.0'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(isNewerVersion('1.7.0', '1.7.0-rc.1'), isTrue);
      expect(isNewerVersion('1.7.0-rc.2', '1.7.0-rc.1'), isTrue);
      expect(isNewerVersion('1.6.0', '1.6.0'), isFalse);
      expect(isNewerVersion('1.5.9', '1.6.0'), isFalse);
      expect(isNewerVersion('1.7.0-rc.1', '1.7.0'), isFalse);
    });

    test('UpdateManifest.tryParse 校验字段并拒绝危险文件名与非法哈希', () {
      final hash = 'a' * 64;
      final ok = UpdateManifest.tryParse(
        _manifest(
          version: '1.7.0',
          apkHash: hash.toUpperCase(),
          apkSize: 1024,
          msixHash: hash,
          msixSize: 2048,
        ),
      );
      expect(ok, isNotNull);
      expect(ok!.version, '1.7.0');
      expect(ok.android!.sha256, hash);
      expect(ok.windows!.name, 'jikelog-1.7.0.msix');

      // 拒绝路径穿越与非法后缀
      expect(
        UpdateManifest.tryParse({
          'version': '1.7.0',
          'files': {
            'android': {'name': '../evil.apk', 'size': 1024, 'sha256': hash},
          },
        }),
        isNull,
      );
      expect(
        UpdateManifest.tryParse({
          'version': '1.7.0',
          'files': {
            'windows': {'name': 'jikelog.exe', 'size': 1024, 'sha256': hash},
          },
        }),
        isNull,
      );
      // 拒绝非法版本号与过短哈希
      expect(
        UpdateManifest.tryParse({
          'version': 'not-a-version',
          'files': {
            'android': {'name': 'a.apk', 'size': 10, 'sha256': hash},
          },
        }),
        isNull,
      );
      expect(
        UpdateManifest.tryParse({
          'version': '1.7.0',
          'files': {
            'android': {'name': 'a.apk', 'size': 10, 'sha256': '1234'},
          },
        }),
        isNull,
      );
    });

    test('formatByteSize 按 B / KB / MB 格式化', () {
      expect(formatByteSize(0), '0 B');
      expect(formatByteSize(512), '512 B');
      expect(formatByteSize(2048), '2 KB');
      expect(formatByteSize(89041932), '84.9 MB');
    });
  });

  group('update_installer', () {
    test('installAndroidApk 正确映射原生通道返回结果', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('jikelog/test-updater');
      String? nextReturn;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'installApk');
            if (nextReturn == 'throw') {
              throw PlatformException(code: 'ERR');
            }
            return nextReturn;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final fake = File('jikelog-1.7.0.apk');
      nextReturn = 'launched';
      expect(
        await installAndroidApk(fake, channel: channel),
        InstallOutcome.launched,
      );
      nextReturn = 'permission_required';
      expect(
        await installAndroidApk(fake, channel: channel),
        InstallOutcome.permissionRequired,
      );
      nextReturn = 'failed';
      expect(
        await installAndroidApk(fake, channel: channel),
        InstallOutcome.failed,
      );
      nextReturn = 'throw';
      expect(
        await installAndroidApk(fake, channel: channel),
        InstallOutcome.failed,
      );
    });

    test('installWindowsMsix 通过系统关联打开 MSIX 文件', () async {
      Uri? opened;
      final fake = File('jikelog-1.7.0.msix');
      expect(
        await installWindowsMsix(
          fake,
          launch: (uri) async {
            opened = uri;
            return true;
          },
        ),
        InstallOutcome.launched,
      );
      expect(opened?.path, endsWith('jikelog-1.7.0.msix'));

      expect(
        await installWindowsMsix(fake, launch: (_) async => false),
        InstallOutcome.failed,
      );
    });
  });

  group('AppUpdateService', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('jk-update-test-');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('下载、校验 SHA-256、复用缓存并清理旧版本安装包', () async {
      final bytes = Uint8List.fromList(utf8.encode('fake-apk-binary-v1.7.0'));
      final hash = sha256.convert(bytes).toString();
      final stale = File(p.join(tmp.path, 'jikelog-1.5.0.apk'))
        ..writeAsStringSync('old');

      final adapter = _UpdateHttpAdapter(
        manifestJson: _manifest(
          version: '1.7.0',
          apkHash: hash,
          apkSize: bytes.length,
          msixHash: hash,
          msixSize: bytes.length,
        ),
        packageBytes: bytes,
      );
      final service = AppUpdateService(
        baseUrl: 'https://www.pingvv.top/',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: false,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (_) async => InstallOutcome.launched,
      );

      final candidate = await service.checkForUpdate();
      expect(candidate, isNotNull);
      expect(candidate!.version, '1.7.0');
      expect(
        candidate.downloadUrl,
        'https://www.pingvv.top/download/jikelog-1.7.0.apk',
      );

      var lastReceived = 0;
      final file = await service.downloadAndVerify(
        candidate,
        onProgress: (r, _) => lastReceived = r,
      );
      expect(await file.exists(), isTrue);
      expect(lastReceived, bytes.length);
      expect(stale.existsSync(), isFalse);
      expect(adapter.packageRequests, 1);

      // 二次调用复用已校验缓存，不重新下载
      final cached = await service.downloadAndVerify(candidate);
      expect(cached.path, file.path);
      expect(adapter.packageRequests, 1);
    });

    test('SHA-256 校验失败时删除损坏文件并抛异常', () async {
      final bytes = Uint8List.fromList(utf8.encode('corrupted-bytes'));
      final wrongHash = '0' * 64;
      final adapter = _UpdateHttpAdapter(
        manifestJson: _manifest(
          version: '1.7.0',
          apkHash: wrongHash,
          apkSize: bytes.length,
          msixHash: wrongHash,
          msixSize: bytes.length,
        ),
        packageBytes: bytes,
      );
      final service = AppUpdateService(
        baseUrl: 'https://www.pingvv.top',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: false,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (_) async => InstallOutcome.launched,
      );

      final candidate = (await service.checkForUpdate())!;
      await expectLater(
        service.downloadAndVerify(candidate),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('校验未通过'),
          ),
        ),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('当前已是最新版本时返回 null', () async {
      final hash = 'b' * 64;
      final adapter = _UpdateHttpAdapter(
        manifestJson: _manifest(
          version: '1.6.0',
          apkHash: hash,
          apkSize: 100,
          msixHash: hash,
          msixSize: 100,
        ),
      );
      final service = AppUpdateService(
        baseUrl: 'https://www.pingvv.top',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: true,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (_) async => InstallOutcome.launched,
      );
      expect(await service.checkForUpdate(), isNull);
    });
  });

  group('应用内更新界面流程', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('jk-update-ui-');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('概览页静默发现新版本显示横幅，支持忽略与更新', (tester) async {
      final bytes = Uint8List.fromList(utf8.encode('apk-9.9.9'));
      final hash = sha256.convert(bytes).toString();
      final adapter = _UpdateHttpAdapter(
        manifestJson: _manifest(
          version: '9.9.9',
          apkHash: hash,
          apkSize: bytes.length,
          msixHash: hash,
          msixSize: bytes.length,
        ),
        packageBytes: bytes,
      );
      TestHooks.updateService = AppUpdateService(
        baseUrl: 'https://www.pingvv.top',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: false,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (f) async => TestHooks.installUpdate(f),
      );

      await pumpApp(tester);
      expect(find.byKey(const Key('update-banner')), findsOneWidget);
      expect(find.textContaining('v9.9.9'), findsOneWidget);

      await tapAndSettle(
        tester,
        find.byKey(const Key('update-banner-dismiss')),
      );
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });

    testWidgets('Android 设置页检查更新：需要安装权限后点击继续安装复用已校验 APK', (tester) async {
      final bytes = Uint8List.fromList(utf8.encode('apk-9.9.9-perm'));
      final hash = sha256.convert(bytes).toString();
      final adapter = _UpdateHttpAdapter(
        manifestJson: _manifest(
          version: '9.9.9',
          apkHash: hash,
          apkSize: bytes.length,
          msixHash: hash,
          msixSize: bytes.length,
        ),
        packageBytes: bytes,
      );
      var installCalls = 0;
      TestHooks.installUpdate = (f) {
        installCalls++;
        if (installCalls == 1) return InstallOutcome.permissionRequired;
        TestHooks.installed.add(f.path);
        return InstallOutcome.launched;
      };
      TestHooks.updateService = AppUpdateService(
        baseUrl: 'https://www.pingvv.top',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: false,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (f) async => TestHooks.installUpdate(f),
      );

      await pumpApp(tester, height: 1200, path: '/settings');
      await tapAndSettle(
        tester,
        find.byKey(const Key('settings-check-update')),
      );
      expect(find.byKey(const Key('update-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('update-start')));
      await _waitForFinder(tester, find.textContaining('允许来自此来源的应用'));
      expect(find.textContaining('允许来自此来源的应用'), findsOneWidget);
      expect(adapter.packageRequests, 1);

      await tester.tap(find.byKey(const Key('update-continue-install')));
      await _waitForFinder(tester, find.textContaining('已调起系统安装界面'));
      expect(find.textContaining('已调起系统安装界面'), findsOneWidget);
      expect(adapter.packageRequests, 1); // 未重复下载
      expect(TestHooks.installed.single, endsWith('jikelog-9.9.9.apk'));
    });

    testWidgets('Windows 关于页检查更新：下载校验 MSIX 并调起应用安装程序', (tester) async {
      final bytes = Uint8List.fromList(utf8.encode('msix-9.9.9'));
      final hash = sha256.convert(bytes).toString();
      final adapter = _UpdateHttpAdapter(
        manifestJson: _manifest(
          version: '9.9.9',
          apkHash: hash,
          apkSize: bytes.length,
          msixHash: hash,
          msixSize: bytes.length,
        ),
        packageBytes: bytes,
      );
      TestHooks.updateService = AppUpdateService(
        baseUrl: 'https://www.pingvv.top',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: true,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (f) async => TestHooks.installUpdate(f),
      );

      await pumpApp(
        tester,
        features: PlatformFeatures.windows,
        width: 1280,
        height: 800,
        path: '/settings/about',
      );
      await tapAndSettle(tester, find.byKey(const Key('about-check-update')));
      expect(find.byKey(const Key('update-dialog')), findsOneWidget);
      expect(find.textContaining('jikelog-9.9.9.msix'), findsOneWidget);

      await tester.tap(find.byKey(const Key('update-start')));
      await _waitForFinder(tester, find.textContaining('已打开 Windows 应用安装程序'));
      expect(find.textContaining('已打开 Windows 应用安装程序'), findsOneWidget);
      expect(TestHooks.installed.single, endsWith('jikelog-9.9.9.msix'));
    });

    testWidgets('已是最新版本时点击检查更新弹出提示', (tester) async {
      final hash = 'c' * 64;
      final adapter = _UpdateHttpAdapter(
        manifestJson: _manifest(
          version: '1.6.0',
          apkHash: hash,
          apkSize: 100,
          msixHash: hash,
          msixSize: 100,
        ),
      );
      TestHooks.updateService = AppUpdateService(
        baseUrl: 'https://www.pingvv.top',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: false,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (f) async => TestHooks.installUpdate(f),
      );

      await pumpApp(tester, height: 1200, path: '/settings');
      await tapAndSettle(
        tester,
        find.byKey(const Key('settings-check-update')),
      );
      expect(find.byKey(const Key('update-dialog')), findsNothing);
      expect(find.textContaining('当前已是最新版本'), findsOneWidget);
    });

    testWidgets('检查更新网络失败时弹出错误提示', (tester) async {
      final adapter = _UpdateHttpAdapter(manifestStatus: 500);
      TestHooks.updateService = AppUpdateService(
        baseUrl: 'https://www.pingvv.top',
        dio: Dio()..httpClientAdapter = adapter,
        isDesktop: false,
        currentVersion: '1.6.0',
        updateDir: () async => tmp,
        installPackage: (f) async => TestHooks.installUpdate(f),
      );

      await pumpApp(tester, height: 1200, path: '/settings');
      await tapAndSettle(
        tester,
        find.byKey(const Key('settings-check-update')),
      );
      expect(find.textContaining('检查更新失败'), findsOneWidget);
    });
  });
}
