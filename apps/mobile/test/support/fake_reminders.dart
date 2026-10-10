import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:jikelog/features/reminders/device_time_zone.dart';
import 'package:jikelog/features/reminders/local_notifier.dart';
import 'package:jikelog/features/reminders/push_client.dart';
import 'package:jikelog/features/reminders/system_calendar.dart';

/// 记录排定结果的本地通知。
class FakeLocalNotifier implements LocalNotifier {
  ReminderPermissions perms = const ReminderPermissions(
    notifications: true,
    exact: true,
  );

  /// requestPermissions 之后的权限。
  ReminderPermissions? afterRequest;
  final scheduled = <int, PlannedAlarm>{};
  final exactCalls = <bool>[];
  int scheduleCount = 0;
  int requestCount = 0;
  bool failPending = false;
  String? timeZone;
  String? launch;
  void Function(String payload)? onTap;

  @override
  Future<void> init({
    required String timeZone,
    required void Function(String payload) onTap,
  }) async {
    this.timeZone = timeZone;
    this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async {
    final p = launch;
    launch = null;
    return p;
  }

  @override
  Future<ReminderPermissions> permissions() async => perms;

  @override
  Future<ReminderPermissions> requestPermissions() async {
    requestCount++;
    perms = afterRequest ?? perms;
    return perms;
  }

  @override
  Future<Map<int, String?>> pending() async {
    if (failPending) throw StateError('pending failed');
    return {for (final e in scheduled.entries) e.key: e.value.payload};
  }

  @override
  Future<void> schedule(PlannedAlarm alarm, {required bool exact}) async {
    scheduleCount++;
    exactCalls.add(exact);
    scheduled[alarm.id] = alarm;
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<void> cancelAll() async => scheduled.clear();
}

class FakePushClient implements PushClient {
  FakePushClient({this.token});

  String? token;
  int starts = 0;
  void Function(String memoId)? onOpen;

  @override
  String? get provider => 'jpush';

  @override
  Future<String?> start({required void Function(String memoId) onOpen}) async {
    starts++;
    this.onOpen = onOpen;
    return token;
  }
}

class FakeTimeZone extends DeviceTimeZone {
  FakeTimeZone([this.value = 'Asia/Shanghai']);

  String value;

  @override
  Future<String> current() async => value;
}

/// 内存中的系统日历。
class FakeSystemCalendar implements SystemCalendar {
  bool granted = true;
  bool grantOnRequest = true;
  final calendars = <String, String>{};
  final events = <String, (String, CalendarEventData)>{};
  var _seq = 0;

  @override
  Future<bool> requestAccess() async => granted = granted || grantOnRequest;

  @override
  Future<bool> hasAccess() async => granted;

  @override
  Future<bool> exists(String calendarId) async =>
      calendars.containsKey(calendarId);

  @override
  Future<String> createCalendar(String name) async {
    final id = 'cal-${++_seq}';
    calendars[id] = name;
    return id;
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    calendars.remove(calendarId);
    events.removeWhere((_, e) => e.$1 == calendarId);
  }

  @override
  Future<String> createEvent(String calendarId, CalendarEventData e) async {
    final id = 'ev-${++_seq}';
    events[id] = (calendarId, e);
    return id;
  }

  @override
  Future<void> updateEvent(String eventId, CalendarEventData e) async {
    final cur = events[eventId];
    if (cur == null) {
      throw const DeviceCalendarException(
        errorCode: DeviceCalendarError.notFound,
        message: 'missing',
      );
    }
    events[eventId] = (cur.$1, e);
  }

  @override
  Future<void> deleteEvent(String eventId) async => events.remove(eventId);

  List<CalendarEventData> get all => [for (final e in events.values) e.$2];
}
