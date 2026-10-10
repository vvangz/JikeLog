import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/router.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/sync_providers.dart';
import 'package:jikelog/features/memos/memo_models.dart';
import 'package:jikelog/features/memos/memo_repository.dart';
import 'package:jikelog/features/memos/memo_widgets.dart';
import 'package:jikelog/features/reminders/local_notifier.dart';
import 'package:jikelog/features/reminders/reminder_coordinator.dart';
import 'package:jikelog/features/reminders/reminder_scheduler.dart';
import 'package:jikelog/features/worklog/worklog_repository.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';
import '../support/fake_sync_server.dart';

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

Future<void> _go(WidgetTester tester, String path) async {
  _c(tester).read(routerProvider).go(path);
  await settleApp(tester);
}

/// 等待自动保存（1 秒防抖）、提醒排定（0.3 秒防抖）与同步完成。
Future<void> _autosave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await settleApp(tester);
  await tester.pump(const Duration(seconds: 2));
  await settleApp(tester);
}

Future<Memo> _memo(WidgetTester tester, String id) async => (await _run<Memo?>(
  tester,
  () => _c(tester).read(memoRepositoryProvider).get(id),
))!;

Future<String> _create(
  WidgetTester tester, {
  String content = '周会',
  DateTime? at,
  bool allDay = false,
  List<int> reminders = const [0],
}) => _run(
  tester,
  () => _c(tester)
      .read(memoRepositoryProvider)
      .create(
        content: content,
        at: at ?? DateTime.now().add(const Duration(hours: 2)),
        allDay: allDay,
        reminders: reminders,
      ),
);

FakeBackend _backend() =>
    standardBackend()
      ..on('PUT', '/api/v1/me/push', (_) => FakeResponse.ok({'ok': true}));

void main() {
  tearDown(TestHooks.reset);
  setUp(ReminderCoordinator.resetLaunchForTesting);
  _reviewFixTests();

  testWidgets('空状态 → 新建备忘 → 输入后自动保存并同步，排定本地提醒', (tester) async {
    final server = FakeSyncServer();
    await pumpApp(tester, backend: _backend(), syncServer: server);
    await _go(tester, '/memos');
    expect(find.text('还没有备忘'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('memo-create')));
    expect(find.text('新建备忘'), findsOneWidget);
    expect(find.text('填写内容后自动保存'), findsOneWidget);
    // 默认提醒来自设置（准时）
    final onTime = tester.widget<FilterChip>(
      find.byKey(const Key('memo-reminder-0')),
    );
    expect(onTime.selected, isTrue);

    await tester.enterText(find.byKey(const Key('memo-content')), '交周报\n附上数据');
    await _autosave(tester);
    final rec = server.records.values.single;
    expect(rec.entity, 'memo');
    expect(rec.fields['content'], '交周报\n附上数据');
    expect(rec.fields['reminders'], '0');
    expect(find.text('填写内容后自动保存'), findsNothing);

    final alarm = TestHooks.notifier.scheduled.values.single;
    expect(alarm.title, '交周报');
    expect(memoIdOfPayload(alarm.payload), rec.id);

    await tester.pageBack();
    await settleApp(tester);
    expect(find.text('交周报'), findsOneWidget);
  });

  testWidgets('新建后没写内容就返回：不保存', (tester) async {
    await pumpApp(tester, backend: _backend());
    await _go(tester, '/memos');
    await tapAndSettle(tester, find.byKey(const Key('memo-create')));
    await tester.pageBack();
    await settleApp(tester);
    expect(find.text('还没有备忘'), findsOneWidget);
  });

  testWidgets('修改全天与提醒：立即保存；自定义提醒校验范围', (tester) async {
    await pumpApp(tester, backend: _backend());
    final id = await _create(tester);
    await _go(tester, '/memos/$id');

    await tapAndSettle(tester, find.byKey(const Key('memo-reminder-15')));
    expect((await _memo(tester, id)).reminders, [0, 15]);
    await tapAndSettle(tester, find.byKey(const Key('memo-reminder-0')));
    expect((await _memo(tester, id)).reminders, [15]);

    await tapAndSettle(tester, find.byKey(const Key('memo-reminder-custom')));
    await tester.enterText(
      find.byKey(const Key('custom-reminder-amount')),
      '0',
    );
    await tapAndSettle(tester, find.byKey(const Key('custom-reminder-ok')));
    expect(find.text('请输入 1 分钟到 30 天之间的提前量'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('custom-reminder-amount')),
      '2',
    );
    await tapAndSettle(tester, find.byKey(const Key('custom-reminder-unit')));
    await tapAndSettle(tester, find.text('小时').last);
    await tapAndSettle(tester, find.byKey(const Key('custom-reminder-ok')));
    expect((await _memo(tester, id)).reminders, [15, 120]);
    expect(find.byKey(const Key('memo-reminder-120')), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('memo-all-day')));
    final m = await _memo(tester, id);
    expect(m.allDay, isTrue);
    expect(m.at.hour, 9);
    expect(find.byKey(const Key('memo-time')), findsNothing);
    expect(find.text('提醒从当天 9:00 起算'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('memo-done')));
    expect((await _memo(tester, id)).done, isTrue);
  });

  testWidgets('选择日期与时间', (tester) async {
    await pumpApp(tester, backend: _backend());
    final at = DateTime(2030, 3, 4, 10, 30);
    final id = await _create(tester, at: at);
    await _go(tester, '/memos');
    unawaited(_c(tester).read(routerProvider).push('/memos/$id'));
    await settleApp(tester);
    expect(find.text('2030年3月4日'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('memo-date')));
    await tapAndSettle(tester, find.text('5'));
    await tapAndSettle(tester, find.text('OK'));
    expect((await _memo(tester, id)).at, DateTime(2030, 3, 5, 10, 30));

    await tapAndSettle(tester, find.byKey(const Key('memo-time')));
    await tapAndSettle(tester, find.text('OK'));
    expect((await _memo(tester, id)).at, DateTime(2030, 3, 5, 10, 30));

    // 取消全天：改为当天 9:00 的普通备忘
    await tapAndSettle(tester, find.byKey(const Key('memo-all-day')));
    await tapAndSettle(tester, find.byKey(const Key('memo-all-day')));
    final m = await _memo(tester, id);
    expect(m.allDay, isFalse);
    expect(m.at, DateTime(2030, 3, 5, 9));

    await tapAndSettle(tester, find.byKey(const Key('memo-delete')));
    await tapAndSettle(tester, find.text('删除').last);
    expect(
      await _run<Memo?>(
        tester,
        () => _c(tester).read(memoRepositoryProvider).get(id),
      ),
      isNull,
    );
    expect(find.text('还没有备忘'), findsOneWidget);
  });

  testWidgets('最多 5 个提醒；清空内容不保存', (tester) async {
    await pumpApp(tester, backend: _backend());
    final id = await _create(tester, reminders: [0, 5, 15, 60, 1440]);
    await _go(tester, '/memos/$id');
    await tapAndSettle(tester, find.byKey(const Key('memo-reminder-custom')));
    await tester.enterText(
      find.byKey(const Key('custom-reminder-amount')),
      '3',
    );
    await tapAndSettle(tester, find.byKey(const Key('custom-reminder-ok')));
    expect(find.text('最多设置 5 个提醒'), findsOneWidget);
    expect((await _memo(tester, id)).reminders, hasLength(5));

    await tester.enterText(find.byKey(const Key('memo-content')), '');
    await _autosave(tester);
    expect(find.text('内容不能为空，清空的内容不会保存'), findsOneWidget);
    expect((await _memo(tester, id)).content, '周会');
  });

  testWidgets('列表：逾期在前、勾选完成移入已完成并取消提醒', (tester) async {
    await pumpApp(tester, backend: _backend());
    final late = await _create(
      tester,
      content: '昨天没做的',
      at: DateTime.now().subtract(const Duration(days: 1)),
    );
    final soonAt = DateTime.now().add(const Duration(hours: 2));
    final soon = await _create(tester, content: '马上要做的', at: soonAt);
    await _go(tester, '/memos');
    expect(find.text('已逾期'), findsOneWidget);
    expect(find.text(friendlyDate(soonAt, DateTime.now())), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('昨天没做的')).dy,
      lessThan(tester.getTopLeft(find.text('马上要做的')).dy),
    );
    await settleApp(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await settleApp(tester);
    expect(TestHooks.notifier.scheduled.keys, [alarmId(soon, 0)]);

    await tapAndSettle(tester, find.byKey(Key('memo-check-$soon')));
    await tester.pump(const Duration(milliseconds: 400));
    await settleApp(tester);
    expect(find.text('已完成 1'), findsOneWidget);
    expect(TestHooks.notifier.scheduled, isEmpty);
    expect((await _memo(tester, late)).done, isFalse);
  });

  testWidgets('日历：标记备忘与工作日志，选中日期列出当天内容，从这天新建', (tester) async {
    await pumpApp(tester, backend: _backend());
    final today = dateOnly(DateTime.now());
    await _create(
      tester,
      content: '今天的备忘',
      at: today.add(const Duration(hours: 23)),
    );
    await _run(
      tester,
      () => _c(tester).read(worklogRepositoryProvider).create(location: '总部'),
    );
    await _go(tester, '/memos');
    await tapAndSettle(tester, find.text('日历'));
    expect(find.byKey(const Key('memo-calendar')), findsOneWidget);
    final agenda = find.byKey(const Key('memo-agenda'));
    expect(
      find.descendant(of: agenda, matching: find.text('今天的备忘')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: agenda, matching: find.text('总部')),
      findsOneWidget,
    );

    // 选中另一天：没有内容
    final other = today.day == 15 ? 16 : 15;
    await tapAndSettle(tester, find.text('$other').first);
    expect(find.text('这一天没有备忘和工作日志'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('memo-create')));
    await tester.enterText(find.byKey(const Key('memo-content')), '那天的事');
    await _autosave(tester);
    final repo = _c(tester).read(memoRepositoryProvider);
    final memos = (await tester.runAsync(() => repo.watchAll().first))!;
    final created = memos.firstWhere((m) => m.content == '那天的事');
    expect(created.day.day, other);
    expect(created.at.hour, allDayAnchorHour);
  });

  testWidgets('缺少权限时提示并可去开启；登记推送带上本地提醒能力', (tester) async {
    TestHooks.notifier
      ..perms = const ReminderPermissions(notifications: true, exact: false)
      ..afterRequest = const ReminderPermissions(
        notifications: true,
        exact: true,
      );
    TestHooks.push.token = 'reg-123';
    final backend = await pumpApp(tester, backend: _backend());
    final first = backend.last('PUT', '/api/v1/me/push').body!;
    expect(first, {
      'provider': 'jpush',
      'token': 'reg-123',
      'timeZone': 'Asia/Shanghai',
      'localReminders': false,
      'localUntil': null,
    });

    await _create(tester);
    await _go(tester, '/memos');
    expect(find.text('未允许精确闹钟，提醒可能延后几分钟'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('reminder-banner-enable')));
    expect(TestHooks.notifier.requestCount, 1);
    expect(find.byKey(const Key('reminder-banner')), findsNothing);
    expect(
      backend.last('PUT', '/api/v1/me/push').body!['localReminders'],
      isTrue,
    );
    expect(backend.count('PUT', '/api/v1/me/push'), 2);

    // 回到前台：没有变化时不重复登记
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleApp(tester);
    expect(backend.count('PUT', '/api/v1/me/push'), 2);
  });

  testWidgets('点按本地通知或推送通知打开对应备忘', (tester) async {
    await pumpApp(tester, backend: _backend());
    final id = await _create(tester, content: '点通知打开我');
    await _go(tester, '/memos');
    TestHooks.notifier.onTap!('$id|0|1|2');
    await settleApp(tester);
    expect(find.byKey(const Key('memo-content')), findsOneWidget);
    expect(find.text('点通知打开我'), findsWidgets);

    await tester.pageBack();
    await settleApp(tester);
    TestHooks.push.onOpen!(id);
    await settleApp(tester);
    expect(find.byKey(const Key('memo-content')), findsOneWidget);
  });

  testWidgets('设置：备忘录同步到系统日历，关闭时删除日历', (tester) async {
    await pumpApp(tester, backend: _backend());
    await _create(tester, content: '写进系统日历');
    await _go(tester, '/settings');
    expect(find.text('已开启，备忘会按时提醒'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('calendar-export')));
    await tapAndSettle(tester, find.text('开启'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleApp(tester);
    expect(TestHooks.calendar.calendars.values, ['即刻日志']);
    expect(TestHooks.calendar.all.single.title, '写进系统日历');

    await tapAndSettle(tester, find.byKey(const Key('calendar-export')));
    expect(TestHooks.calendar.calendars, isEmpty);

    TestHooks.calendar
      ..granted = false
      ..grantOnRequest = false;
    await tapAndSettle(tester, find.byKey(const Key('calendar-export')));
    await tapAndSettle(tester, find.text('开启'));
    expect(find.text('没有获得日历权限，可在系统设置中允许后重试'), findsOneWidget);
  });

  testWidgets('设置：缺少通知权限时可去开启', (tester) async {
    TestHooks.notifier
      ..perms = const ReminderPermissions(notifications: false, exact: true)
      ..afterRequest = const ReminderPermissions(
        notifications: true,
        exact: true,
      );
    await pumpApp(tester, backend: _backend());
    await _go(tester, '/settings');
    expect(find.text('未允许通知，备忘到时间不会弹出提醒'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(const Key('reminder-permission-enable')),
    );
    expect(find.text('已开启，备忘会按时提醒'), findsOneWidget);
  });

  testWidgets('退出登录：取消本地提醒并删除系统日历', (tester) async {
    await pumpApp(tester, backend: _backend());
    await _create(tester);
    await _go(tester, '/settings');
    await tapAndSettle(tester, find.byKey(const Key('calendar-export')));
    await tapAndSettle(tester, find.text('开启'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleApp(tester);
    expect(TestHooks.notifier.scheduled, isNotEmpty);
    expect(TestHooks.calendar.calendars, isNotEmpty);

    await _autosave(tester); // 先同步完，退出时不再提示有未同步的修改
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tapAndSettle(tester, find.byKey(const Key('nav-/account')));
    await tapAndSettle(tester, find.byKey(const Key('account-logout')));
    await tapAndSettle(tester, find.text('退出'));
    expect(TestHooks.notifier.scheduled, isEmpty);
    expect(TestHooks.calendar.calendars, isEmpty);
  });

  testWidgets('其他设备修改与删除', (tester) async {
    await pumpApp(tester, backend: _backend());
    final id = await _create(tester, content: '原来的');
    await _autosave(tester); // 先同步上去：本机未推送的修改不会被远端覆盖
    await _go(tester, '/memos');
    unawaited(_c(tester).read(routerProvider).push('/memos/$id'));
    await settleApp(tester);
    Future<void> remote(
      Map<String, Object?> fields, {
      bool deleted = false,
    }) => _run(tester, () async {
      final store = _c(tester).read(recordStoreProvider);
      final cur = (await store.get(id))!;
      final clock =
          '${DateTime.now().millisecondsSinceEpoch + 60000}-0000-bbbbbbbbbbbbbbbb';
      await store.applyRemote(
        RemoteRecord(
          entity: 'memo',
          id: id,
          version: cur.version + 1,
          serverSeq: cur.serverSeq + 1,
          deleted: deleted,
          fields: {...cur.fields, ...fields},
          clocks: {for (final f in cur.fields.keys) f: clock},
        ),
      );
    });

    await remote({'content': '对方改的'});
    final field = find.byKey(const Key('memo-content'));
    expect(tester.widget<TextField>(field).controller!.text, '对方改的');
    await remote({}, deleted: true);
    expect(find.text('这条备忘已在其他设备上删除'), findsOneWidget);
    expect(find.byKey(const Key('memo-content')), findsNothing);
  });
}

void _reviewFixTests() {
  testWidgets('本地闹钟排满时把覆盖范围告诉服务端', (tester) async {
    final backend = await pumpApp(tester, backend: _backend());
    final base = DateTime.now().add(const Duration(days: 1));
    for (var i = 0; i < 13; i++) {
      await _create(
        tester,
        content: '备忘 $i',
        at: base.add(Duration(hours: i)),
        reminders: [0, 5, 15, 60, 1440],
      );
    }
    await tester.pump(const Duration(milliseconds: 400));
    await settleApp(tester);
    expect(TestHooks.notifier.scheduled, hasLength(maxPlannedAlarms));
    final body = backend.last('PUT', '/api/v1/me/push').body!;
    expect(body['localReminders'], isTrue);
    expect(DateTime.parse(body['localUntil'] as String), isA<DateTime>());
  });

  testWidgets('退出后重新登录会重新登记推送', (tester) async {
    final backend = await pumpApp(tester, backend: _backend());
    expect(backend.count('PUT', '/api/v1/me/push'), 1);
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tapAndSettle(tester, find.byKey(const Key('nav-/account')));
    await tapAndSettle(tester, find.byKey(const Key('account-logout')));
    for (var i = 0; i < 40 && find.text('退出').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tapAndSettle(tester, find.text('退出'));
    await enter(tester, const Key('login-username'), 'zhangsan');
    await enter(tester, const Key('login-password'), 'Passw0rd!');
    await tapAndSettle(tester, find.byKey(const Key('login-submit')));
    expect(backend.count('PUT', '/api/v1/me/push'), 2);
  });

  testWidgets('点按通知：编辑页已打开时不重复打开；格式不对的 ID 忽略；启动通知只处理一次', (tester) async {
    const id0 = '0192a000-0000-7000-8000-00000000aaaa';
    TestHooks.notifier.launch = '$id0|0|1|2';
    await pumpApp(tester, backend: _backend());
    // 启动时的通知指向一条不存在的备忘：打开后显示不存在
    expect(find.text('备忘不存在'), findsOneWidget);
    await tester.pageBack();
    await settleApp(tester);

    final id = await _create(tester, content: '只开一个');
    TestHooks.notifier.onTap!('$id|0|1|2');
    await settleApp(tester);
    TestHooks.notifier.onTap!('$id|0|1|2');
    await settleApp(tester);
    expect(find.byKey(const Key('memo-content')), findsOneWidget);
    await tester.pageBack();
    await settleApp(tester);
    expect(find.byKey(const Key('memo-content')), findsNothing);

    TestHooks.push.onOpen!('../settings');
    await settleApp(tester);
    expect(find.byKey(const Key('memo-content')), findsNothing);
  });

  testWidgets('有未保存的输入时其他设备的修改合并进来', (tester) async {
    await pumpApp(tester, backend: _backend());
    final id = await _create(tester, content: '第一段\n第二段');
    await _autosave(tester);
    await _go(tester, '/memos');
    unawaited(_c(tester).read(routerProvider).push('/memos/$id'));
    await settleApp(tester);
    final field = find.byKey(const Key('memo-content'));
    await tester.enterText(field, '第一段，本地补充\n第二段');
    await tester.pump(const Duration(milliseconds: 100));
    await _run(tester, () async {
      final store = _c(tester).read(recordStoreProvider);
      final cur = (await store.get(id))!;
      final clock =
          '${DateTime.now().millisecondsSinceEpoch + 60000}-0000-bbbbbbbbbbbbbbbb';
      await store.applyRemote(
        RemoteRecord(
          entity: 'memo',
          id: id,
          version: cur.version + 1,
          serverSeq: cur.serverSeq + 1,
          deleted: false,
          fields: {...cur.fields, 'content': '第一段\n第二段，远端补充'},
          clocks: {...cur.clocks, 'content': clock},
        ),
      );
    });
    expect(
      tester.widget<TextField>(field).controller!.text,
      '第一段，本地补充\n第二段，远端补充',
    );
    await _autosave(tester);
    expect((await _memo(tester, id)).content, '第一段，本地补充\n第二段，远端补充');
  });

  testWidgets('矮屏 + 大字号：日历与当天内容可以滚动查看', (tester) async {
    await pumpApp(tester, backend: _backend(), height: 560, textScale: 1.5);
    await _create(
      tester,
      content: '矮屏也能看到',
      at: dateOnly(DateTime.now()).add(const Duration(hours: 23)),
    );
    await _go(tester, '/memos');
    await tapAndSettle(tester, find.text('日历'));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('矮屏也能看到'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('memo-agenda')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('矮屏也能看到'), findsOneWidget);
  });
}
