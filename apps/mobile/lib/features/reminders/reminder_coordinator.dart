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

/// 备忘 ID 的格式（UUID）：通知中带来的 ID 只有符合格式才用于打开页面。
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

class ReminderCoordinator {
  ReminderCoordinator(this._ref);

  final Ref _ref;
  static const _pushKey = 'push.registered';
  static const _debounce = Duration(milliseconds: 300);

  /// 启动 App 的那条通知只处理一次（插件在整个进程内都会返回它）。
  static bool _launchHandled = false;

  @visibleForTesting
  static void resetLaunchForTesting() => _launchHandled = false;

  String? _userId;

  /// 每次启停加一：异步操作在 await 之后发现它变了，说明已退出或换了账号，立即停止。
  int _generation = 0;
  bool _disposed = false;
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

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> _apply(AuthState auth, bool consented) async {
    if (_disposed) return;
    switch (auth) {
      case SignedIn(:final user) when consented:
        if (_userId != user.id) await _start(user.id);
      case SignedOut(:final wipeLocalData):
        await _stop(wipe: wipeLocalData);
        // 下次登录是新的设备会话（服务端已清除旧会话的推送登记），必须重新登记
        await _ref.read(keyValueStoreProvider).remove(_pushKey);
      default:
        break;
    }
  }

  Future<void> _start(String userId) async {
    await _stop(wipe: false);
    final gen = ++_generation;
    _userId = userId;
    _timeZone = await _ref.read(deviceTimeZoneProvider).current();
    if (!_current(gen)) return;
    final notifier = _ref.read(localNotifierProvider);
    await notifier.init(timeZone: _timeZone, onTap: _openPayload);
    if (!_current(gen)) return;
    if (!_launchHandled) {
      _launchHandled = true;
      final launched = await notifier.launchPayload();
      if (launched != null && _current(gen)) _openPayload(launched);
    }
    _memos = _ref.read(memoRepositoryProvider).watchAll().listen((memos) {
      _latest = memos;
      _timer?.cancel();
      _timer = Timer(_debounce, () => unawaited(_reconcile(gen)));
    });
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_onResume()));
    // 不等待：取推送标识可能要十几秒，不能挡住随后的退出登录
    unawaited(registerPush());
  }

  Future<void> _stop({required bool wipe}) async {
    final wasActive = _userId != null;
    _generation++;
    _userId = null;
    _timer?.cancel();
    _timer = null;
    await _memos?.cancel();
    _memos = null;
    _latest = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    if (_disposed) return;
    if (wasActive) await _ref.read(reminderSchedulerProvider).clear();
    if (wipe) await _ref.read(calendarExporterProvider).clear();
  }

  Future<void> _reconcile(int gen) async {
    final memos = _latest;
    final userId = _userId;
    if (memos == null || userId == null || !_current(gen)) return;
    final scheduler = _ref.read(reminderSchedulerProvider);
    final before = scheduler.coverage;
    unawaited(
      _ref.read(calendarExporterProvider).reconcile(memos, owner: userId),
    );
    await scheduler.reconcile(memos);
    // 本地闹钟覆盖的范围变了：告诉服务端，超出范围的提醒由它推送
    if (_current(gen) && scheduler.coverage != before) await registerPush();
  }

  /// 立即按最新数据重新排定（开启系统日历后调用）。
  void refresh() => unawaited(_reconcile(_generation));

  Future<void> _onResume() async {
    final gen = _generation;
    try {
      if (_userId == null) return;
      final tz = await _ref.read(deviceTimeZoneProvider).current();
      if (!_current(gen)) return;
      if (tz != _timeZone) {
        // 换了时区：已排定的闹钟是绝对时刻，不受影响；只更新之后计算用的本地时区
        _timeZone = tz;
        await _ref
            .read(localNotifierProvider)
            .init(timeZone: tz, onTap: _openPayload);
      }
      if (!_current(gen)) return;
      await _reconcile(gen);
      await registerPush();
    } on Object catch (e) {
      debugPrint('回到前台时更新提醒失败: $e');
    }
  }

  /// 向服务端登记推送标识与本地提醒能力；与上次登记相同则跳过，失败时下次回到前台再试。
  Future<void> registerPush() async {
    final userId = _userId;
    final gen = _generation;
    if (userId == null) return;
    try {
      final perms = await _ref
          .read(reminderPermissionsProvider.notifier)
          .refresh();
      final push = _ref.read(pushClientProvider);
      final token = await push.start(onOpen: _openMemo);
      if (!_current(gen)) return;
      final provider = token == null ? null : push.provider;
      final local = perms.canRemindLocally;
      final until = local
          ? _ref.read(reminderSchedulerProvider).coverage
          : null;
      final signature =
          '$userId|$provider|$token|$_timeZone|$local|'
          '${until?.millisecondsSinceEpoch}';
      final prefs = _ref.read(keyValueStoreProvider);
      if (prefs.getString(_pushKey) == signature) return;
      await _ref
          .read(accountApiProvider)
          .updatePush(
            provider: provider,
            token: token,
            timeZone: _timeZone,
            localReminders: local,
            localUntil: until,
          );
      if (_current(gen)) await prefs.setString(_pushKey, signature);
    } on Object catch (e) {
      debugPrint('登记推送失败，稍后重试: $e');
    }
  }

  void _openPayload(String payload) {
    final id = memoIdOfPayload(payload);
    if (id != null) _openMemo(id);
  }

  void _openMemo(String id) {
    if (_userId == null || !_uuid.hasMatch(id)) return;
    final router = _ref.read(routerProvider);
    final path = '/memos/$id';
    // 正在编辑这条备忘时不再打开第二个编辑页
    if (router.state.matchedLocation == path) return;
    unawaited(router.push(path));
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _userId = null;
    _timer?.cancel();
    unawaited(_memos?.cancel());
    _lifecycle?.dispose();
  }
}
