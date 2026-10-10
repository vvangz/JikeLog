import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/sync/sync_providers.dart';
import '../auth/auth_controller.dart';
import '../consent/consent_controller.dart';
import '../memos/memo_models.dart';
import '../memos/memo_repository.dart';
import 'device_time_zone.dart';
import 'local_notifier.dart';
import 'push_client.dart';
import 'reminder_scheduler.dart';
import 'system_calendar.dart';

final localNotifierProvider = Provider<LocalNotifier>(
  (_) => PluginLocalNotifier(),
);

final pushClientProvider = Provider<PushClient>(
  (_) => jpushAppKey.isEmpty
      ? const NoPushClient()
      : JPushClient(appKey: jpushAppKey),
);

final systemCalendarProvider = Provider<SystemCalendar>(
  (_) => PluginSystemCalendar(),
);

final deviceTimeZoneProvider = Provider<DeviceTimeZone>(
  (_) => const DeviceTimeZone(),
);

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(ref.watch(localNotifierProvider)),
);

final calendarExporterProvider = Provider<CalendarExporter>(
  (ref) => CalendarExporter(
    calendar: ref.watch(systemCalendarProvider),
    db: ref.watch(appDatabaseProvider),
    prefs: ref.watch(keyValueStoreProvider),
  ),
);

/// 提醒权限（null 表示尚未读取）。备忘录页的提示条与设置页使用。
final reminderPermissionsProvider =
    NotifierProvider<ReminderPermissionsController, ReminderPermissions?>(
      ReminderPermissionsController.new,
    );

class ReminderPermissionsController extends Notifier<ReminderPermissions?> {
  @override
  ReminderPermissions? build() => null;

  Future<ReminderPermissions> refresh() async {
    final p = await ref.read(localNotifierProvider).permissions();
    state = p;
    return p;
  }

  /// 请求通知与精确闹钟权限。精确闹钟需要用户在系统设置中打开，回到 App 时重新读取。
  Future<void> request() async {
    state = await ref.read(localNotifierProvider).requestPermissions();
    await ref.read(reminderCoordinatorProvider).registerPush();
  }

  @visibleForTesting
  void set(ReminderPermissions p) => state = p;
}

/// 按登录与隐私同意状态启停提醒：排定本地通知、登记推送、同步系统日历（ADR-008）。
final reminderCoordinatorProvider = Provider<ReminderCoordinator>((ref) {
  final c = ReminderCoordinator(ref);
  ref.onDispose(c.dispose);
  void update() => c.onState(
    ref.read(authControllerProvider),
    consented: ref.read(consentControllerProvider),
  );
  ref.listen(authControllerProvider, (_, _) => update());
  ref.listen(consentControllerProvider, (_, _) => update());
  update();
  return c;
});

class ReminderCoordinator {
  ReminderCoordinator(this._ref);

  final Ref _ref;
  static const _pushKey = 'push.registered';
  static const _debounce = Duration(milliseconds: 300);

  String? _userId;
  String _timeZone = fallbackTimeZone;
  StreamSubscription<List<Memo>>? _memos;
  List<Memo>? _latest;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Future<void> _queue = Future.value();

  /// 已排队的状态变化全部处理完毕（测试用）。
  @visibleForTesting
  Future<void> get idle => _queue;

  void onState(AuthState auth, {required bool consented}) {
    _queue = _queue.then((_) => _apply(auth, consented)).catchError((Object e) {
      debugPrint('启停提醒失败: $e');
    });
  }

  Future<void> _apply(AuthState auth, bool consented) async {
    switch (auth) {
      case SignedIn(:final user) when consented:
        if (_userId != user.id) await _start(user.id);
      case SignedOut(:final wipeLocalData):
        await _stop(wipe: wipeLocalData);
      default:
        break;
    }
  }

  Future<void> _start(String userId) async {
    await _stop(wipe: false);
    _userId = userId;
    _timeZone = await _ref.read(deviceTimeZoneProvider).current();
    final notifier = _ref.read(localNotifierProvider);
    await notifier.init(timeZone: _timeZone, onTap: _openPayload);
    final launched = await notifier.launchPayload();
    if (launched != null) _openPayload(launched);
    _memos = _ref.read(memoRepositoryProvider).watchAll().listen((memos) {
      _latest = memos;
      _timer?.cancel();
      _timer = Timer(_debounce, _reconcile);
    });
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_onResume()));
    await registerPush();
  }

  Future<void> _stop({required bool wipe}) async {
    final wasActive = _userId != null;
    _userId = null;
    _timer?.cancel();
    _timer = null;
    await _memos?.cancel();
    _memos = null;
    _latest = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    if (wasActive) await _ref.read(reminderSchedulerProvider).clear();
    if (wipe) {
      await _ref.read(calendarExporterProvider).clear();
      await _ref.read(keyValueStoreProvider).remove(_pushKey);
    }
  }

  void _reconcile() {
    final memos = _latest;
    if (memos == null || _userId == null) return;
    unawaited(_ref.read(reminderSchedulerProvider).reconcile(memos));
    unawaited(_ref.read(calendarExporterProvider).reconcile(memos));
  }

  /// 立即按最新数据重新排定（开启系统日历后调用）。
  void refresh() => _reconcile();

  Future<void> _onResume() async {
    if (_userId == null) return;
    final tz = await _ref.read(deviceTimeZoneProvider).current();
    if (tz != _timeZone) {
      // 换了时区：本地闹钟按新时区重新计算
      _timeZone = tz;
      await _ref
          .read(localNotifierProvider)
          .init(timeZone: tz, onTap: _openPayload);
      await _ref.read(localNotifierProvider).cancelAll();
    }
    _reconcile();
    await registerPush();
  }

  /// 向服务端登记推送标识与本地提醒能力；与上次登记相同则跳过，失败时下次回到前台再试。
  Future<void> registerPush() async {
    final userId = _userId;
    if (userId == null) return;
    final perms = await _ref
        .read(reminderPermissionsProvider.notifier)
        .refresh();
    final push = _ref.read(pushClientProvider);
    final token = await push.start(onOpen: _openMemo);
    final provider = token == null ? null : push.provider;
    final signature =
        '$userId|$provider|$token|$_timeZone|${perms.canRemindLocally}';
    final prefs = _ref.read(keyValueStoreProvider);
    if (prefs.getString(_pushKey) == signature) return;
    try {
      await _ref
          .read(accountApiProvider)
          .updatePush(
            provider: provider,
            token: token,
            timeZone: _timeZone,
            localReminders: perms.canRemindLocally,
          );
      if (_userId == userId) await prefs.setString(_pushKey, signature);
    } on Object catch (e) {
      debugPrint('登记推送失败，稍后重试: $e');
    }
  }

  void _openPayload(String payload) {
    final id = memoIdOfPayload(payload);
    if (id != null) _openMemo(id);
  }

  void _openMemo(String id) {
    if (_userId == null) return;
    unawaited(_ref.read(routerProvider).push('/memos/$id'));
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_memos?.cancel());
    _lifecycle?.dispose();
  }
}
