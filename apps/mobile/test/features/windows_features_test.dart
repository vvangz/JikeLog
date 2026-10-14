import 'dart:async';

import 'package:flutter/material.dart';
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
}
