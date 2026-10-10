import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/features/memos/memo_models.dart';
import 'package:jikelog/features/reminders/system_calendar.dart';

import '../../support/fake_reminders.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSystemCalendar cal;
  late MemoryStore prefs;
  late CalendarExporter exporter;
  final now = DateTime(2026, 10, 12, 8);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cal = FakeSystemCalendar();
    prefs = MemoryStore();
    exporter = CalendarExporter(
      calendar: cal,
      db: db,
      prefs: prefs,
      now: () => now,
    );
  });

  tearDown(() => db.close());

  Memo memo(
    String id, {
    DateTime? at,
    bool allDay = false,
    bool done = false,
    String content = '周会',
  }) => Memo(
    id: id,
    content: content,
    at: at ?? DateTime(2026, 10, 12, 15, 30),
    allDay: allDay,
    done: done,
    updatedAt: now,
  );

  test('未开启时不写入', () async {
    await exporter.reconcile([memo('a')], owner: 'u1');
    expect(cal.calendars, isEmpty);
    expect(exporter.enabled, isFalse);
  });

  test('开启后创建"即刻日志"日历并写入事件；修改、完成与删除同步过去', () async {
    expect(await exporter.enable(), isTrue);
    await exporter.reconcile([
      memo('a'),
      memo('b', at: DateTime(2026, 10, 13, 9), allDay: true, content: '体检\n空腹'),
      memo('old', at: DateTime(2026, 8, 1)), // 超出过去 30 天
    ], owner: 'u1');
    expect(cal.calendars.values, [systemCalendarName]);
    final events = {for (final e in cal.all) e.title: e};
    expect(events.keys, unorderedEquals(['周会', '体检']));
    expect(events['周会']!.end, DateTime(2026, 10, 12, 16));
    expect(events['体检']!.allDay, isTrue);
    expect(events['体检']!.start, DateTime(2026, 10, 13));
    expect(events['体检']!.end, DateTime(2026, 10, 14));

    await exporter.reconcile([
      memo('a', at: DateTime(2026, 10, 12, 17), done: true),
    ], owner: 'u1');
    expect(cal.all.single.title, '✓ 周会');
    expect(cal.all.single.start, DateTime(2026, 10, 12, 17));
    expect(cal.events, hasLength(1), reason: '更新事件而不是新建');
  });

  test('用户在系统日历中删掉事件或日历后重建', () async {
    await exporter.enable();
    await exporter.reconcile([memo('a')], owner: 'u1');
    cal.events.clear();
    await exporter.reconcile([memo('a', content: '改名')], owner: 'u1');
    expect(cal.all.single.title, '改名');

    cal.calendars.clear();
    cal.events.clear();
    await exporter.reconcile([memo('a', content: '改名')], owner: 'u1');
    expect(cal.calendars, hasLength(1));
    expect(cal.all.single.title, '改名');
  });

  test('换了账号时整个日历重建，不留下旧事件；没有备忘时不反复重建', () async {
    await exporter.enable();
    await exporter.reconcile([], owner: 'u1');
    final first = cal.calendars.keys.single;
    await exporter.reconcile([], owner: 'u1');
    expect(cal.calendars.keys.single, first, reason: '同一账号不重建');
    await exporter.reconcile([memo('a'), memo('b')], owner: 'u1');
    await db.wipe();
    await exporter.reconcile([memo('c', content: '新账号的备忘')], owner: 'u2');
    expect(cal.calendars, hasLength(1));
    expect(cal.all.map((e) => e.title), ['新账号的备忘']);
  });

  test('关闭时删除日历；没有权限时开启失败', () async {
    await exporter.enable();
    await exporter.reconcile([memo('a')], owner: 'u1');
    await exporter.disable();
    expect(exporter.enabled, isFalse);
    expect(cal.calendars, isEmpty);
    expect(await db.select(db.calendarLinks).get(), isEmpty);

    cal
      ..granted = false
      ..grantOnRequest = false;
    expect(await exporter.enable(), isFalse);
    expect(exporter.enabled, isFalse);
  });

  test('退出登录时删除日历但保留开关；收回权限后不再写入', () async {
    await exporter.enable();
    await exporter.reconcile([memo('a')], owner: 'u1');
    await exporter.clear();
    expect(cal.calendars, isEmpty);
    expect(exporter.enabled, isTrue);

    cal.granted = false;
    await exporter.reconcile([memo('a')], owner: 'u1');
    expect(cal.calendars, isEmpty);
  });
}
