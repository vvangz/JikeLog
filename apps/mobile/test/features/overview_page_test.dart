import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/providers.dart';
import 'package:jikelog/features/ledger/entry_editor_page.dart';
import 'package:jikelog/features/ledger/ledger_models.dart';
import 'package:jikelog/features/ledger/ledger_presets.dart';
import 'package:jikelog/features/ledger/ledger_repository.dart';
import 'package:jikelog/features/memos/memo_repository.dart';
import 'package:jikelog/features/notes/note_repository.dart';
import 'package:jikelog/features/notes/notes_list_page.dart';
import 'package:jikelog/features/overview/overview_page.dart';
import 'package:jikelog/features/worklog/worklog_repository.dart';

import '../support/app_harness.dart';
import '../support/fake_sync_server.dart';

const _user = '0192a000-0000-7000-8000-000000000001';

ProviderContainer _c(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

/// 在测试的虚拟时间中执行异步操作并推进时间直到完成。
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

/// 造一组数据：今天的日志、今天晚些时候的备忘、一篇笔记、一个账户与一笔支出。
Future<void> _seed(WidgetTester tester) async {
  final c = _c(tester);
  final now = DateTime.now();
  await _run(tester, () async {
    await c.read(worklogRepositoryProvider).create(date: now);
    await c
        .read(memoRepositoryProvider)
        .create(content: '季度复盘', at: now.add(const Duration(minutes: 30)));
    final note = await c.read(noteRepositoryProvider).create();
    await c.read(noteRepositoryProvider).update(note, title: '读书笔记');
    final ledger = c.read(ledgerRepositoryProvider);
    final acc = await ledger.createAccount(
      name: '现金',
      type: AccountType.cash,
      initialBalance: 100000,
    );
    await ledger.createEntry(
      EntryDraft(
        type: EntryType.expense,
        amount: 3250,
        date: now,
        accountId: acc,
        categoryId: presetCategoryId(_user, 'expense.food.lunch'),
      ),
    );
  });
}

/// 滚动到可见（ensureVisible 要在下一帧才生效）后点击。
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, f);
}

void main() {
  testWidgets('登录后默认进入概览：问候、今日摘要与各模块空状态', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    expect(find.byType(OverviewPage), findsOneWidget);
    expect(find.textContaining('张三'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('overview-summary'))).data,
      '今天没有待办 · 今日日志还没写',
    );
    for (final k in ['worklog', 'memos', 'ledger', 'notes']) {
      expect(find.byKey(Key('overview-$k')), findsOneWidget);
    }
    expect(find.text('接下来没有待办'), findsOneWidget);
    expect(find.text('还没有笔记'), findsOneWidget);
    expect(find.textContaining('还没有记账'), findsOneWidget);
  });

  testWidgets('有数据时显示统计；金额可隐藏并记在本机', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    await _seed(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('overview-summary'))).data,
      '今天 1 条备忘待完成 · 今日日志已写',
    );
    expect(find.text('季度复盘'), findsOneWidget);
    expect(find.text('读书笔记'), findsOneWidget);
    expect(find.text('32.50'), findsOneWidget); // 本月支出
    expect(
      tester.widget<Text>(find.byKey(const Key('overview-net-worth'))).data,
      '967.50',
    );

    await _tap(tester, find.byKey(const Key('overview-hide-amounts')));
    expect(find.text('32.50'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('overview-net-worth'))).data,
      '****',
    );
    expect(
      _c(tester).read(keyValueStoreProvider).getString('overview.hideAmounts'),
      '1',
    );

    // 离开再回来仍保持隐藏
    await goTo(tester, '/notes');
    await goTo(tester, '/overview');
    expect(
      tester.widget<Text>(find.byKey(const Key('overview-net-worth'))).data,
      '****',
    );

    await _tap(tester, find.byKey(const Key('overview-hide-amounts')));
    expect(find.text('32.50'), findsOneWidget);
    expect(
      _c(tester).read(keyValueStoreProvider).getString('overview.hideAmounts'),
      isNull,
    );
  });

  testWidgets('点击卡片进入模块，点击条目打开详情，快捷按钮新建', (tester) async {
    await pumpApp(tester, syncServer: FakeSyncServer());
    await _seed(tester);

    await _tap(tester, find.byKey(const Key('overview-notes')));
    expect(find.byType(NotesListPage), findsOneWidget);

    await goTo(tester, '/overview');
    await _tap(tester, find.text('读书笔记'));
    expect(find.byKey(const Key('note-title')), findsOneWidget);

    await goTo(tester, '/overview');
    await _tap(tester, find.byKey(const Key('overview-action-entry')));
    expect(find.byType(EntryEditorPage), findsOneWidget);
  });

  testWidgets('宽屏：卡片两列排列，同一行等高', (tester) async {
    await pumpApp(tester, width: 1200, syncServer: FakeSyncServer());
    final worklog = tester.getRect(find.byKey(const Key('overview-worklog')));
    final memos = tester.getRect(find.byKey(const Key('overview-memos')));
    final ledger = tester.getRect(find.byKey(const Key('overview-ledger')));
    expect(memos.top, worklog.top);
    expect(memos.left, greaterThan(worklog.right));
    expect(memos.height, worklog.height);
    expect(ledger.top, greaterThan(worklog.bottom));
  });

  testWidgets('窄屏 + 2 倍字号：有数据时不溢出', (tester) async {
    await pumpApp(
      tester,
      width: 320,
      height: 700,
      textScale: 2,
      syncServer: FakeSyncServer(),
    );
    await _seed(tester);
    expect(tester.takeException(), isNull);
  });
}
