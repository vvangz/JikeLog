import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/router.dart';
import 'package:jikelog/core/platform/platform_features.dart';
import 'package:jikelog/features/notes/note_models.dart';
import 'package:jikelog/features/notes/note_repository.dart';

import '../support/app_harness.dart';
import '../support/fake_sync_server.dart';

/// Windows 上关闭的功能（ADR-013）：富文本编辑器、系统日历。
ProviderContainer _c(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

Future<void> _go(WidgetTester tester, String path) async {
  _c(tester).read(routerProvider).go(path);
  await settleApp(tester);
}

/// 在测试的虚拟时间中完成仓库操作（见 notes_pages_test）。
Future<T> _run<T>(WidgetTester tester, Future<T> Function() body) async {
  T? result;
  var done = false;
  unawaited(
    body().then((v) {
      result = v;
      done = true;
    }),
  );
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue, reason: '操作未完成');
  await settleApp(tester);
  return result as T;
}

void main() {
  testWidgets('Windows：新建笔记用 Markdown，没有切换编辑方式的按钮', (tester) async {
    await pumpApp(
      tester,
      syncServer: FakeSyncServer(),
      features: PlatformFeatures.windows,
      width: 1280,
      height: 800,
    );
    await _go(tester, '/notes');
    await tapAndSettle(tester, find.byKey(const Key('note-create')));

    expect(find.byKey(const Key('note-body')), findsOneWidget);
    expect(find.byKey(const Key('note-format')), findsNothing);
    final id = _c(tester).read(routerProvider).state.pathParameters['id']!;
    final note = await _run(
      tester,
      () => _c(tester).read(noteRepositoryProvider).get(id),
    );
    expect(note!.format, NoteFormat.markdown);
  });

  testWidgets('Windows：富文本笔记用 Markdown 打开，不改保存的格式', (tester) async {
    await pumpApp(
      tester,
      syncServer: FakeSyncServer(),
      features: PlatformFeatures.windows,
      width: 1280,
      height: 800,
    );
    final repo = _c(tester).read(noteRepositoryProvider);
    final id = await _run(tester, () => repo.create(format: NoteFormat.rich));
    await _run(tester, () => repo.update(id, body: '在手机上写的富文本'));

    await _go(tester, '/notes/$id');
    final body = find.byKey(const Key('note-body'));
    expect(body, findsOneWidget);
    expect(
      find.descendant(of: body, matching: find.text('在手机上写的富文本')),
      findsOneWidget,
    );
    final note = await _run(tester, () => repo.get(id));
    expect(note!.format, NoteFormat.rich);
  });

  testWidgets('Windows：设置页不显示"同步到系统日历"', (tester) async {
    await pumpApp(
      tester,
      features: PlatformFeatures.windows,
      width: 1280,
      height: 800,
    );
    await _go(tester, '/settings');
    expect(find.byKey(const Key('calendar-export')), findsNothing);
  });

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleApp(tester);
  }

  testWidgets('快捷键：Ctrl+N 在当前模块新建，Ctrl+F 打开搜索；子页面上不处理', (tester) async {
    await pumpApp(
      tester,
      syncServer: FakeSyncServer(),
      features: PlatformFeatures.windows,
      width: 1280,
      height: 800,
    );
    await _go(tester, '/notes');
    await ctrl(tester, LogicalKeyboardKey.keyN);
    final router = _c(tester).read(routerProvider);
    expect(router.state.matchedLocation, startsWith('/notes/'));

    // 已在笔记编辑页（子页面）：快捷键不再新建
    final editing = router.state.matchedLocation;
    await ctrl(tester, LogicalKeyboardKey.keyN);
    expect(router.state.matchedLocation, editing);

    await _go(tester, '/ledger');
    await ctrl(tester, LogicalKeyboardKey.keyN);
    expect(router.state.matchedLocation, '/ledger/entry/new');

    await _go(tester, '/memos');
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(router.state.matchedLocation, '/search');
  });

  testWidgets('快捷键：底部面板打开时不新建；Ctrl+Alt（AltGr）不处理', (tester) async {
    await pumpApp(
      tester,
      syncServer: FakeSyncServer(),
      features: PlatformFeatures.windows,
    );
    await _go(tester, '/notes');
    await tapAndSettle(tester, find.byKey(const Key('note-filter-open')));
    await ctrl(tester, LogicalKeyboardKey.keyN);
    final router = _c(tester).read(routerProvider);
    expect(router.state.matchedLocation, '/notes');

    // 关闭底部面板
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await settleApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleApp(tester);
    expect(router.state.matchedLocation, '/notes');

    await ctrl(tester, LogicalKeyboardKey.keyN);
    expect(router.state.matchedLocation, startsWith('/notes/'));
  });
}
