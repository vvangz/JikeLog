/// 概览页的统计：全部由本地数据实时计算（纯函数，便于测试）。
library;

import 'package:flutter/foundation.dart';

import '../memos/memo_models.dart';
import '../notes/note_models.dart';
import '../worklog/worklog_repository.dart';

/// [day] 所在周的第一天；[weekStart] 为 1（周一）或 7（周日），与设置一致。
DateTime weekStartOf(DateTime day, int weekStart) {
  final d = dateOnly(day);
  final offset = (d.weekday - weekStart) % 7;
  return DateTime(d.year, d.month, d.day - offset);
}

/// 工作日志概况。
@immutable
class WorklogSummary {
  const WorklogSummary({
    required this.streak,
    required this.thisMonth,
    required this.writtenToday,
    required this.heatmap,
  });

  /// 连续记录的天数（今天还没写时从昨天起算）。
  final int streak;

  /// 本月的日志篇数。
  final int thisMonth;
  final bool writtenToday;

  /// 按周排列的每天篇数，最早的一周在前，每周 7 天从周起始日开始；今天之后为 -1。
  final List<List<int>> heatmap;
}

WorklogSummary worklogSummary(
  List<Worklog> logs,
  DateTime now, {
  int weeks = 26,
  int weekStart = 1,
}) {
  final today = dateOnly(now);
  final perDay = <DateTime, int>{};
  var thisMonth = 0;
  for (final w in logs) {
    final d = dateOnly(w.date);
    perDay[d] = (perDay[d] ?? 0) + 1;
    if (d.year == today.year && d.month == today.month) thisMonth++;
  }

  final writtenToday = perDay.containsKey(today);
  var streak = 0;
  var cur = writtenToday
      ? today
      : DateTime(today.year, today.month, today.day - 1);
  while (perDay.containsKey(cur)) {
    streak++;
    cur = DateTime(cur.year, cur.month, cur.day - 1);
  }

  final first = weekStartOf(today, weekStart);
  final heatmap = [
    for (var w = weeks - 1; w >= 0; w--)
      [
        for (var i = 0; i < 7; i++)
          switch (DateTime(first.year, first.month, first.day - w * 7 + i)) {
            final d when d.isAfter(today) => -1,
            final d => perDay[d] ?? 0,
          },
      ],
  ];
  return WorklogSummary(
    streak: streak,
    thisMonth: thisMonth,
    writtenToday: writtenToday,
    heatmap: heatmap,
  );
}

/// 备忘录概况。
@immutable
class MemoSummary {
  const MemoSummary({
    required this.today,
    required this.overdue,
    required this.weekDone,
    required this.weekTotal,
    required this.upcoming,
  });

  /// 今天未完成的备忘。
  final int today;

  /// 之前日期未完成的备忘（今天的计入 [today]）。
  final int overdue;

  /// 本周的备忘中已完成 / 全部。
  final int weekDone;
  final int weekTotal;

  /// 接下来未完成、未过时的备忘，按时间先后。
  final List<Memo> upcoming;

  /// 本周完成率；本周没有备忘时为 null。
  double? get weekRate => weekTotal == 0 ? null : weekDone / weekTotal;
}

MemoSummary memoSummary(
  List<Memo> memos,
  DateTime now, {
  int weekStart = 1,
  int upcomingLimit = 3,
}) {
  final today = dateOnly(now);
  final from = weekStartOf(today, weekStart);
  final to = DateTime(from.year, from.month, from.day + 7);
  var todayCount = 0;
  var overdue = 0;
  var weekDone = 0;
  var weekTotal = 0;
  final upcoming = <Memo>[];
  for (final m in memos) {
    final day = m.day;
    if (!day.isBefore(from) && day.isBefore(to)) {
      weekTotal++;
      if (m.done) weekDone++;
    }
    if (m.done) continue;
    if (day == today) {
      todayCount++;
    } else if (day.isBefore(today)) {
      overdue++;
    }
    if (!m.overdue(now)) upcoming.add(m);
  }
  upcoming.sort((a, b) => a.at.compareTo(b.at));
  return MemoSummary(
    today: todayCount,
    overdue: overdue,
    weekDone: weekDone,
    weekTotal: weekTotal,
    upcoming: upcoming.take(upcomingLimit).toList(),
  );
}

/// 笔记概况。
@immutable
class NoteSummary {
  const NoteSummary({
    required this.total,
    required this.recentlyEdited,
    required this.favorites,
    required this.recent,
  });

  final int total;

  /// 近 7 天编辑过的篇数。
  final int recentlyEdited;
  final int favorites;

  /// 最近编辑的几篇。
  final List<Note> recent;
}

NoteSummary noteSummary(List<Note> notes, DateTime now, {int recentLimit = 3}) {
  final since = now.subtract(const Duration(days: 7));
  final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return NoteSummary(
    total: notes.length,
    recentlyEdited: notes.where((n) => n.updatedAt.isAfter(since)).length,
    favorites: notes.where((n) => n.favorite).length,
    recent: sorted.take(recentLimit).toList(),
  );
}

/// 问候语（按时段）。
String greetingFor(DateTime now) => switch (now.hour) {
  >= 5 && < 11 => '早上好',
  >= 11 && < 13 => '中午好',
  >= 13 && < 18 => '下午好',
  _ => '晚上好',
};

/// 相对时间：刚刚 / N 分钟前 / N 小时前 / 昨天 / M月D日（跨年带年份）。
String relativeTime(DateTime t, DateTime now) {
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  final days = dateOnly(now).difference(dateOnly(t)).inDays;
  if (days == 0) return '${diff.inHours} 小时前';
  if (days == 1) return '昨天';
  if (t.year == now.year) return '${t.month}月${t.day}日';
  return '${t.year}年${t.month}月${t.day}日';
}
