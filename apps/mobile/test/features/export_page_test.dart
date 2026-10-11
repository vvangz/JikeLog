import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/router.dart';
import 'package:jikelog/features/export/export_api.dart';
import 'package:jikelog/features/export/export_page.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';

ProviderContainer _c(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

const _id1 = '0192a000-0000-7000-8000-0000000000e1';
const _id2 = '0192a000-0000-7000-8000-0000000000e2';

Map<String, dynamic> _job(
  String id,
  String status, {
  List<String> modules = const ['worklog', 'note', 'memo', 'ledger'],
  bool attachments = false,
  int? size,
  String? error,
  DateTime? expiresAt,
}) => {
  'id': id,
  'modules': modules,
  'attachments': attachments,
  'status': status,
  'createdAt': DateTime(2026, 10, 11, 9, 30).toUtc().toIso8601String(),
  'size': ?size,
  'error': ?error,
  'expiresAt': ?expiresAt?.toUtc().toIso8601String(),
};

/// 后端：导出列表由 [jobs] 决定，发起导出时追加一条排队中的导出。
FakeBackend _backend(List<Map<String, dynamic>> jobs) {
  final b = standardBackend();
  b
    ..on('GET', '/api/v1/exports', (_) => FakeResponse.ok(jobs))
    ..on('POST', '/api/v1/exports', (req) {
      final job = _job(
        _id2,
        'pending',
        modules: (req.body!['modules'] as List).cast<String>(),
        attachments: req.body!['attachments'] as bool,
      );
      jobs.insert(0, job);
      return FakeResponse.ok(job, status: 202);
    })
    ..on(
      'GET',
      '/api/v1/exports/$_id1/download',
      (_) => FakeResponse.ok({
        'url': 'https://oss.example/x.zip',
        'expiresAt': DateTime.now().toUtc().toIso8601String(),
      }),
    )
    ..on('DELETE', '/api/v1/exports/$_id1', (_) {
      jobs.removeWhere((j) => j['id'] == _id1);
      return FakeResponse.ok({'ok': true});
    });
  return b;
}

Future<void> _open(WidgetTester tester) async {
  await tapAndSettle(tester, find.byKey(const Key('nav-/settings')));
  await tapAndSettle(tester, find.byKey(const Key('settings-export')));
  expect(find.byType(ExportPage), findsOneWidget);
}

void main() {
  tearDown(TestHooks.reset);

  testWidgets('选择模块发起导出；进行中时禁用按钮并定时刷新，完成后可下载', (tester) async {
    final jobs = <Map<String, dynamic>>[];
    final b = _backend(jobs);
    await pumpApp(tester, backend: b, width: 1200);
    await _open(tester);
    expect(find.text('还没有导出过'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('export-module-note')));
    await tapAndSettle(tester, find.byKey(const Key('export-module-memo')));
    await tapAndSettle(tester, find.byKey(const Key('export-attachments')));
    await tapAndSettle(tester, find.byKey(const Key('export-start')));
    expect(b.last('POST', '/api/v1/exports').body, {
      'modules': ['worklog', 'ledger'],
      'attachments': true,
    });
    expect(find.text('已开始导出，完成后会通知你'), findsOneWidget);
    expect(find.text('工作日志、记账 · 含附件'), findsOneWidget);
    expect(find.textContaining('排队中'), findsOneWidget);
    expect(find.text('正在导出…'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('export-start')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(start.onPressed, isNull);

    // 服务端生成完成：下次刷新时显示大小与下载按钮
    final listed = b.count('GET', '/api/v1/exports');
    jobs[0] = _job(
      _id2,
      'done',
      modules: const ['worklog', 'ledger'],
      attachments: true,
      size: 3 * 1024 * 1024,
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    await tester.pump(const Duration(seconds: 3));
    await settleApp(tester);
    expect(b.count('GET', '/api/v1/exports'), greaterThan(listed));
    expect(find.textContaining('3.0 MB'), findsOneWidget);
    expect(find.byKey(const Key('export-download-$_id2')), findsOneWidget);

    // 全部结束后不再刷新
    final after = b.count('GET', '/api/v1/exports');
    await tester.pump(const Duration(seconds: 10));
    await settleApp(tester);
    expect(b.count('GET', '/api/v1/exports'), after);
  });

  testWidgets('下载后分享；删除前确认；过期与失败的导出不能下载', (tester) async {
    final jobs = [
      _job(
        _id1,
        'done',
        size: 2048,
        expiresAt: DateTime.now().add(const Duration(hours: 3)),
      ),
      _job(_id2, 'failed', error: '生成导出文件失败，请稍后重试'),
      _job(
        '0192a000-0000-7000-8000-0000000000e3',
        'done',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ];
    await pumpApp(tester, backend: _backend(jobs), width: 1200);
    await _open(tester);
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.textContaining('生成导出文件失败'), findsOneWidget);
    expect(find.textContaining('已过期'), findsOneWidget);
    expect(find.byKey(const Key('export-download-$_id2')), findsNothing);
    expect(find.byIcon(Icons.download), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('export-download-$_id1')));
    expect(TestHooks.exportFiles.shared, [
      ('https://oss.example/x.zip', '即刻日志导出-20261011-0930.zip'),
    ]);

    TestHooks.exportFiles.fail = Exception('network');
    await tapAndSettle(tester, find.byKey(const Key('export-download-$_id1')));
    expect(find.text('下载失败，请检查网络后重试'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('export-delete-$_id1')));
    expect(find.text('删除这次导出？'), findsOneWidget);
    await tapAndSettle(tester, find.text('取消'));
    expect(find.byKey(const Key('export-$_id1')), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('export-delete-$_id1')));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '删除'));
    expect(find.byKey(const Key('export-$_id1')), findsNothing);
  });

  testWidgets('服务端拒绝时显示原因；不选模块时不能导出', (tester) async {
    final b = _backend([])
      ..on(
        'POST',
        '/api/v1/exports',
        (_) => FakeResponse.error(
          429,
          'EXPORT_LIMIT',
          message: '24 小时内最多导出 5 次，请稍后再试',
        ),
      );
    await pumpApp(tester, backend: b, width: 1200);
    await _open(tester);
    await tapAndSettle(tester, find.byKey(const Key('export-start')));
    expect(find.text('24 小时内最多导出 5 次，请稍后再试'), findsOneWidget);

    for (final m in ExportModule.values) {
      await tapAndSettle(tester, find.byKey(Key('export-module-${m.name}')));
    }
    final start = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('export-start')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(start.onPressed, isNull);
  });

  testWidgets('读取列表失败时可以重试', (tester) async {
    var fail = true;
    final b = standardBackend()
      ..on(
        'GET',
        '/api/v1/exports',
        (_) => fail
            ? const FakeResponse(503, {
                'success': false,
                'requestId': 'test',
                'error': {'code': 'SERVICE_UNAVAILABLE', 'message': '服务暂不可用'},
              })
            : const FakeResponse(200, {
                'success': true,
                'requestId': 'test',
                'data': <Object>[],
              }),
      );
    await pumpApp(tester, backend: b);
    unawaited(_c(tester).read(routerProvider).push('/settings/export'));
    await settleApp(tester);
    expect(find.text('服务暂不可用'), findsOneWidget);
    fail = false;
    await tapAndSettle(tester, find.text('重试'));
    expect(find.text('还没有导出过'), findsOneWidget);
  });

  testWidgets('请求返回前离开页面不报错', (tester) async {
    final pending = Completer<FakeResponse>();
    final b = _backend([])
      ..on('POST', '/api/v1/exports', (_) => pending.future);
    await pumpApp(tester, backend: b, width: 1200);
    await _open(tester);
    await tester.tap(find.byKey(const Key('export-start')));
    await tester.pump();
    await tester.pageBack();
    await settleApp(tester);
    expect(find.byType(ExportPage), findsNothing);
    pending.complete(FakeResponse.ok(_job(_id2, 'pending'), status: 202));
    await settleApp(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏 + 大字号：导出页面不溢出', (tester) async {
    final jobs = [
      _job(
        _id1,
        'done',
        attachments: true,
        size: 123456789,
        expiresAt: DateTime.now().add(const Duration(hours: 3)),
      ),
      _job(_id2, 'failed', error: '生成导出文件失败，请稍后重试'),
    ];
    await pumpApp(
      tester,
      backend: _backend(jobs),
      width: 320,
      height: 700,
      textScale: 1.5,
    );
    unawaited(_c(tester).read(routerProvider).push('/settings/export'));
    await settleApp(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await settleApp(tester);
    expect(find.byKey(const Key('export-download-$_id1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('文件大小与文件名', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(25 * 1024 * 1024), '25 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    expect(
      exportFileName(DateTime(2026, 1, 2, 3, 4)),
      '即刻日志导出-20260102-0304.zip',
    );
    final job = ExportJob.fromJson({
      ..._job(_id1, 'unknown-status', modules: ['worklog', 'photos']),
    });
    expect(job.status, ExportStatus.failed);
    expect(job.modules, [ExportModule.worklog]);
    expect(job.canDownload(DateTime.now()), isFalse);
  });
}
