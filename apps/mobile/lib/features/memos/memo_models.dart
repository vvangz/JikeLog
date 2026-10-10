import 'package:flutter/foundation.dart';

import '../../core/sync/record_store.dart';

/// 备忘内容上限（与服务端一致）。
const maxMemoLength = 5000;

/// 一条备忘最多设置的提醒数，以及最长提前量（30 天，与服务端一致）。
const maxReminders = 5;
const maxReminderMinutes = 30 * 24 * 60;

/// 全天备忘的提醒从当天 9:00 往前算（ADR-008）。
const allDayAnchorHour = 9;

/// 常用的提前提醒（分钟）。
const reminderPresets = <int>[0, 5, 15, 60, 1440];

/// 一条备忘。
@immutable
class Memo {
  const Memo({
    required this.id,
    required this.content,
    required this.at,
    required this.updatedAt,
    this.allDay = false,
    this.reminders = const [],
    this.done = false,
    this.pending = false,
    this.hasConflict = false,
    this.syncError,
  });

  factory Memo.fromRecord(LocalRecord r) => Memo(
    id: r.id,
    content: r.fields['content'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch(r.fields['at'] as int? ?? 0),
    allDay: r.fields['allDay'] == 1,
    reminders: parseReminders(r.fields['reminders'] as String? ?? ''),
    done: r.fields['done'] == 1,
    updatedAt: r.updatedAt,
    pending: r.dirty,
    hasConflict: r.hasConflict,
    syncError: r.syncError,
  );

  final String id;
  final String content;

  /// 备忘时间（本地时间）。全天备忘为当天 9:00。
  final DateTime at;
  final bool allDay;

  /// 提前提醒的分钟数，升序。
  final List<int> reminders;
  final bool done;
  final DateTime updatedAt;
  final bool pending;
  final bool hasConflict;
  final String? syncError;

  /// 所在日期（本地）。
  DateTime get day => dateOnly(at);

  /// 第一行，用作标题。
  String get title {
    final line = content.trimLeft().split('\n').first.trim();
    return line.isEmpty ? '（空白备忘）' : line;
  }

  /// 各提醒的时刻，与 [reminders] 一一对应。
  List<DateTime> get fireTimes => [
    for (final m in reminders) at.subtract(Duration(minutes: m)),
  ];

  /// 已经过了备忘时间且未完成（全天备忘过了当天才算）。
  bool overdue(DateTime now) =>
      !done && (allDay ? day.isBefore(dateOnly(now)) : at.isBefore(now));

  @override
  bool operator ==(Object other) =>
      other is Memo &&
      other.id == id &&
      other.content == content &&
      other.at == at &&
      other.allDay == allDay &&
      listEquals(other.reminders, reminders) &&
      other.done == done &&
      other.updatedAt == updatedAt &&
      other.pending == pending &&
      other.hasConflict == hasConflict &&
      other.syncError == syncError;

  @override
  int get hashCode => Object.hash(
    id,
    content,
    at,
    allDay,
    Object.hashAll(reminders),
    done,
    updatedAt,
    pending,
    hasConflict,
    syncError,
  );
}

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// 全天备忘在某天的时刻（9:00）。
DateTime allDayAt(DateTime day) =>
    DateTime(day.year, day.month, day.day, allDayAnchorHour);

/// 提醒列表的规范形式：升序、不重复、逗号分隔（服务端只接受这种写法）。
String encodeReminders(Iterable<int> minutes) {
  final sorted = minutes.toSet().toList()..sort();
  return sorted.join(',');
}

/// 解析提醒列表，忽略无法识别的部分。
List<int> parseReminders(String s) {
  if (s.isEmpty) return const [];
  final out = <int>{};
  for (final p in s.split(',')) {
    final n = int.tryParse(p);
    if (n != null && n >= 0 && n <= maxReminderMinutes) out.add(n);
  }
  return out.toList()..sort();
}

/// 提醒的显示文字。
String reminderLabel(int minutes, {bool allDay = false}) {
  if (minutes == 0) return allDay ? '当天 9:00' : '准时';
  if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
  if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
  return '提前 $minutes 分钟';
}

/// 新建备忘的默认时间：下一个整点。
DateTime defaultMemoTime(DateTime now) =>
    DateTime(now.year, now.month, now.day, now.hour + 1);
