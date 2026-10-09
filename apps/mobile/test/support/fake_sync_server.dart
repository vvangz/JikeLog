import 'package:cryptography/cryptography.dart';
import 'package:jikelog/core/api/api_exception.dart';
import 'package:jikelog/core/sync/e2e.dart';
import 'package:jikelog/core/sync/schema.dart';
import 'package:jikelog/core/sync/sync_api.dart';
import 'package:jikelog/core/sync/sync_engine.dart';
import 'package:jikelog/core/sync/text_patch.dart';

/// 内存中的同步服务端：按 ADR-005 的规则逐字段合并（快进 / 补丁合并 / 最后修改覆盖 / 删除胜出），
/// 用于验证客户端同步引擎。与 Go 实现的一致性由服务端集成测试保证。
class FakeSyncServer {
  final records = <String, ServerRecord>{};
  int seq = 0;

  /// 被拒绝的记录 ID（模拟服务端校验失败）。
  final rejectIds = <String>{};
}

class ServerRecord {
  ServerRecord(this.entity, this.id);

  final String entity;
  final String id;
  int version = 0;
  int serverSeq = 0;
  bool deleted = false;
  Map<String, Object?> fields = {};
  Map<String, String> clocks = {};
  Map<String, Set<String>> absorbed = {};

  Map<String, dynamic> toJson() => {
    'entity': entity,
    'id': id,
    'version': version,
    'serverSeq': serverSeq,
    'deleted': deleted,
    'fields': deleted ? <String, Object?>{} : {...fields},
    'clocks': deleted ? <String, String>{} : {...clocks},
  };
}

/// 一台设备与 [FakeSyncServer] 之间的连接（含传输加密）。
class FakeTransport implements SyncTransport {
  FakeTransport(this.server);

  final FakeSyncServer server;
  final _session = E2ESession(
    id: 'fake',
    key: SecretKey(List.filled(32, 9)),
    expiresAt: DateTime(2100),
  );

  /// 为 false 时模拟离线。
  bool online = true;

  /// 推送请求到达服务端之前调用（模拟推送期间用户继续编辑）。
  Future<void> Function()? beforePush;
  int pushCount = 0;

  @override
  Future<T> withSession<T>(Future<T> Function(E2ESession s) call) =>
      call(_session);

  void _check() {
    if (!online) {
      throw const ApiException(code: ApiErrorCode.network, message: '网络连接失败');
    }
  }

  @override
  Future<({List<PushResult> results, int cursor})> push(
    E2ESession s,
    List<Map<String, dynamic>> changes,
  ) async {
    _check();
    pushCount++;
    await beforePush?.call();
    final results = <PushResult>[];
    for (final c in changes) {
      results.add(await _apply(s, c));
    }
    return (results: results, cursor: server.seq);
  }

  Future<PushResult> _apply(E2ESession s, Map<String, dynamic> c) async {
    final id = c['id'] as String;
    final entity = c['entity'] as String;
    if (server.rejectIds.contains(id)) {
      return PushResult(
        id: id,
        status: 'rejected',
        errorCode: 'VALIDATION_FAILED',
      );
    }
    final cur = server.records[id];
    if (c['deleted'] == true) {
      if (cur == null || cur.deleted) {
        return PushResult(id: id, status: 'applied');
      }
      cur.deleted = true;
      _bump(cur);
      return PushResult(
        id: id,
        status: 'applied',
        version: cur.version,
        serverSeq: cur.serverSeq,
      );
    }
    final fields = await _open(
      s,
      entity,
      id,
      c['fields'] as Map<String, dynamic>,
    );
    final clocks = (c['clocks'] as Map<String, dynamic>).cast<String, String>();
    final base = (c['baseClocks'] as Map<String, dynamic>? ?? {})
        .cast<String, String>();
    final patches = <String, String>{};
    for (final e in (c['patches'] as Map<String, dynamic>? ?? {}).entries) {
      patches[e.key] = await E2ECrypto.open(
        s.key,
        E2ECrypto.aad(entity, id, e.key, 'p'),
        e.value as String,
      );
    }
    if (cur == null) {
      final r = ServerRecord(entity, id)
        ..fields = fields
        ..clocks = clocks;
      server.records[id] = r;
      _bump(r);
      return PushResult(
        id: id,
        status: 'applied',
        version: r.version,
        serverSeq: r.serverSeq,
      );
    }
    if (cur.deleted) {
      return PushResult(
        id: id,
        status: 'conflict',
        version: cur.version,
        serverSeq: cur.serverSeq,
        record: await _seal(s, cur),
      );
    }
    var status = 'applied';
    var changed = false;
    for (final f in fields.keys) {
      final cc = clocks[f]!;
      final sc = cur.clocks[f];
      if (cc == sc || (cur.absorbed[f]?.contains(cc) ?? false)) continue;
      changed = true;
      if (sc == base[f]) {
        cur.fields[f] = fields[f];
        cur.clocks[f] = cc;
        cur.absorbed.remove(f);
      } else if (patches[f] != null &&
          Entities.field(entity, f).text &&
          TextPatch.apply(
            cur.fields[f] as String? ?? '',
            TextPatch.decode(patches[f]!),
          ).ok) {
        cur.fields[f] = TextPatch.apply(
          cur.fields[f] as String? ?? '',
          TextPatch.decode(patches[f]!),
        ).text;
        final winner = cc.compareTo(sc ?? '') > 0 ? cc : sc!;
        if (winner != cc) (cur.absorbed[f] ??= {}).add(cc);
        cur.clocks[f] = winner;
        if (status == 'applied') status = 'merged';
      } else if (cc.compareTo(sc ?? '') > 0) {
        cur.fields[f] = fields[f];
        cur.clocks[f] = cc;
        cur.absorbed.remove(f);
        status = 'conflict';
      } else {
        (cur.absorbed[f] ??= {}).add(cc);
        status = 'conflict';
      }
    }
    if (changed) _bump(cur);
    return PushResult(
      id: id,
      status: status,
      version: cur.version,
      serverSeq: cur.serverSeq,
      record: status == 'applied' ? null : await _seal(s, cur),
    );
  }

  void _bump(ServerRecord r) {
    r.version++;
    r.serverSeq = ++server.seq;
  }

  @override
  Future<PullPage> pull(E2ESession s, int since, {int limit = 200}) async {
    _check();
    final list =
        server.records.values.where((r) => r.serverSeq > since).toList()
          ..sort((a, b) => a.serverSeq.compareTo(b.serverSeq));
    final page = list.take(limit).toList();
    return PullPage(
      records: [for (final r in page) await _seal(s, r)],
      nextSince: page.isEmpty ? since : page.last.serverSeq,
      hasMore: list.length > limit,
    );
  }

  @override
  Future<void> ack(int seq) async => _check();

  Future<Map<String, Object?>> _open(
    E2ESession s,
    String entity,
    String id,
    Map<String, dynamic> raw,
  ) async {
    final out = <String, Object?>{};
    for (final e in raw.entries) {
      final v = e.value;
      out[e.key] = v is String && Entities.field(entity, e.key).sensitive
          ? await s.openValue(entity, id, e.key, v)
          : v;
    }
    return out;
  }

  Future<Map<String, dynamic>> _seal(E2ESession s, ServerRecord r) async {
    final j = r.toJson();
    final fields = j['fields'] as Map<String, Object?>;
    for (final f in fields.keys.toList()) {
      final v = fields[f];
      if (v is String && Entities.field(r.entity, f).sensitive) {
        fields[f] = await s.sealValue(r.entity, r.id, f, v);
      }
    }
    return j;
  }
}
