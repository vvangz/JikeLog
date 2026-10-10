import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import '../db/database.dart';
import 'e2e.dart';
import 'record_store.dart';
import 'schema.dart';
import 'sync_api.dart';

/// 同步引擎需要的服务端能力（[SyncApi] 实现；测试中替换为内存服务端）。
abstract interface class SyncTransport {
  Future<T> withSession<T>(Future<T> Function(E2ESession s) call);
  Future<({List<PushResult> results, int cursor})> push(
    E2ESession s,
    List<Map<String, dynamic>> changes,
  );
  Future<PullPage> pull(E2ESession s, int since, {int limit});
  Future<void> ack(int seq);
}

enum SyncPhase { idle, syncing, offline, error }

@immutable
class SyncStatus {
  const SyncStatus(this.phase, {this.lastSyncedAt, this.message});

  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? message;
}

/// 推送本地修改并拉取其他设备的修改（ADR-005）。
class SyncEngine {
  SyncEngine({
    required this.transport,
    required this.store,
    required this.db,
    this.debounce = const Duration(seconds: 2),
  });

  final SyncTransport transport;
  final RecordStore store;
  final AppDatabase db;
  final Duration debounce;

  static const sinceKey = 'sync.since';
  static const _maxPushRounds = 20;

  final _status = StreamController<SyncStatus>.broadcast();
  SyncStatus _current = const SyncStatus(SyncPhase.idle);
  Future<void>? _running;
  bool _again = false;
  Timer? _timer;
  bool _disposed = false;
  bool _halted = false;

  SyncStatus get status => _current;
  Stream<SyncStatus> get statusStream => _status.stream;

  /// 本地修改后调用：防抖后同步，连续编辑只触发一次。
  void schedule() {
    if (_disposed || _halted) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(sync()));
  }

  /// 推送 + 拉取。运行期间再次调用会在本轮结束后再跑一轮，保证不漏掉新的修改或通知。
  Future<void> sync() {
    if (_disposed || _halted) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _once();
    } while (_again && !_disposed && !_halted);
  }

  Future<void> _once() async {
    _emit(SyncStatus(SyncPhase.syncing, lastSyncedAt: _current.lastSyncedAt));
    try {
      var attempt = 0;
      await transport.withSession((s) async {
        attempt++;
        await _pushAll(s);
        await _pullAll(s, retryCorrupt: attempt == 1);
      });
      _emit(SyncStatus(SyncPhase.idle, lastSyncedAt: DateTime.now()));
    } on ApiException catch (e) {
      _emit(
        SyncStatus(
          e.isNetwork ? SyncPhase.offline : SyncPhase.error,
          lastSyncedAt: _current.lastSyncedAt,
          message: e.message,
        ),
      );
    } on Object catch (e, st) {
      debugPrint('同步失败: $e\n$st');
      _emit(
        SyncStatus(
          SyncPhase.error,
          lastSyncedAt: _current.lastSyncedAt,
          message: '同步失败，请稍后重试',
        ),
      );
    }
  }

  Future<void> _pushAll(E2ESession s) async {
    for (var round = 0; round < _maxPushRounds; round++) {
      final pending = await store.pending();
      if (pending.isEmpty) return;
      final byId = {for (final c in pending) c.id: c};
      final wire = [for (final c in pending) await _encode(s, c)];
      final res = await transport.push(s, wire);
      for (final r in res.results) {
        final sent = byId.remove(r.id);
        if (sent != null) await _applyResult(s, sent, r);
      }
      // 服务端没有返回结果的变更留到下次同步，不在本轮反复推送
      if (byId.isNotEmpty) return;
    }
  }

  Future<void> _applyResult(
    E2ESession s,
    OutgoingChange sent,
    PushResult r,
  ) async {
    switch (r.status) {
      case 'applied':
        await store.markPushed(
          sent,
          version: r.version ?? 0,
          serverSeq: r.serverSeq ?? 0,
        );
      case 'merged' || 'conflict' when r.record != null:
        await store.applyRemote(
          await _decode(s, r.record!),
          conflict: r.status == 'conflict',
          sent: sent,
        );
      default:
        await store.markRejected(sent.id, r.errorCode ?? r.status);
    }
  }

  /// 拉取全部新记录。无法解密的记录：第一次先换新会话重试（[retryCorrupt]），
  /// 仍然失败则跳过这一条并照常推进游标，不能让一条坏记录卡住整个同步。
  Future<void> _pullAll(E2ESession s, {required bool retryCorrupt}) async {
    var since = int.tryParse(await db.meta(sinceKey) ?? '') ?? 0;
    final start = since;
    while (true) {
      final page = await transport.pull(s, since);
      for (final rec in page.records) {
        final RemoteRecord remote;
        try {
          remote = await _decode(s, rec);
        } on Object catch (e) {
          if (retryCorrupt) {
            throw const ApiException(
              code: ApiErrorCode.e2eSessionInvalid,
              message: '记录无法解密，重新建立加密会话',
            );
          }
          debugPrint('跳过无法解析的记录 ${rec['id']}: $e');
          continue;
        }
        await store.applyRemote(remote);
      }
      since = page.nextSince;
      await db.setMeta(sinceKey, '$since');
      if (!page.hasMore) break;
    }
    if (since != start) {
      try {
        await transport.ack(since);
      } on ApiException catch (e) {
        debugPrint('同步确认失败（下次再确认）: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _encode(E2ESession s, OutgoingChange c) async {
    if (c.deleted) return {'entity': c.entity, 'id': c.id, 'deleted': true};
    final fields = <String, Object?>{};
    for (final e in c.fields.entries) {
      final v = e.value;
      fields[e.key] = v is String && Entities.field(c.entity, e.key).sensitive
          ? await s.sealValue(c.entity, c.id, e.key, v)
          : v;
    }
    final patches = <String, String>{};
    for (final e in c.patches.entries) {
      patches[e.key] = Entities.field(c.entity, e.key).sensitive
          ? await s.sealPatch(c.entity, c.id, e.key, e.value)
          : e.value;
    }
    return {
      'entity': c.entity,
      'id': c.id,
      'fields': fields,
      'clocks': c.clocks,
      if (c.baseClocks.isNotEmpty) 'baseClocks': c.baseClocks,
      if (patches.isNotEmpty) 'patches': patches,
    };
  }

  Future<RemoteRecord> _decode(E2ESession s, Map<String, dynamic> j) async {
    final entity = j['entity'] as String;
    final id = j['id'] as String;
    final fields = <String, Object?>{};
    for (final e
        in (j['fields'] as Map<String, dynamic>? ?? const {}).entries) {
      final v = e.value;
      fields[e.key] = v is String && Entities.field(entity, e.key).sensitive
          ? await s.openValue(entity, id, e.key, v)
          : (v is num ? v.toInt() : v);
    }
    return RemoteRecord(
      entity: entity,
      id: id,
      version: (j['version'] as num).toInt(),
      serverSeq: (j['serverSeq'] as num).toInt(),
      deleted: j['deleted'] as bool? ?? false,
      fields: fields,
      clocks: (j['clocks'] as Map<String, dynamic>? ?? const {})
          .cast<String, String>(),
    );
  }

  /// 停止同步并等待进行中的一轮结束（退出登录、切换账号清空本地数据之前调用），
  /// 之后的 [sync] 不做任何事，直到 [resume]。
  Future<void> halt() async {
    _halted = true;
    _timer?.cancel();
    await _running;
  }

  void resume() => _halted = false;

  void _emit(SyncStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _running;
    await _status.close();
  }
}
