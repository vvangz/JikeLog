import 'dart:async';

import 'package:flutter/foundation.dart';

import '../memos/memo_models.dart';
import 'local_notifier.dart';

/// 最多排定的本地提醒数：只排最近的这些（Android 单个应用最多约 500 个闹钟）。
const maxPlannedAlarms = 64;

/// 通知标题的最大字数。
const _maxTitle = 60;

/// 字符串的稳定哈希（FNV-1a，31 位）：每次运行结果相同（Object.hash 不保证）。
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// 一条备忘的某个提醒对应的通知 ID：由备忘 ID 与提前量稳定地算出。
int alarmId(String memoId, int offset) => stableHash('$memoId:$offset');

/// 通知 payload 中的备忘 ID（payload 格式见 [planAlarms]）。
String? memoIdOfPayload(String payload) {
  final id = payload.split('|').first;
  return id.isEmpty ? null : id;
}

/// 计算应当排定的本地提醒：未完成备忘尚未到时的提醒，按时间取最近的 [limit] 条。
/// payload 含备忘 ID、提前量、时刻与内容摘要，任何一项变化都会重新排定。
List<PlannedAlarm> planAlarms(
  List<Memo> memos,
  DateTime now, {
  int limit = maxPlannedAlarms,
}) {
  final out = <PlannedAlarm>[];
  for (final m in memos) {
    if (m.done) continue;
    for (final offset in m.reminders) {
      final at = m.at.subtract(Duration(minutes: offset));
      if (!at.isAfter(now)) continue;
      final title = m.title.length > _maxTitle
          ? '${m.title.substring(0, _maxTitle)}…'
          : m.title;
      out.add(
        PlannedAlarm(
          id: alarmId(m.id, offset),
          at: at,
          title: title,
          body: alarmBody(m, offset),
          payload:
              '${m.id}|$offset|${at.millisecondsSinceEpoch}|'
              '${stableHash('$title|${m.allDay}|${m.at.millisecondsSinceEpoch}')}',
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// 通知正文：备忘时间，提前提醒时注明提前量。
String alarmBody(Memo m, int offset) {
  final date = '${m.at.month}月${m.at.day}日';
  final time =
      '${m.at.hour.toString().padLeft(2, '0')}:'
      '${m.at.minute.toString().padLeft(2, '0')}';
  final when = m.allDay ? '$date 全天' : '$date $time';
  return offset == 0
      ? when
      : '$when · ${reminderLabel(offset, allDay: m.allDay)}';
}

/// 本地闹钟覆盖到的时刻：排满 [maxPlannedAlarms] 条时为最后一条的时刻（更晚的提醒由服务端推送），
/// 否则为 null（全部覆盖）。
DateTime? coverageOf(List<PlannedAlarm> plan, {int limit = maxPlannedAlarms}) =>
    plan.length >= limit ? plan.last.at : null;

/// 让本机已排定的通知与备忘录保持一致：多删少补，未变化的不动。
class ReminderScheduler {
  ReminderScheduler(this.notifier, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LocalNotifier notifier;
  final DateTime Function() _now;
  Future<void> _queue = Future.value();

  /// 最近一次排定后本地闹钟覆盖到的时刻（见 [coverageOf]）。
  DateTime? coverage;

  /// 按最新的备忘录重新排定。多次调用按顺序执行。
  Future<void> reconcile(List<Memo> memos) =>
      _queue = _queue.then((_) => _reconcile(memos)).catchError((Object e) {
        debugPrint('排定本地提醒失败: $e');
      });

  Future<void> _reconcile(List<Memo> memos) async {
    final perms = await notifier.permissions();
    final plan = planAlarms(memos, _now());
    final pending = await notifier.pending();
    final wanted = {for (final a in plan) a.id};
    for (final id in pending.keys) {
      if (!wanted.contains(id)) await notifier.cancel(id);
    }
    var failed = false;
    for (final a in plan) {
      if (pending[a.id] == a.payload) continue;
      try {
        await notifier.schedule(a, exact: perms.exact);
      } on Object catch (e) {
        // 一条失败不影响其他提醒；失败的那条下次排定时重试
        failed = true;
        debugPrint('排定提醒 ${a.id} 失败: $e');
      }
    }
    // 有提醒没排上时，不能再声称本地全部覆盖：服务端会照常推送
    coverage = failed
        ? (plan.isEmpty ? null : plan.first.at)
        : coverageOf(plan);
  }

  /// 取消全部提醒（退出登录时）。
  Future<void> clear() =>
      _queue = _queue.then((_) => notifier.cancelAll()).catchError((Object e) {
        debugPrint('取消本地提醒失败: $e');
      });
}
