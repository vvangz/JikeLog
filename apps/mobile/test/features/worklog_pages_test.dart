import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/sync/sync_providers.dart';
import 'package:jikelog/features/worklog/worklog_list_page.dart';
import 'package:jikelog/features/worklog/worklog_repository.dart';

import '../support/app_harness.dart';
import '../support/fake_sync_server.dart';

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(
    find.byType(WorklogListPage).evaluate().isNotEmpty
        ? find.byType(WorklogListPage)
        : find.byType(Scaffold).first,
  ),
);

/// 等待自动保存（1 秒防抖）与同步完成。
Future<void> _autosave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await settleApp(tester);
  await tester.pump(const Duration(seconds: 2));
  await settleApp(tester);
}

/// 在测试的虚拟时间中执行异步操作并推进时间直到完成（不用 runAsync：
/// 页面已在虚拟时间中启动的同步任务在真实时间里永远不会完成，会互相等待）。
Future<void> _run(WidgetTester tester, Future<void> Function() body) async {
  var done = false;
  Object? error;
  body().then(
    (_) => done = true,
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: '操作未完成');
  await settleApp(tester);
}

void main() {
  testWidgets('空状态 → 写日志 → 自动保存并同步 → 回到列表', (tester) async {
    final server = FakeSyncServer();
    await pumpApp(tester, syncServer: server);
    expect(find.text('还没有工作日志'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('worklog-create')));
    expect(find.byKey(const Key('worklog-content')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('worklog-location')), '公司');
    await tester.enterText(
      find.byKey(const Key('worklog-content')),
      '## 上午\n- 参加周会\n- [ ] 整理需求',
    );
    await _autosave(tester);
    expect(find.text('已同步'), findsOneWidget);
    final rec = server.records.values.single;
    expect(rec.fields['location'], '公司');
    expect(rec.fields['content'], contains('参加周会'));

    await tester.pageBack();
    await settleApp(tester);
    expect(find.text('公司'), findsOneWidget);
    expect(find.textContaining('上午 参加周会'), findsOneWidget);
  });

  testWidgets('离线编辑显示已保存在本机，列表标记待同步', (tester) async {
    final server = FakeSyncServer();
    await pumpApp(tester, syncServer: server);
    final c = _container(tester);
    (c.read(syncTransportProvider) as FakeTransport).online = false;

    await tapAndSettle(tester, find.byKey(const Key('worklog-create')));
    await tester.enterText(find.byKey(const Key('worklog-content')), '离线写的');
    await _autosave(tester);
    expect(find.text('已保存在本机，联网后自动同步'), findsOneWidget);
    await tester.pageBack();
    await settleApp(tester);
    expect(find.byTooltip('待同步'), findsOneWidget);
    expect(server.records, isEmpty);
  });

  testWidgets('Markdown 工具栏插入格式，预览渲染内容', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    await tapAndSettle(tester, find.byKey(const Key('worklog-create')));
    final field = find.byKey(const Key('worklog-content'));
    await tester.enterText(field, '今天');
    await tapAndSettle(tester, find.byTooltip('待办'));
    expect(tester.widget<TextField>(field).controller!.text, '- [ ] 今天');
    await tapAndSettle(tester, find.byTooltip('表格'));
    expect(
      tester.widget<TextField>(field).controller!.text,
      contains('| 事项 | 进度 |'),
    );
    await tapAndSettle(
      tester,
      find.byKey(const Key('markdown-preview-toggle')),
    );
    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(find.text('事项'), findsOneWidget);
  });

  testWidgets('工作地点联想历史地点', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    final repo = _container(tester).read(worklogRepositoryProvider);
    await _run(tester, () async {
      final id = await repo.create();
      await repo.update(id, location: '客户现场');
    });
    await tapAndSettle(tester, find.byKey(const Key('worklog-create')));
    await tester.tap(find.byKey(const Key('worklog-location')));
    await tester.enterText(find.byKey(const Key('worklog-location')), '客户');
    await settleApp(tester);
    expect(find.widgetWithText(ListTile, '客户现场'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(ListTile, '客户现场'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('worklog-location')))
          .controller!
          .text,
      '客户现场',
    );
  });

  testWidgets('冲突版本提示，删除日志后从列表消失', (tester) async {
    final server = FakeSyncServer();
    await pumpApp(tester, syncServer: server);
    final c = _container(tester);
    late String id;
    await _run(tester, () async {
      id = await c.read(worklogRepositoryProvider).create();
      await c.read(syncEngineProvider).sync();
      // 模拟服务端在推送时判定冲突
      final store = c.read(recordStoreProvider);
      final r = (await store.get(id))!;
      await store.applyRemote(
        remoteOf(server.records[id]!, r.entity),
        conflict: true,
      );
    });
    await settleApp(tester);
    expect(find.byTooltip('有冲突版本'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('有冲突版本'));
    expect(find.byKey(const Key('worklog-conflict')), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('worklog-delete')));
    await tapAndSettle(tester, find.text('删除').last);
    await _autosave(tester);
    expect(find.text('还没有工作日志'), findsOneWidget);
    expect(server.records[id]!.deleted, isTrue);
  });

  test('列表预览去掉 Markdown 标记', () {
    expect(
      plainPreview('## 标题\n- **加粗**\n- [x] 完成\n| a | b |\n```\ncode'),
      '标题 加粗 完成 code',
    );
  });
}
