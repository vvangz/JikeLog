import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 提醒通知的 Android 渠道（与服务端推送使用同一渠道，见 server/internal/platform/pusher）。
const reminderChannelId = 'memo_reminders';

/// 其他通知的渠道 ID。
const generalChannelId = 'general';
const reminderChannelName = '备忘提醒';

/// 默认时区：读取设备时区失败时使用。
const fallbackTimeZone = 'Asia/Shanghai';

/// 提醒相关的权限状态。
@immutable
class ReminderPermissions {
  const ReminderPermissions({required this.notifications, required this.exact});

  static const none = ReminderPermissions(notifications: false, exact: false);

  /// 允许显示通知（Android 13 起需要授权）。
  final bool notifications;

  /// 允许精确闹钟（Android 12 起需要授权，否则提醒可能延后数分钟）。
  final bool exact;

  /// 本机能按时弹出提醒：服务端据此决定是否还要推送（ADR-008）。
  bool get canRemindLocally => notifications && exact;

  @override
  bool operator ==(Object other) =>
      other is ReminderPermissions &&
      other.notifications == notifications &&
      other.exact == exact;

  @override
  int get hashCode => Object.hash(notifications, exact);
}

/// 一条待排定的本地通知。
@immutable
class PlannedAlarm {
  const PlannedAlarm({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// 点按通知时交还给 App；同时用于判断已排定的通知是否需要更新。
  final String payload;
}

/// 本地通知（flutter_local_notifications 的封装，测试中替换为假实现）。
abstract class LocalNotifier {
  /// 初始化插件并创建通知渠道。[onTap] 在用户点按通知时调用，参数为 payload。
  Future<void> init({
    required String timeZone,
    required void Function(String payload) onTap,
  });

  /// 用户点按通知启动了 App 时，返回该通知的 payload。
  Future<String?> launchPayload();

  Future<ReminderPermissions> permissions();

  /// 请求通知权限，并在需要时打开系统的精确闹钟设置页。
  Future<ReminderPermissions> requestPermissions();

  /// 已排定的通知：id → payload。
  Future<Map<int, String?>> pending();

  Future<void> schedule(PlannedAlarm alarm, {required bool exact});

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

/// 基于 flutter_local_notifications 的实现。
class PluginLocalNotifier implements LocalNotifier {
  PluginLocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      reminderChannelId,
      reminderChannelName,
      channelDescription: '备忘录的提前提醒',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      // 锁屏时不显示备忘内容（通知标题是备忘的第一行）
      visibility: NotificationVisibility.private,
    ),
  );

  @override
  Future<void> init({
    required String timeZone,
    required void Function(String payload) onTap,
  }) async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(timeZone));
    } on Object {
      tz.setLocalLocation(tz.getLocation(fallbackTimeZone));
    }
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null) onTap(p);
      },
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        reminderChannelId,
        reminderChannelName,
        description: '备忘录的提前提醒',
        importance: Importance.high,
      ),
    );
    // 服务端推送的其他通知（如数据导出完成）使用的渠道，ID 与服务端 pusher.ChannelGeneral 一致
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        generalChannelId,
        '其他通知',
        description: '数据导出完成等通知',
      ),
    );
    _ready = true;
  }

  @override
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return d?.didNotificationLaunchApp == true
        ? d?.notificationResponse?.payload
        : null;
  }

  @override
  Future<ReminderPermissions> permissions() async {
    final android = _android;
    if (android == null) return ReminderPermissions.none;
    return ReminderPermissions(
      notifications: await android.areNotificationsEnabled() ?? false,
      exact: await android.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<ReminderPermissions> requestPermissions() async {
    final android = _android;
    if (android == null) return ReminderPermissions.none;
    await android.requestNotificationsPermission();
    if (await android.canScheduleExactNotifications() != true) {
      await android.requestExactAlarmsPermission();
    }
    return permissions();
  }

  @override
  Future<Map<int, String?>> pending() async => {
    for (final p in await _plugin.pendingNotificationRequests())
      p.id: p.payload,
  };

  @override
  Future<void> schedule(PlannedAlarm alarm, {required bool exact}) async {
    try {
      await _plugin.zonedSchedule(
        id: alarm.id,
        title: alarm.title,
        body: alarm.body,
        scheduledDate: tz.TZDateTime.from(alarm.at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: alarm.payload,
      );
    } on PlatformException catch (e) {
      // 权限在排定前被收回：退回非精确闹钟
      if (!exact) rethrow;
      debugPrint('精确闹钟不可用，改用非精确闹钟: $e');
      await schedule(alarm, exact: false);
    }
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAllPendingNotifications();
}
