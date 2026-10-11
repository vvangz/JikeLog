import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/router.dart';
import 'package:jikelog/core/sync/schema.dart';
import 'package:jikelog/core/sync/sync_providers.dart';
import 'package:jikelog/features/search/search_page.dart';
import 'package:jikelog/features/search/search_snippet.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';

ProviderContainer _c(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

var _seq = 0;

/// 写入一条记录（与同步、本地编辑相同的路径），返回 ID。
Future<String> _put(
  WidgetTester tester,
  String entity,
  Map<String, Object?> fields,
) async {
  final id =
      '0192a000-0000-7000-8000-${(++_seq).toRadixString(16).padLeft(12, '0')}';
  await tester.runAsync(
    () => _c(tester).read(recordStoreProvider).write(entity, id, fields),
  );
  return id;
}

Future<void> _go(WidgetTester tester, String path) async {
  _c(tester).read(routerProvider).go(path);
  await settleApp(tester);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('search-field')), text);
  // 等待输入防抖后再完成查询
  await tester.pump(const Duration(milliseconds: 300));
  await settleApp(tester);
}

Iterable<String> _hits(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('search-hit-'),
      ),
    )
    .map((w) => (w.key! as ValueKey<String>).value.substring(11));

void main() {
  tearDown(TestHooks.reset);

  testWidgets('从模块打开搜索时默认只搜该模块；可切换为全部；打开结果后返回', (tester) async {
    await pumpApp(tester);
    final note = await _put(tester, Entities.note, {
      'title': '季度评审',
      'body': '准备**评审**材料',
      'format': 'markdown',
    });
    final memo = await _put(tester, Entities.memo, {
      'content': '评审会议',
      'at': DateTime(2026, 10, 20, 9).millisecondsSinceEpoch,
      'allDay': 0,
      'reminders': '',
      'done': 0,
    });
    await _go(tester, '/notes');
    await tapAndSettle(tester, find.byKey(const Key('shell-search')));
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.text('搜索笔记'), findsOneWidget);
    expect(find.text('搜索'), findsWidgets, reason: '尚未输入时的说明');

    await _search(tester, '评审');
    expect(_hits(tester), [note]);
    expect(find.byKey(const Key('search-group-note')), findsOneWidget);
    expect(find.text('笔记 · 1'), findsOneWidget);
    // 标题与片段中的关键词高亮
    final title = tester.widget<HighlightText>(
      find
          .descendant(
            of: find.byKey(Key('search-hit-$note')),
            matching: find.byType(HighlightText),
          )
          .first,
    );
    expect(title.snippet.text, '季度评审');
    expect(title.snippet.ranges, [(2, 4)]);

    await tapAndSettle(tester, find.byKey(const Key('search-module-all')));
    expect(_hits(tester).toSet(), {note, memo});
    expect(find.text('备忘录 · 1'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(Key('search-hit-$memo')));
    expect(find.byType(SearchPage), findsNothing);
    await tester.pageBack();
    await settleApp(tester);
    expect(find.byType(SearchPage), findsOneWidget);
    expect(_hits(tester).toSet(), {note, memo});
  });

  testWidgets('流水按分类名搜到，显示分类与金额；多选模块与清除关键词', (tester) async {
    await pumpApp(tester);
    final cat = await _put(tester, Entities.ledgerCategory, {
      'name': '咖啡',
      'kind': 'expense',
      'icon': 'coffee',
      'archived': 0,
      'sortOrder': 0,
    });
    final acc = await _put(tester, Entities.ledgerAccount, {
      'name': '钱包',
      'type': 'cash',
      'initialBalance': '0',
      'archived': 0,
      'sortOrder': 0,
    });
    final entry = await _put(tester, Entities.ledgerEntry, {
      'type': 'expense',
      'amount': '2800',
      'fee': '0',
      'date': '2026-10-11',
      'accountId': acc,
      'categoryId': cat,
      'note': '拿铁',
    });
    final log = await _put(tester, Entities.worklog, {
      'date': '2026-10-11',
      'location': '咖啡馆',
      'content': '远程办公',
    });
    await _go(tester, '/ledger');
    await tapAndSettle(tester, find.byKey(const Key('shell-search')));
    expect(find.text('搜索记账'), findsOneWidget);
    await _search(tester, '咖啡');
    expect(_hits(tester), [entry]);
    expect(
      find.descendant(
        of: find.byKey(Key('search-hit-$entry')),
        matching: find.text('咖啡'),
      ),
      findsOneWidget,
    );
    expect(find.text('-28.00'), findsOneWidget);
    expect(find.text('拿铁'), findsOneWidget, reason: '备注作为片段显示');

    await tapAndSettle(tester, find.byKey(const Key('search-module-worklog')));
    expect(_hits(tester).toSet(), {entry, log});
    expect(find.text('2026-10-11 · 咖啡馆'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('search-module-ledger')));
    expect(_hits(tester), [log]);

    await tapAndSettle(tester, find.byKey(const Key('search-clear')));
    expect(_hits(tester), isEmpty);
    expect(find.byKey(const Key('search-clear')), findsNothing);
  });

  testWidgets('没有结果时提示；时间范围选择器可以打开和取消', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/worklog');
    await tapAndSettle(tester, find.byKey(const Key('shell-search')));
    await _search(tester, '不存在的内容');
    expect(find.text('没有找到相关内容'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('search-range')));
    expect(find.text('选择时间范围'), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('Close').last);
    expect(find.text('时间不限'), findsOneWidget);
  });

  testWidgets('宽屏时从侧栏打开搜索（全部模块）', (tester) async {
    await pumpApp(tester, width: 1200);
    await _go(tester, '/settings');
    await tapAndSettle(tester, find.byKey(const Key('nav-search')));
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.text('搜索全部内容'), findsOneWidget);
  });

  testWidgets('窄屏 + 大字号：筛选与结果不溢出', (tester) async {
    await pumpApp(tester, width: 320, height: 700, textScale: 1.5);
    final cat = await _put(tester, Entities.ledgerCategory, {
      'name': '一个名字非常长的餐饮分类',
      'kind': 'expense',
    });
    await _put(tester, Entities.ledgerEntry, {
      'type': 'expense',
      'amount': '123456789',
      'fee': '0',
      'date': '2026-10-11',
      'categoryId': cat,
      'note': '很长很长的备注内容，用来检查窄屏下的换行与省略',
    });
    await _put(tester, Entities.note, {
      'title': '一篇标题非常非常长的笔记，用来检查窄屏',
      'body': '正文中也包含餐饮两个字',
    });
    unawaited(_c(tester).read(routerProvider).push('/search'));
    await settleApp(tester);
    await _search(tester, '餐饮');
    expect(_hits(tester), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果超过上限时提示缩小范围', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(
      () => _c(tester).read(appDatabaseProvider).transaction(() async {
        for (var i = 0; i < 205; i++) {
          await _c(tester).read(recordStoreProvider).write(
            Entities.memo,
            '0192a000-0000-7000-8000-${(900000 + i).toRadixString(16).padLeft(12, '0')}',
            {
              'content': '批量备忘 $i',
              'at': i,
              'allDay': 0,
              'reminders': '',
              'done': 0,
            },
          );
        }
      }),
    );
    unawaited(_c(tester).read(routerProvider).push('/search'));
    await settleApp(tester);
    await _search(tester, '批量');
    expect(find.textContaining('共 205 条，只显示最近的 200 条'), findsOneWidget);
  });
}
