import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/ledger/ledger_models.dart';
import 'package:jikelog/features/memos/memo_models.dart';
import 'package:jikelog/features/notes/note_models.dart';
import 'package:jikelog/features/overview/overview_cards.dart';
import 'package:jikelog/features/overview/overview_providers.dart';
import 'package:jikelog/features/overview/overview_stats.dart';
import 'package:jikelog/features/worklog/worklog_repository.dart';

/// 2026-10-27 是周二。
final _now = DateTime(2026, 10, 27, 15, 30);

Worklog _log(DateTime date, [String id = '']) => Worklog(
  id: id.isEmpty ? date.toIso8601String() : id,
  date: date,
  location: '',
  content: '',
  updatedAt: date,
);

Memo _memo(String id, DateTime at, {bool done = false, bool allDay = false}) =>
    Memo(
      id: id,
      content: id,
      at: at,
      allDay: allDay,
      done: done,
      updatedAt: at,
    );

Note _note(String id, DateTime updatedAt, {bool favorite = false}) => Note(
  id: id,
  title: id,
  body: '',
  format: NoteFormat.markdown,
  updatedAt: updatedAt,
  favorite: favorite,
);

void main() {
  group('周起始', () {
    test('周一或周日开始', () {
      expect(weekStartOf(_now, 1), DateTime(2026, 10, 26));
      expect(weekStartOf(_now, 7), DateTime(2026, 10, 25));
      // 周日当天：周一开始时属于上一周，周日开始时就是当天
      expect(weekStartOf(DateTime(2026, 10, 25, 8), 1), DateTime(2026, 10, 19));
      expect(weekStartOf(DateTime(2026, 10, 25, 8), 7), DateTime(2026, 10, 25));
    });
  });

  group('工作日志', () {
    test('今天写了：从今天起算连续天数', () {
      final s = worklogSummary([
        _log(DateTime(2026, 10, 27)),
        _log(DateTime(2026, 10, 26)),
        _log(DateTime(2026, 10, 25)),
        _log(DateTime(2026, 10, 23)), // 中断
      ], _now);
      expect(s.streak, 3);
      expect(s.writtenToday, isTrue);
    });

    test('今天还没写：从昨天起算，不算中断', () {
      final s = worklogSummary([
        _log(DateTime(2026, 10, 26)),
        _log(DateTime(2026, 10, 25)),
      ], _now);
      expect(s.streak, 2);
      expect(s.writtenToday, isFalse);
    });

    test('昨天也没写：连续天数为 0', () {
      final s = worklogSummary([_log(DateTime(2026, 10, 25))], _now);
      expect(s.streak, 0);
      expect(worklogSummary(const [], _now).streak, 0);
    });

    test('本月篇数：同一天多篇分别计数，跨月不计', () {
      final s = worklogSummary([
        _log(DateTime(2026, 10, 1), 'a'),
        _log(DateTime(2026, 10, 1), 'b'),
        _log(DateTime(2026, 10, 27)),
        _log(DateTime(2026, 9, 30)),
        _log(DateTime(2025, 10, 5)),
      ], _now);
      expect(s.thisMonth, 3);
    });

    test('热力图：按周排列，最近一周在最后，今天之后为 -1', () {
      final s = worklogSummary(
        [
          _log(DateTime(2026, 10, 27), 'a'),
          _log(DateTime(2026, 10, 27), 'b'),
          _log(DateTime(2026, 10, 26)),
          _log(DateTime(2026, 10, 19)),
          _log(DateTime(2026, 1, 1)), // 范围之外
        ],
        _now,
        weeks: 3,
      );
      expect(s.heatmap, [
        [0, 0, 0, 0, 0, 0, 0], // 10-12 起
        [1, 0, 0, 0, 0, 0, 0], // 10-19 起
        [1, 2, -1, -1, -1, -1, -1], // 10-26 起
      ]);
    });

    test('热力图：周日开始', () {
      final s = worklogSummary(
        [_log(DateTime(2026, 10, 25))],
        _now,
        weeks: 1,
        weekStart: 7,
      );
      expect(s.heatmap, [
        [1, 0, 0, -1, -1, -1, -1],
      ]);
    });
  });

  group('备忘录', () {
    test('今日待办、之前的逾期与本周完成率', () {
      final s = memoSummary([
        _memo('上午会议', DateTime(2026, 10, 27, 9)), // 今天已过时间：计入今日待办
        _memo('晚上', DateTime(2026, 10, 27, 20)),
        _memo('今天已完成', DateTime(2026, 10, 27, 8), done: true),
        _memo('昨天', DateTime(2026, 10, 26, 10)), // 逾期，属于本周
        _memo('上周', DateTime(2026, 10, 20, 10)), // 逾期，不属于本周
        _memo('下周', DateTime(2026, 11, 3, 10)),
      ], _now);
      expect(s.today, 2);
      expect(s.overdue, 2);
      expect(s.weekTotal, 4);
      expect(s.weekDone, 1);
      expect(s.weekRate, 0.25);
    });

    test('接下来：未完成、未过时，按时间先后，最多 3 条', () {
      final s = memoSummary([
        _memo('d', DateTime(2026, 11, 3, 10)),
        _memo('过时', DateTime(2026, 10, 27, 9)),
        _memo('b', DateTime(2026, 10, 27, 20)),
        _memo('全天', allDayAt(DateTime(2026, 10, 27)), allDay: true),
        _memo('c', DateTime(2026, 10, 28, 8)),
        _memo('完成', DateTime(2026, 10, 27, 21), done: true),
      ], _now);
      expect(s.upcoming.map((m) => m.id), ['全天', 'b', 'c']);
    });

    test('本周没有备忘：完成率为空', () {
      expect(memoSummary(const [], _now).weekRate, isNull);
    });

    test('时间说明', () {
      expect(
        memoWhen(_memo('a', DateTime(2026, 10, 27, 9, 5)), _now),
        '今天 09:05',
      );
      expect(
        memoWhen(
          _memo('b', allDayAt(DateTime(2026, 10, 28)), allDay: true),
          _now,
        ),
        '明天 全天',
      );
      expect(
        memoWhen(_memo('c', DateTime(2026, 10, 29, 14)), _now),
        '后天 14:00',
      );
      expect(
        memoWhen(_memo('d', DateTime(2026, 11, 3, 8)), _now),
        '11月3日 08:00',
      );
      expect(
        memoWhen(_memo('e', DateTime(2027, 1, 2, 8)), _now),
        '2027年1月2日 08:00',
      );
    });
  });

  group('笔记', () {
    test('总数、近 7 天编辑、收藏、最近编辑', () {
      final s = noteSummary([
        _note('旧', DateTime(2026, 9, 1), favorite: true),
        _note('新', DateTime(2026, 10, 27, 15)),
        _note('中', DateTime(2026, 10, 22)),
        _note('边界外', DateTime(2026, 10, 20, 15)),
      ], _now);
      expect(s.total, 4);
      expect(s.recentlyEdited, 2);
      expect(s.favorites, 1);
      expect(s.recent.map((n) => n.id), ['新', '中', '边界外']);
    });
  });

  group('记账', () {
    test('本月收支、近 30 天每日支出、净资产', () {
      Entry e(String id, EntryType type, int amount, DateTime date) => Entry(
        id: id,
        type: type,
        amount: amount,
        date: date,
        accountId: 'cash',
        categoryId: 'c',
      );
      final s = ledgerSummary(
        const [
          Account(
            id: 'cash',
            name: '现金',
            type: AccountType.cash,
            initialBalance: 10000,
          ),
        ],
        const [],
        [
          e('1', EntryType.income, 50000, DateTime(2026, 10, 1)),
          e('2', EntryType.expense, 1200, DateTime(2026, 10, 27)),
          e('3', EntryType.expense, 800, DateTime(2026, 9, 28)), // 上月，但在 30 天内
          e('4', EntryType.expense, 999, DateTime(2026, 9, 1)), // 30 天外
        ],
        _now,
      );
      expect(s.month.income, 50000);
      expect(s.month.expense, 1200);
      expect(s.daily, hasLength(30));
      expect(s.daily.last, 1200);
      expect(s.daily.first, 800); // 9 月 28 日
      expect(s.daily.fold(0, (a, b) => a + b), 2000);
      expect(s.netWorth.total, 10000 + 50000 - 1200 - 800 - 999);
      expect(s.hasData, isTrue);
      expect(
        ledgerSummary(const [], const [], const [], _now).hasData,
        isFalse,
      );
    });
  });

  group('文案', () {
    test('问候语按时段', () {
      expect(greetingFor(DateTime(2026, 1, 1, 4)), '晚上好');
      expect(greetingFor(DateTime(2026, 1, 1, 5)), '早上好');
      expect(greetingFor(DateTime(2026, 1, 1, 11)), '中午好');
      expect(greetingFor(DateTime(2026, 1, 1, 13)), '下午好');
      expect(greetingFor(DateTime(2026, 1, 1, 18)), '晚上好');
    });

    test('相对时间', () {
      expect(
        relativeTime(_now.subtract(const Duration(seconds: 20)), _now),
        '刚刚',
      );
      expect(
        relativeTime(_now.subtract(const Duration(minutes: 5)), _now),
        '5 分钟前',
      );
      expect(
        relativeTime(_now.subtract(const Duration(hours: 3)), _now),
        '3 小时前',
      );
      expect(relativeTime(DateTime(2026, 10, 26, 23), _now), '昨天');
      expect(relativeTime(DateTime(2026, 10, 2), _now), '10月2日');
      expect(relativeTime(DateTime(2025, 12, 31), _now), '2025年12月31日');
    });
  });
}
