import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/memos/memo_models.dart';
import 'package:jikelog/features/reminders/local_notifier.dart';
import 'package:jikelog/features/reminders/reminder_scheduler.dart';

import '../../support/fake_reminders.dart';

void main() {
  final now = DateTime(2026, 10, 12, 8);
  Memo memo(
    String id, {
    required DateTime at,
    List<int> reminders = const [0],
    bool done = false,
    bool allDay = false,
    String content = '周会',
  }) => Memo(
    id: id,
    content: content,
    at: at,
    reminders: reminders,
    done: done,
    allDay: allDay,
    updatedAt: now,
  );

  group('planAlarms', () {
    test('只排未完成备忘尚未到时的提醒，按时间先后', () {
      final plan = planAlarms([
        memo('a', at: DateTime(2026, 10, 12, 9), reminders: [0, 30, 120]),
        memo('b', at: DateTime(2026, 10, 12, 8, 40)),
        memo('c', at: DateTime(2026, 10, 12, 10), done: true),
      ], now);
      expect(plan.map((a) => a.at), [
        DateTime(2026, 10, 12, 8, 30),
        DateTime(2026, 10, 12, 8, 40),
        DateTime(2026, 10, 12, 9),
      ]);
      expect(plan.first.title, '周会');
      expect(plan.first.body, '10月12日 09:00 · 提前 30 分钟');
      expect(memoIdOfPayload(plan.first.payload), 'a');
      expect(plan.map((a) => a.id).toSet(), hasLength(3));
    });

    test('只取最近的若干条；长标题截断；全天备忘的文字', () {
      final memos = [
        for (var i = 0; i < 10; i++)
          memo('m$i', at: now.add(Duration(hours: i + 1))),
      ];
      expect(planAlarms(memos, now, limit: 3).map((a) => a.id), [
        alarmId('m0', 0),
        alarmId('m1', 0),
        alarmId('m2', 0),
      ]);
      final long = planAlarms([
        memo('x', at: now.add(const Duration(hours: 1)), content: '长' * 80),
      ], now).single;
      expect(long.title, '${'长' * 60}…');
      final allDay = planAlarms([
        memo(
          'd',
          at: DateTime(2026, 10, 13, 9),
          allDay: true,
          reminders: [0, 1440],
        ),
      ], now);
      expect(allDay.map((a) => a.body), ['10月13日 全天 · 提前 1 天', '10月13日 全天']);
    });

    test('通知 ID 稳定且各不相同；内容变化改变 payload', () {
      expect(alarmId('a', 0), alarmId('a', 0));
      expect(alarmId('a', 0), isNot(alarmId('a', 15)));
      expect(alarmId('a', 0), greaterThanOrEqualTo(0));
      final p1 = planAlarms([memo('a', at: DateTime(2026, 10, 12, 9))], now);
      final p2 = planAlarms([
        memo('a', at: DateTime(2026, 10, 12, 9), content: '改了'),
      ], now);
      expect(p1.single.id, p2.single.id);
      expect(p1.single.payload, isNot(p2.single.payload));
      expect(memoIdOfPayload(''), isNull);
    });
  });

  group('ReminderScheduler', () {
    test('多删少补，未变化的不重新排定', () async {
      final n = FakeLocalNotifier();
      final s = ReminderScheduler(n, now: () => now);
      final a = memo('a', at: DateTime(2026, 10, 12, 9), reminders: [0, 15]);
      await s.reconcile([a]);
      expect(n.scheduled.values.map((x) => x.at), [
        DateTime(2026, 10, 12, 8, 45),
        DateTime(2026, 10, 12, 9),
      ]);
      expect(n.exactCalls, [true, true]);

      n.scheduleCount = 0;
      await s.reconcile([a]);
      expect(n.scheduleCount, 0, reason: '没有变化时不重新排定');

      await s.reconcile([
        memo('a', at: DateTime(2026, 10, 12, 9), reminders: [0]),
      ]);
      expect(n.scheduled.keys, [alarmId('a', 0)]);

      await s.reconcile([]);
      expect(n.scheduled, isEmpty);
    });

    test('没有精确闹钟权限时排定非精确闹钟；clear 取消全部', () async {
      final n = FakeLocalNotifier()
        ..perms = const ReminderPermissions(notifications: true, exact: false);
      final s = ReminderScheduler(n, now: () => now);
      await s.reconcile([memo('a', at: DateTime(2026, 10, 12, 9))]);
      expect(n.exactCalls, [false]);
      await s.clear();
      expect(n.scheduled, isEmpty);
    });

    test('出错时不影响后续调用', () async {
      final n = FakeLocalNotifier()..failPending = true;
      final s = ReminderScheduler(n, now: () => now);
      await s.reconcile([memo('a', at: DateTime(2026, 10, 12, 9))]);
      n.failPending = false;
      await s.reconcile([memo('a', at: DateTime(2026, 10, 12, 9))]);
      expect(n.scheduled, hasLength(1));
    });
  });
}
