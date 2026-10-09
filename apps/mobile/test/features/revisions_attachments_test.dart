import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/app.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/core/sync/sync_providers.dart';
import 'package:jikelog/features/attachments/attachment_providers.dart';
import 'package:jikelog/features/attachments/attachment_section.dart';
import 'package:jikelog/features/worklog/worklog_repository.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';
import '../support/fake_sync_server.dart';

/// 交替推进真实时间（文件读写）与虚拟时间，直到 [finder] 出现（或消失）。
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  bool present = true,
}) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty == present) return;
  }
  fail('等待超时：$finder');
}

/// 测试用的已选文件。
final class _TestFile extends PlatformFile {
  _TestFile(this.file);

  final File file;

  @override
  String get name => file.uri.pathSegments.last;

  @override
  Uri get uri => file.uri;

  @override
  XFile get xFile => XFile(file.path);

  @override
  int? lengthSync() => file.lengthSync();

  @override
  Future<int?> length() => file.length();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}

/// 启动应用并新建一条已同步的日志，进入其编辑页。返回日志 ID。
Future<String> _openNewWorklog(WidgetTester tester) async {
  await tapAndSettle(tester, find.byKey(const Key('worklog-create')));
  await tester.enterText(find.byKey(const Key('worklog-content')), '现在的内容');
  await tester.pump(const Duration(seconds: 1));
  await settleApp(tester);
  await tester.pump(const Duration(seconds: 2));
  await settleApp(tester);
  final c = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).last),
  );
  final list = c.read(worklogListProvider).value!;
  return list.single.id;
}

void main() {
  testWidgets('修订历史：查看冲突版本并恢复', (tester) async {
    final server = FakeSyncServer();
    final backend = standardBackend()
      ..on(
        'POST',
        '/api/v1/sync/e2e/session',
        (_) => FakeResponse.ok({
          'sessionId': 's1',
          'expiresAt': '2100-01-01T00:00:00Z',
        }, status: 201),
      );
    await pumpApp(tester, backend: backend, syncServer: server);
    final id = await _openNewWorklog(tester);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).last),
    );
    final api = c.read(syncApiProvider);
    backend
      ..on(
        'GET',
        '/api/v1/records/$id/revisions',
        (_) => FakeResponse.ok([
          {
            'id': 'rev-1',
            'version': 1,
            'reason': 'conflict',
            'createdAt': '2026-10-09T08:00:00Z',
            'deviceModel': 'Xiaomi 14',
          },
        ]),
      )
      ..on('GET', '/api/v1/revisions/rev-1', (_) async {
        final s = await api.session();
        return FakeResponse.ok({
          'id': 'rev-1',
          'recordId': id,
          'entity': 'worklog',
          'version': 1,
          'reason': 'conflict',
          'createdAt': '2026-10-09T08:00:00Z',
          'fields': {
            'date': '2026-10-08',
            'location': await s.sealValue('worklog', id, 'location', '客户现场'),
            'content': await s.sealValue('worklog', id, 'content', '另一台设备上的内容'),
          },
        });
      });

    await tapAndSettle(tester, find.byKey(const Key('worklog-revisions')));
    expect(find.text('冲突中未被采用的版本'), findsOneWidget);
    expect(find.textContaining('Xiaomi 14'), findsOneWidget);

    await tapAndSettle(tester, find.text('冲突中未被采用的版本'));
    expect(find.text('另一台设备上的内容'), findsOneWidget);
    expect(find.text('2026-10-08 · 客户现场'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('revision-restore')));
    await tester.pump(const Duration(seconds: 2));
    await settleApp(tester);
    expect(find.text('已恢复此版本'), findsOneWidget);
    final w = c.read(worklogProvider(id)).value!;
    expect(w.content, '另一台设备上的内容');
    expect(w.location, '客户现场');
  });

  testWidgets('修订历史：加载失败可重试', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    await _openNewWorklog(tester);
    await tapAndSettle(tester, find.byKey(const Key('worklog-revisions')));
    expect(find.text('读取修订历史失败，请检查网络后重试'), findsOneWidget);
  });

  testWidgets('附件区：添加文件，上传失败显示原因并可重试，可删除', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('jk-ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final src = File('${tmp.path}/报告.pdf')..writeAsBytesSync([1, 2, 3]);
    final b = standardBackend()
      ..on(
        'POST',
        '/api/v1/sync/e2e/session',
        (_) => FakeResponse.ok({
          'sessionId': 's1',
          'expiresAt': '2100-01-01T00:00:00Z',
        }, status: 201),
      )
      ..on(
        'POST',
        '/api/v1/attachments',
        (_) => FakeResponse.error(413, 'QUOTA_EXCEEDED', message: '附件空间已用完'),
      );
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(
            backend: b,
            store: MemoryStore({
              'consent.version': '1',
              'auth.user': '{"id":"0192a000-0000-7000-8000-000000000001","username":"zhangsan","nickname":"张三","hasPhone":false,"createdAt":"2026-10-09T08:00:00Z"}',
            }),
            tokens: MemoryTokenStore(testTokens),
            syncServer: FakeSyncServer(),
          ),
          attachmentDirProvider.overrideWithValue(() async => tmp),
          filePickerProvider.overrideWithValue(() async => [_TestFile(src)]),
        ],
        child: const JikeLogApp(),
      ),
    );
    await settleApp(tester);
    await _openNewWorklog(tester);
    expect(find.textContaining('可添加图片、PDF'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('attachment-add')));
    await tester.tap(find.byKey(const Key('attachment-add')));
    await _waitFor(tester, find.text('附件空间已用完'));
    expect(find.text('报告.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    await tester.tap(find.byTooltip('重试'));
    await _waitFor(tester, find.text('附件空间已用完'));
    expect(b.count('POST', '/api/v1/attachments'), 2);

    await tapAndSettle(tester, find.byTooltip('删除附件'));
    await tapAndSettle(tester, find.text('删除').last);
    await _waitFor(tester, find.text('报告.pdf'), present: false);
  });

  test('文件大小格式化', () {
    expect(formatSize(512), '512 B');
    expect(formatSize(2048), '2.0 KB');
    expect(formatSize(3 * 1024 * 1024), '3.0 MB');
  });
}
