import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/db/database.dart';
import '../../core/storage/stores.dart';
import '../memos/memo_models.dart';

/// 系统日历中由 App 创建的日历名称。
const systemCalendarName = '即刻日志';

/// 写入系统日历的时间范围：过去 30 天到未来 1 年（ADR-008）。
const _pastWindow = Duration(days: 30);
const _futureWindow = Duration(days: 366);

/// 非全天备忘在系统日历中的时长。
const _eventDuration = Duration(minutes: 30);

/// 系统日历中的一条事件。
@immutable
class CalendarEventData {
  const CalendarEventData({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// 用于判断事件是否需要更新。
  String get signature =>
      '$title|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|$allDay';
}

/// 系统日历（device_calendar_plus 的封装，测试中替换为假实现）。
abstract class SystemCalendar {
  /// 请求日历读写权限，返回是否已授权。
  Future<bool> requestAccess();

  Future<bool> hasAccess();

  /// 日历是否仍然存在（用户可能在系统日历中删掉了它）。
  Future<bool> exists(String calendarId);

  /// 在本机账户下创建日历，返回 ID。
  Future<String> createCalendar(String name);

  Future<void> deleteCalendar(String calendarId);

  Future<String> createEvent(String calendarId, CalendarEventData e);

  Future<void> updateEvent(String eventId, CalendarEventData e);

  Future<void> deleteEvent(String eventId);
}

class PluginSystemCalendar implements SystemCalendar {
  DeviceCalendar get _cal => DeviceCalendar.instance;

  @override
  Future<bool> requestAccess() async =>
      await _cal.requestPermissions() == CalendarPermissionStatus.granted;

  @override
  Future<bool> hasAccess() async =>
      await _cal.hasPermissions() == CalendarPermissionStatus.granted;

  @override
  Future<bool> exists(String calendarId) async =>
      (await _cal.listCalendars()).any((c) => c.id == calendarId);

  @override
  Future<String> createCalendar(String name) =>
      _cal.createCalendar(name: name, colorHex: '#6F4E37');

  @override
  Future<void> deleteCalendar(String calendarId) =>
      _cal.deleteCalendar(calendarId);

  @override
  Future<String> createEvent(String calendarId, CalendarEventData e) =>
      _cal.createEvent(
        calendarId: calendarId,
        title: e.title,
        startDate: e.start,
        endDate: e.end,
        isAllDay: e.allDay,
        // 不带闹钟：提醒由 App 负责，避免重复
        reminders: const [],
      );

  @override
  Future<void> updateEvent(String eventId, CalendarEventData e) =>
      _cal.updateEvent(
        instanceId: eventId,
        title: e.title,
        startDate: e.start,
        endDate: e.end,
        isAllDay: e.allDay,
      );

  @override
  Future<void> deleteEvent(String eventId) =>
      _cal.deleteEvent(instanceId: eventId);
}

/// 备忘在系统日历中对应的事件。
CalendarEventData eventOf(Memo m) {
  final title = m.done ? '✓ ${m.title}' : m.title;
  if (m.allDay) {
    return CalendarEventData(
      title: title,
      start: m.day,
      // 按日历日加一天（不用 24 小时，跨夏令时切换也正确）
      end: DateTime(m.day.year, m.day.month, m.day.day + 1),
      allDay: true,
    );
  }
  return CalendarEventData(
    title: title,
    start: m.at,
    end: m.at.add(_eventDuration),
    allDay: false,
  );
}

/// 把备忘录单向写入系统日历中的"即刻日志"日历（按设备开启，ADR-008）。
class CalendarExporter {
  CalendarExporter({
    required this.calendar,
    required this.db,
    required this.prefs,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SystemCalendar calendar;
  final AppDatabase db;
  final KeyValueStore prefs;
  final DateTime Function() _now;
  Future<void> _queue = Future.value();

  static const _enabledKey = 'calendar.export.enabled';
  static const _calendarKey = 'calendar.export.id';

  /// 日历中的事件属于哪个账号：换了账号登录时整个日历重建。
  static const _ownerKey = 'calendar.export.owner';

  bool get enabled => prefs.getString(_enabledKey) == '1';

  /// 开启：请求权限并创建日历。没有获得权限时返回 false。
  Future<bool> enable() async {
    if (!await calendar.requestAccess()) return false;
    await prefs.setString(_enabledKey, '1');
    return true;
  }

  /// 关闭：删除整个"即刻日志"日历与对应关系。
  Future<void> disable() => _serial(() async {
    await prefs.remove(_enabledKey);
    await _dropCalendar();
  });

  /// 按最新的备忘录同步系统日历（[owner] 为当前账号）。未开启或没有权限时不做任何事。
  Future<void> reconcile(List<Memo> memos, {required String owner}) =>
      _serial(() async {
        if (!enabled || !await calendar.hasAccess()) return;
        final calendarId = await _ensureCalendar(owner);
        final now = _now();
        final wanted = {
          for (final m in memos)
            if (m.at.isAfter(now.subtract(_pastWindow)) &&
                m.at.isBefore(now.add(_futureWindow)))
              m.id: eventOf(m),
        };
        final links = {
          for (final l in await db.select(db.calendarLinks).get()) l.memoId: l,
        };
        for (final l in links.values) {
          if (wanted.containsKey(l.memoId)) continue;
          await _ignoreMissing(() => calendar.deleteEvent(l.eventId));
          await (db.delete(
            db.calendarLinks,
          )..where((t) => t.memoId.equals(l.memoId))).go();
        }
        for (final MapEntry(key: memoId, value: e) in wanted.entries) {
          final link = links[memoId];
          if (link?.signature == e.signature) continue;
          var eventId = link?.eventId;
          if (eventId != null) {
            final updated = await _ignoreMissing(
              () => calendar.updateEvent(eventId!, e),
            );
            if (!updated) eventId = null; // 用户在系统日历中删掉了事件：重新创建
          }
          eventId ??= await calendar.createEvent(calendarId, e);
          await db
              .into(db.calendarLinks)
              .insertOnConflictUpdate(
                CalendarLinksCompanion.insert(
                  memoId: memoId,
                  eventId: eventId,
                  signature: e.signature,
                ),
              );
        }
      });

  /// 退出登录时删除日历（其中是该账号的备忘）。开关保留，重新登录后重建。
  Future<void> clear() => _serial(() async {
    if (await calendar.hasAccess()) await _dropCalendar();
  });

  Future<String> _ensureCalendar(String owner) async {
    final saved = prefs.getString(_calendarKey);
    if (saved != null && await calendar.exists(saved)) {
      if (prefs.getString(_ownerKey) == owner) return saved;
      // 换了账号：其中是上一个账号的备忘，无从对应，整个日历重建
      await _ignoreMissing(() => calendar.deleteCalendar(saved));
    }
    // 日历不存在了（首次开启，或被用户删除）：之前的对应关系全部作废
    await db.delete(db.calendarLinks).go();
    final id = await calendar.createCalendar(systemCalendarName);
    await prefs.setString(_calendarKey, id);
    await prefs.setString(_ownerKey, owner);
    return id;
  }

  Future<void> _dropCalendar() async {
    final id = prefs.getString(_calendarKey);
    if (id != null) await _ignoreMissing(() => calendar.deleteCalendar(id));
    await prefs.remove(_calendarKey);
    await prefs.remove(_ownerKey);
    await db.delete(db.calendarLinks).go();
  }

  /// 执行操作；目标已不存在时忽略并返回 false。其他错误（权限、系统日历忙）照常抛出，
  /// 对应关系保持不变，下次同步时重试——不能当作"不存在"而重复创建事件。
  static Future<bool> _ignoreMissing(Future<void> Function() op) async {
    try {
      await op();
      return true;
    } on DeviceCalendarException catch (e) {
      if (e.errorCode == DeviceCalendarError.notFound) return false;
      rethrow;
    }
  }

  Future<void> _serial(Future<void> Function() op) =>
      _queue = _queue.then((_) => op()).catchError((Object e) {
        debugPrint('同步系统日历失败: $e');
      });
}
