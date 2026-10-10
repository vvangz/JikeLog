import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/router.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/sync_providers.dart';
import 'package:jikelog/features/notes/note_models.dart';
import 'package:jikelog/features/notes/note_repository.dart';
import 'package:jikelog/features/worklog/worklog_repository.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';
import '../support/fake_media.dart';
import '../support/fake_sync_server.dart';

ProviderContainer _c(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

/// 等待自动保存（1 秒防抖）与同步完成。
Future<void> _autosave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await settleApp(tester);
  await tester.pump(const Duration(seconds: 2));
  await settleApp(tester);
}

/// 在测试的虚拟时间中执行异步操作并推进时间直到完成（见 worklog_pages_test）。
Future<T> _run<T>(WidgetTester tester, Future<T> Function() body) async {
  T? result;
  var done = false;
  Object? error;
  unawaited(
    body().then(
      (v) {
        result = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: '操作未完成');
  await settleApp(tester);
  return result as T;
}

/// 从本机库读取笔记（页面关闭后 noteProvider 不再被监听，其值可能已过时）。
Future<Note> _note(WidgetTester tester, String id) async => (await _run<Note?>(
  tester,
  () => _c(tester).read(noteRepositoryProvider).get(id),
))!;

/// 交替推进真实时间（文件读写）与虚拟时间，直到 [done] 成立。
Future<void> _waitUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: '等待超时');
  await settleApp(tester);
}

/// 点击工具栏按钮：工具栏横向滚动，滚动后先绘制一帧再点击。
Future<void> _tool(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, f);
}

/// 在对话框中输入并等待重建（确定按钮在有输入后才可用）。
Future<void> _input(
  WidgetTester tester,
  String text, {
  String key = 'text-input',
}) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

Future<void> _go(WidgetTester tester, String path) async {
  _c(tester).read(routerProvider).go(path);
  await settleApp(tester);
}

/// 进入笔记模块并新建一篇笔记，返回其 ID。
Future<String> _newNote(WidgetTester tester) async {
  await _go(tester, '/notes');
  await tapAndSettle(tester, find.byKey(const Key('note-create')));
  final router = _c(tester).read(routerProvider);
  return router.state.pathParameters['id']!;
}

/// 让本机收到"其他设备"对笔记正文的修改。
Future<void> _remoteBody(
  WidgetTester tester,
  String id,
  String body,
) => _run(tester, () async {
  final store = _c(tester).read(recordStoreProvider);
  final cur = (await store.get(id))!;
  final clock =
      '${DateTime.now().millisecondsSinceEpoch + 60000}-0000-bbbbbbbbbbbbbbbb';
  await store.applyRemote(
    RemoteRecord(
      entity: 'note',
      id: id,
      version: cur.version + 1,
      serverSeq: cur.serverSeq + 1,
      deleted: false,
      fields: {...cur.fields, 'body': body},
      clocks: {...cur.clocks, 'body': clock},
    ),
  );
});

void main() {
  tearDown(TestHooks.reset);
  _revisionTests();

  testWidgets('空状态 → 新建富文本笔记 → 输入 → 自动保存并同步 → 返回列表', (tester) async {
    final server = FakeSyncServer();
    await pumpApp(tester, syncServer: server);
    await _go(tester, '/notes');
    expect(find.text('还没有笔记'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('note-create')));
    expect(find.byKey(const Key('fake-rich-editor')), findsOneWidget);
    expect(find.byKey(const Key('rich-toolbar')), findsOneWidget);
    final ed = FakeRichEditor.current!;
    expect(ed.received.first['type'], 'init');

    await tester.enterText(find.byKey(const Key('note-title')), '周会纪要');
    ed.type('- [ ] 整理接口文档');
    await _autosave(tester);
    final rec = server.records.values.single;
    expect(rec.fields['title'], '周会纪要');
    expect(rec.fields['body'], '- [ ] 整理接口文档');
    expect(rec.fields['format'], 'rich');
    expect(find.text('已同步'), findsOneWidget);

    // 返回前取回编辑器中尚未发出的输入
    ed.type('- [ ] 整理接口文档\n- [ ] 发周报', deliver: false);
    await tester.pageBack();
    await settleApp(tester);
    expect(find.byKey(const Key('note-create')), findsOneWidget);
    expect(find.text('周会纪要'), findsOneWidget);
    final note = _c(tester).read(noteListProvider).value!.single;
    expect(note.body, contains('发周报'));
  });

  testWidgets('切换到 Markdown：插入图片并预览，切换回富文本内容不丢', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('jk-note');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final png = File('${tmp.path}/截图.png')..writeAsBytesSync(onePixelPng);
    TestHooks.pickImage = () async => [TestPickedFile(png)];

    await pumpApp(tester, syncServer: FakeSyncServer());
    final id = await _newNote(tester);
    FakeRichEditor.current!.type('富文本里写的');
    await tapAndSettle(tester, find.byKey(const Key('note-format')));
    final body = find.byKey(const Key('note-body'));
    expect(body, findsOneWidget);
    expect(
      find.descendant(of: body, matching: find.text('富文本里写的')),
      findsOneWidget,
    );

    String text() => tester.widget<TextField>(body).controller!.text;
    await tester.tap(find.byKey(const Key('note-insert-image')));
    await _waitUntil(tester, () => text().contains('attachment:'));
    expect(
      text(),
      matches(RegExp(r'富文本里写的\n\n!\[截图\.png\]\(attachment:[0-9a-f-]{36}\)\n')),
    );

    await tapAndSettle(
      tester,
      find.byKey(const Key('markdown-preview-toggle')),
    );
    await _waitUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);

    await tapAndSettle(tester, find.byKey(const Key('note-format')));
    expect(
      FakeRichEditor.current!.received.last['markdown'],
      contains('富文本里写的'),
    );
    await _autosave(tester);
    final n = _c(tester).read(noteProvider(id)).value!;
    expect(n.format, NoteFormat.rich);
    expect(n.body, contains('attachment:'));
  });

  testWidgets('富文本：其他设备的修改到达时编辑器中有尚未送达的输入，合并后保存', (tester) async {
    final server = FakeSyncServer();
    await pumpApp(tester, syncServer: server);
    final id = await _newNote(tester);
    final ed = FakeRichEditor.current!;
    ed.type('第一段\n第二段');
    await _autosave(tester);

    ed.type('第一段，本地\n第二段', deliver: false);
    await _remoteBody(tester, id, '第一段\n第二段，远端');
    expect(ed.received.where((m) => m['type'] == 'setMarkdown'), hasLength(2));
    expect(ed.markdown, '第一段，本地\n第二段，远端');
    (_c(tester).read(syncTransportProvider) as FakeTransport).online = false;
    await _autosave(tester);
    // 远端修改只模拟到达了本机（服务端上没有），所以检查本机保存的合并结果
    final saved = (await _run(
      tester,
      () => _c(tester).read(recordStoreProvider).get(id),
    ))!;
    expect(saved.fields['body'], '第一段，本地\n第二段，远端');
    expect(saved.dirty, isTrue);
  });

  testWidgets('Markdown：没有未保存的输入时直接显示其他设备的修改；同一处冲突时保留输入', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    final id = await _newNote(tester);
    await tapAndSettle(tester, find.byKey(const Key('note-format')));
    final body = find.byKey(const Key('note-body'));
    await tester.enterText(body, '原文');
    await _autosave(tester);

    await _remoteBody(tester, id, '原文，远端补充');
    expect(tester.widget<TextField>(body).controller!.text, '原文，远端补充');

    await tester.enterText(body, '本地改写');
    await tester.pump(const Duration(milliseconds: 100));
    await _remoteBody(tester, id, '远端改写');
    expect(find.textContaining('已保留你的输入'), findsOneWidget);
    expect(tester.widget<TextField>(body).controller!.text, '本地改写');
  });

  testWidgets('信息面板：文件夹、标签、关联工作日志；收藏与置顶；列表筛选', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    final c = _c(tester);
    final folder = await _run(
      tester,
      () => c.read(noteRepositoryProvider).createFolder('项目资料'),
    );
    final wl = await _run(tester, () async {
      final repo = c.read(worklogRepositoryProvider);
      final id = await repo.create(date: DateTime(2026, 10, 9));
      await repo.update(id, location: '公司');
      return id;
    });
    final id = await _newNote(tester);
    await tester.enterText(find.byKey(const Key('note-title')), '接口设计');

    await tapAndSettle(tester, find.byKey(const Key('note-info')));
    await tapAndSettle(tester, find.byKey(const Key('note-info-folder')));
    await tapAndSettle(tester, find.byKey(Key('folder-pick-$folder')));
    expect(find.text('项目资料'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('note-tag-add')));
    await _input(tester, '后端');
    await tapAndSettle(tester, find.byKey(const Key('text-input-ok')));
    expect(find.text('#后端'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('note-link-worklog')));
    await tapAndSettle(tester, find.byKey(Key('worklog-pick-$wl')));
    expect(find.text('2026 年 10 月 9 日 · 公司'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20)); // 关闭面板
    await settleApp(tester);

    await tapAndSettle(tester, find.byKey(const Key('note-favorite')));
    await tapAndSettle(tester, find.byKey(const Key('note-menu')));
    await tapAndSettle(tester, find.text('置顶'));
    await _autosave(tester);
    final n = c.read(noteProvider(id)).value!;
    expect(n.folderId, folder);
    expect(n.tags, ['后端']);
    expect(n.worklogIds, [wl]);
    expect(n.favorite && n.pinned, isTrue);

    await tester.pageBack();
    await settleApp(tester);
    expect(find.text('接口设计'), findsOneWidget);
    expect(find.text('后端'), findsOneWidget);
    expect(find.text('1 条日志'), findsOneWidget);

    Future<void> filter(String key) async {
      await tapAndSettle(tester, find.byKey(const Key('note-filter-open')));
      await tapAndSettle(tester, find.byKey(Key(key)));
    }

    await filter('filter-tag-后端');
    expect(find.text('#后端'), findsOneWidget);
    expect(find.text('接口设计'), findsOneWidget);
    await filter('filter-unfiled');
    expect(find.text('这里还没有笔记'), findsOneWidget);
    await filter('filter-favorites');
    expect(find.text('接口设计'), findsOneWidget);
    await filter('filter-folder-$folder');
    expect(find.text('接口设计'), findsOneWidget);

    // 工作日志页显示关联的笔记
    await _go(tester, '/worklog/$wl');
    expect(find.byKey(Key('linked-note-$id')), findsOneWidget);
  });

  testWidgets('文件夹与标签的管理：新建、重命名、移动、删除', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer(), width: 1000);
    final c = _c(tester);
    await _go(tester, '/notes');
    expect(
      find.byKey(const Key('note-filter-panel')),
      findsOneWidget,
      reason: '宽屏常驻',
    );

    await tapAndSettle(tester, find.byKey(const Key('folder-create')));
    await _input(tester, '工作');
    await tapAndSettle(tester, find.byKey(const Key('text-input-ok')));
    final work = c.read(noteFoldersProvider).value!.roots.single.folder.id;

    await tapAndSettle(tester, find.byKey(Key('folder-menu-$work')));
    await tapAndSettle(tester, find.text('新建子文件夹'));
    await _input(tester, '项目');
    await tapAndSettle(tester, find.byKey(const Key('text-input-ok')));
    final tree = c.read(noteFoldersProvider).value!;
    final proj = tree.roots.single.children.single.folder.id;

    await tapAndSettle(tester, find.byKey(Key('filter-folder-$proj')));
    await tapAndSettle(tester, find.byKey(const Key('note-create')));
    final noteId = c.read(routerProvider).state.pathParameters['id']!;
    await _run(
      tester,
      () => c.read(noteRepositoryProvider).addTag(noteId, '旧名'),
    );
    await tester.pageBack();
    await settleApp(tester);
    expect((await _note(tester, noteId)).folderId, proj, reason: '在当前文件夹中新建');

    await tapAndSettle(tester, find.byKey(Key('folder-menu-$proj')));
    await tapAndSettle(tester, find.text('重命名'));
    await _input(tester, '项目 A');
    await tapAndSettle(tester, find.byKey(const Key('text-input-ok')));
    expect(find.text('工作 / 项目 A'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(Key('folder-menu-$proj')));
    await tapAndSettle(tester, find.text('移动到…'));
    await tapAndSettle(tester, find.byKey(const Key('folder-pick-none')));
    expect(c.read(noteFoldersProvider).value!.roots, hasLength(2));

    await tapAndSettle(tester, find.byKey(const Key('tag-menu-旧名')));
    await tapAndSettle(tester, find.text('重命名'));
    await _input(tester, '新名');
    await tapAndSettle(tester, find.byKey(const Key('text-input-ok')));
    expect((await _note(tester, noteId)).tags, ['新名']);

    await tapAndSettle(tester, find.byKey(const Key('tag-menu-新名')));
    await tapAndSettle(tester, find.text('删除'));
    await tapAndSettle(tester, find.text('删除').last);
    expect((await _note(tester, noteId)).tags, isEmpty);

    await tapAndSettle(tester, find.byKey(Key('folder-menu-$proj')));
    await tapAndSettle(tester, find.text('删除'));
    await tapAndSettle(tester, find.text('删除').last);
    expect((await _note(tester, noteId)).folderId, isNull);
    expect(find.text('全部笔记'), findsWidgets);
  });

  testWidgets('工作日志中新建、关联与取消关联笔记', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    final c = _c(tester);
    final other = await _run(tester, () async {
      final repo = c.read(noteRepositoryProvider);
      final id = await repo.create();
      await repo.update(id, title: '已有的笔记');
      return id;
    });
    await tapAndSettle(tester, find.byKey(const Key('worklog-create')));
    final wl = c.read(worklogListProvider).value!.single.id;

    await tapAndSettle(tester, find.byKey(const Key('worklog-note-create')));
    final created = c.read(routerProvider).state.pathParameters['id']!;
    expect(c.read(noteProvider(created)).value!.worklogIds, [wl]);
    await tester.pageBack();
    await settleApp(tester);
    expect(find.byKey(Key('linked-note-$created')), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('worklog-note-link')));
    await tester.enterText(find.byKey(const Key('note-picker-search')), '已有');
    await tester.pump();
    await tapAndSettle(tester, find.byKey(Key('note-pick-$other')));
    expect(find.byKey(Key('linked-note-$other')), findsOneWidget);

    await tapAndSettle(
      tester,
      find.descendant(
        of: find.byKey(Key('linked-note-$other')),
        matching: find.byTooltip('取消关联'),
      ),
    );
    expect(find.byKey(Key('linked-note-$other')), findsNothing);
  });

  testWidgets('删除笔记；其他设备删除时关闭编辑页', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    await _newNote(tester);
    await tapAndSettle(tester, find.byKey(const Key('note-menu')));
    await tapAndSettle(tester, find.text('删除'));
    await tapAndSettle(tester, find.text('删除').last);
    expect(find.text('还没有笔记'), findsOneWidget);

    final id = await _newNote(tester);
    FakeRichEditor.current!.type('内容');
    await _autosave(tester);
    await _run(tester, () async {
      final store = _c(tester).read(recordStoreProvider);
      final cur = (await store.get(id))!;
      await store.applyRemote(
        RemoteRecord(
          entity: 'note',
          id: id,
          version: cur.version + 1,
          serverSeq: cur.serverSeq + 1,
          deleted: true,
          fields: const {},
          clocks: const {},
        ),
      );
    });
    expect(find.text('这篇笔记已在其他设备上删除'), findsOneWidget);
    expect(find.byKey(const Key('note-create')), findsOneWidget);
  });

  testWidgets('富文本工具栏：命令、表格菜单、链接与打开链接、图片请求', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    await _newNote(tester);
    final ed = FakeRichEditor.current!;
    List<Object?> commands() => [
      for (final m in ed.received)
        if (m['type'] == 'command') m['name'],
    ];

    await tapAndSettle(tester, find.byTooltip('加粗'));
    await tapAndSettle(tester, find.byTooltip('待办'));
    await tapAndSettle(tester, find.byTooltip('插入表格'));
    expect(commands(), ['bold', 'taskList', 'insertTable']);

    await _tool(tester, find.byIcon(Icons.link));
    await _input(tester, 'javascript:alert(1)', key: 'rich-link-input');
    await tapAndSettle(tester, find.byKey(const Key('rich-link-ok')));
    expect(find.text('只支持 http、https、mailto、tel 链接'), findsOneWidget);
    // 提示浮在底部工具栏上，等它消失
    await tester.pump(const Duration(seconds: 5));
    await settleApp(tester);
    await _tool(tester, find.byIcon(Icons.link));
    await _input(tester, 'https://example.com', key: 'rich-link-input');
    await tapAndSettle(tester, find.byKey(const Key('rich-link-ok')));
    expect(ed.received.last, {
      'type': 'setLink',
      'href': 'https://example.com',
    });

    ed.reportState({'link': 'https://example.com'});
    await settleApp(tester);
    await _tool(tester, find.byIcon(Icons.link));
    await _input(tester, '', key: 'rich-link-input');
    await tapAndSettle(tester, find.byKey(const Key('rich-link-ok')));
    expect(commands().last, 'unsetLink');
    await _tool(tester, find.byIcon(Icons.open_in_new));
    await tapAndSettle(tester, find.text('打开'));
    expect(TestHooks.launched.single.toString(), 'https://example.com');

    ed.reportState({
      'inTable': true,
      'bold': true,
      'canUndo': true,
      'heading': 2,
    });
    await settleApp(tester);
    await tapAndSettle(tester, find.byTooltip('撤销'));
    await tapAndSettle(tester, find.byKey(const Key('rich-table-menu')));
    await tapAndSettle(tester, find.text('在下方插入行'));
    await tapAndSettle(tester, find.byTooltip('标题'));
    await tapAndSettle(tester, find.text('一级标题'));
    expect(commands().skip(4), ['undo', 'addRowAfter', 'heading1']);

    // 不存在的附件：回复 null，编辑器显示"无法显示"
    ed.requestImage('0190a1b2-0000-7000-8000-000000000009');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settleApp(tester);
    expect(ed.received.last, {
      'type': 'image',
      'id': '0190a1b2-0000-7000-8000-000000000009',
      'dataUrl': null,
    });
  });
}

void _revisionTests() {
  testWidgets('笔记修订历史：查看冲突版本（含正文中的图片）并恢复', (tester) async {
    final backend = standardBackend()
      ..on(
        'POST',
        '/api/v1/sync/e2e/session',
        (_) => FakeResponse.ok({
          'sessionId': 's1',
          'expiresAt': '2100-01-01T00:00:00Z',
        }, status: 201),
      );
    await pumpApp(tester, backend: backend, syncServer: FakeSyncServer());
    final id = await _newNote(tester);
    final api = _c(tester).read(syncApiProvider);
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
          'entity': 'note',
          'version': 1,
          'reason': 'conflict',
          'createdAt': '2026-10-09T08:00:00Z',
          'fields': {
            'title': await s.sealValue('note', id, 'title', '另一台设备的标题'),
            'body': await s.sealValue('note', id, 'body', '另一台设备的正文'),
            'format': 'markdown',
          },
        });
      });

    await tapAndSettle(tester, find.byKey(const Key('note-menu')));
    await tapAndSettle(tester, find.text('修订历史'));
    await tapAndSettle(tester, find.text('冲突中未被采用的版本'));
    expect(find.text('另一台设备的标题'), findsOneWidget);
    expect(find.text('另一台设备的正文'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('revision-restore')));
    await tester.pump(const Duration(seconds: 2));
    await settleApp(tester);
    final n = await _note(tester, id);
    expect(n.title, '另一台设备的标题');
    expect(n.body, '另一台设备的正文');
  });

  testWidgets('信息面板中录音，保存为笔记的附件', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    await _newNote(tester);
    await tapAndSettle(tester, find.byKey(const Key('note-info')));
    await tapAndSettle(tester, find.byKey(const Key('attachment-record')));
    await tester.tap(find.byKey(const Key('recorder-toggle')));
    await _waitUntil(tester, () => find.text('停止并保存').evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('recorder-toggle')));
    await _waitUntil(
      tester,
      () => find.textContaining('.m4a').evaluate().isNotEmpty,
    );
    expect(find.textContaining('录音 '), findsOneWidget);
  });
}
