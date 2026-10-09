import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../features/auth/auth_controller.dart';
import '../db/database.dart';
import 'hlc.dart';
import 'realtime.dart';
import 'record_store.dart';
import 'sync_api.dart';
import 'sync_engine.dart';

/// 本地数据库，启动时在 ProviderScope 中覆盖。
final appDatabaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError('appDatabaseProvider 需在启动时覆盖'),
);

/// 混合逻辑时钟，启动时从本地库恢复后覆盖。
final hybridClockProvider = Provider<HybridClock>(
  (_) => throw UnimplementedError('hybridClockProvider 需在启动时覆盖'),
);

final recordStoreProvider = Provider<RecordStore>(
  (ref) => RecordStore(
    ref.watch(appDatabaseProvider),
    ref.watch(hybridClockProvider),
  ),
);

final syncApiProvider = Provider<SyncApi>(
  (ref) => SyncApi(ref.watch(apiClientProvider)),
);

/// 同步传输，测试中可覆盖为内存服务端。
final syncTransportProvider = Provider<SyncTransport>(
  (ref) => ref.watch(syncApiProvider),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    transport: ref.watch(syncTransportProvider),
    store: ref.watch(recordStoreProvider),
    db: ref.watch(appDatabaseProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final engine = ref.watch(syncEngineProvider);
  yield engine.status;
  yield* engine.statusStream;
});

/// 尚未推送的本地修改数量。
final pendingChangesProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final count = db.records.id.count();
  final q = db.selectOnly(db.records)
    ..addColumns([count])
    ..where(db.records.dirty.equals(true));
  return q.map((row) => row.read(count) ?? 0).watchSingle();
});

/// 实时通知客户端；收到通知后触发同步。
final realtimeClientProvider = Provider<RealtimeLink>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final store = ref.watch(keyValueStoreProvider);
  final client = RealtimeClient(
    client: ref.watch(apiClientProvider),
    onChange: () => unawaited(engine.sync()),
    deviceId: () => store.getString(deviceIdKey),
    // 设备已下线：发起一次请求，由 ApiClient 的刷新逻辑把登录态切换为未登录
    onRevoked: () => unawaited(engine.sync()),
  );
  ref.onDispose(client.stop);
  return client;
});

/// 按登录状态启停同步：登录后立即同步并保持实时连接，回到前台时再同步一次；
/// 退出登录或切换账号时清空本地数据（数据只属于当时登录的账号）。
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final c = SyncCoordinator(ref);
  ref.onDispose(c.dispose);
  ref.listen(
    authControllerProvider,
    (_, next) => unawaited(c.onAuth(next)),
    fireImmediately: true,
  );
  return c;
});

class SyncCoordinator {
  SyncCoordinator(this._ref);

  final Ref _ref;
  static const _userKey = 'sync.userId';
  static const _interval = Duration(minutes: 5);

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _active = false;

  Future<void> onAuth(AuthState state) async {
    switch (state) {
      case SignedIn(:final user):
        await _start(user.id);
      case SignedOut():
        await _stop(wipe: true);
      case AuthLoading():
        break;
    }
  }

  Future<void> _start(String userId) async {
    final db = _ref.read(appDatabaseProvider);
    final owner = await db.meta(_userKey);
    if (owner != userId) {
      await db.wipe();
      await db.setMeta(_userKey, userId);
    }
    if (_active) return;
    _active = true;
    final engine = _ref.read(syncEngineProvider);
    final realtime = _ref.read(realtimeClientProvider);
    realtime.start();
    unawaited(engine.sync());
    _timer = Timer.periodic(_interval, (_) => unawaited(engine.sync()));
    _lifecycle = AppLifecycleListener(
      onResume: () {
        realtime.start();
        unawaited(engine.sync());
      },
      onPause: () => unawaited(realtime.stop()),
    );
  }

  Future<void> _stop({required bool wipe}) async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    await _ref.read(realtimeClientProvider).stop();
    _ref.read(syncApiProvider).reset();
    if (wipe) await _ref.read(appDatabaseProvider).wipe();
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
  }
}
