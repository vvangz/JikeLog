import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/database.dart';
import 'hlc.dart';
import 'refs.dart';
import 'schema.dart';
import 'text_patch.dart';

/// 本地记录（解码后的 [RecordRow]）。
@immutable
class LocalRecord {
  const LocalRecord({
    required this.id,
    required this.entity,
    required this.fields,
    required this.clocks,
    required this.baseFields,
    required this.baseClocks,
    required this.version,
    required this.serverSeq,
    required this.deleted,
    required this.dirty,
    required this.hasConflict,
    required this.updatedAt,
    this.syncError,
  });

  factory LocalRecord.fromRow(RecordRow r) => LocalRecord(
    id: r.id,
    entity: r.entity,
    fields: _map(r.fields),
    clocks: _map(r.clocks).cast<String, String>(),
    baseFields: _map(r.baseFields),
    baseClocks: _map(r.baseClocks).cast<String, String>(),
    version: r.version,
    serverSeq: r.serverSeq,
    deleted: r.deleted,
    dirty: r.dirty,
    hasConflict: r.hasConflict,
    syncError: r.syncError,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
  );

  final String id;
  final String entity;
  final Map<String, Object?> fields;
  final Map<String, String> clocks;
  final Map<String, Object?> baseFields;
  final Map<String, String> baseClocks;
  final int version;
  final int serverSeq;
  final bool deleted;
  final bool dirty;
  final bool hasConflict;
  final String? syncError;
  final DateTime updatedAt;

  /// 本地修改过、尚未被服务端确认的字段。
  Iterable<String> get changedFields =>
      clocks.keys.where((f) => clocks[f] != baseClocks[f]);

  static Map<String, Object?> _map(String raw) =>
      (jsonDecode(raw) as Map<String, dynamic>).cast<String, Object?>();
}

/// 待推送的一条变更（明文；敏感字段由同步引擎加密）。
@immutable
class OutgoingChange {
  const OutgoingChange({
    required this.entity,
    required this.id,
    required this.deleted,
    required this.fields,
    required this.clocks,
    required this.baseClocks,
    required this.patches,
  });

  final String entity;
  final String id;
  final bool deleted;
  final Map<String, Object?> fields;
  final Map<String, String> clocks;
  final Map<String, String> baseClocks;

  /// 长文本字段的补丁（JSON 字符串）。
  final Map<String, String> patches;
}

/// 服务端下发的记录（敏感字段已解密）。
@immutable
class RemoteRecord {
  const RemoteRecord({
    required this.entity,
    required this.id,
    required this.version,
    required this.serverSeq,
    required this.deleted,
    required this.fields,
    required this.clocks,
  });

  final String entity;
  final String id;
  final int version;
  final int serverSeq;
  final bool deleted;
  final Map<String, Object?> fields;
  final Map<String, String> clocks;
}

/// 本地记录的读写。所有修改都打上 HLC 并标记为待推送。
class RecordStore {
  RecordStore(this.db, this.clock, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase db;
  final HybridClock clock;
  final DateTime Function() _now;

  static const _clockKey = 'hlc.last';

  Future<LocalRecord?> get(String id) async {
    final row = await (db.select(
      db.records,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : LocalRecord.fromRow(row);
  }

  /// 修改（或新建）记录的部分字段。值未变的字段不会产生新的时钟。
  /// 已删除的记录忽略写入（例如编辑页关闭时迟到的保存），不能把墓碑改回正常记录。
  /// [create] 为 false 时记录不存在就忽略：从未同步就被删除的记录没有墓碑，迟到的修改不能把它重建出来。
  Future<void> write(
    String entity,
    String id,
    Map<String, Object?> changes, {
    bool create = true,
  }) => db.transaction(() async {
    final cur = await get(id);
    if (cur != null && cur.deleted) return;
    if (cur == null && !create) return;
    final fields = {...?cur?.fields};
    final clocks = {...?cur?.clocks};
    var touched = false;
    for (final e in changes.entries) {
      if (cur != null &&
          fields.containsKey(e.key) &&
          fields[e.key] == e.value) {
        continue;
      }
      fields[e.key] = e.value;
      clocks[e.key] = clock.now();
      touched = true;
    }
    if (!touched && cur != null) return;
    await _save(
      id: id,
      entity: entity,
      fields: fields,
      clocks: clocks,
      baseFields: cur?.baseFields ?? const {},
      baseClocks: cur?.baseClocks ?? const {},
      version: cur?.version ?? 0,
      serverSeq: cur?.serverSeq ?? 0,
      deleted: false,
      dirty: true,
      hasConflict: cur?.hasConflict ?? false,
    );
    await db.setMeta(_clockKey, clock.last);
  });

  /// 预置记录的字段时钟：最早的时刻、与设备无关的节点。各设备写出的时钟逐字相同，
  /// 服务端视为同一次修改，不会产生冲突；用户的任何修改都比它新。
  static const seedClock = '0000000000000-0000-0000000000000000';

  /// 写入预置记录（如默认分类）：本机还没有这条记录时才写入，字段时钟为 [seedClock]。
  /// 多台设备各自写入同一 ID 的预置记录时自然合并；用户在任何设备上的修改都比它新，
  /// 不会被尚未同步的设备用默认值覆盖（ADR-009）。返回是否写入。
  Future<bool> seed(String entity, String id, Map<String, Object?> fields) =>
      db.transaction(() async {
        if (await get(id) != null) return false;
        await _save(
          id: id,
          entity: entity,
          fields: fields,
          clocks: {for (final f in fields.keys) f: seedClock},
          baseFields: const {},
          baseClocks: const {},
          version: 0,
          serverSeq: 0,
          deleted: false,
          dirty: true,
          hasConflict: false,
        );
        return true;
      });

  /// 删除记录：从未同步过的直接删除，否则留下墓碑待推送。
  Future<void> remove(String id) => db.transaction(() async {
    final cur = await get(id);
    if (cur == null) return;
    await db.setRefs(id, const []);
    if (cur.version == 0) {
      await (db.delete(db.records)..where((t) => t.id.equals(id))).go();
      return;
    }
    await (db.update(db.records)..where((t) => t.id.equals(id))).write(
      RecordsCompanion(
        deleted: const Value(true),
        dirty: const Value(true),
        syncError: const Value(null),
        updatedAt: Value(_now().millisecondsSinceEpoch),
      ),
    );
  });

  /// 清除冲突提示（用户查看过冲突版本后）。
  Future<void> clearConflict(String id) =>
      (db.update(db.records)..where((t) => t.id.equals(id))).write(
        const RecordsCompanion(hasConflict: Value(false)),
      );

  /// 一次推送的请求体预算：服务端上限为 4MB，留出加密与编码的余量。
  static const defaultPushBytes = 2500000;

  /// 待推送的变更（不含被服务端拒绝且之后未再修改的记录）。
  /// 一批最多 [limit] 条，并按估算的请求体大小截断；第一条无论多大都会包含在内。
  Future<List<OutgoingChange>> pending({
    int limit = 100,
    int maxBytes = defaultPushBytes,
  }) async {
    final rows =
        await (db.select(db.records)
              ..where((t) => t.dirty.equals(true) & t.syncError.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)])
              ..limit(limit))
            .get();
    final out = <OutgoingChange>[];
    var bytes = 0;
    for (final r in rows) {
      final c = _outgoing(LocalRecord.fromRow(r));
      bytes += _estimateBytes(c);
      if (out.isNotEmpty && bytes > maxBytes) break;
      out.add(c);
    }
    return out;
  }

  /// 推送时的大致字节数：UTF-8 后再经加密与 Base64（约 4/3），另加字段名与时钟。
  static int _estimateBytes(OutgoingChange c) {
    var n = 300;
    for (final v in [...c.fields.values, ...c.patches.values]) {
      if (v is String) n += utf8.encode(v).length * 4 ~/ 3 + 64;
    }
    return n;
  }

  OutgoingChange _outgoing(LocalRecord r) {
    if (r.deleted) {
      return OutgoingChange(
        entity: r.entity,
        id: r.id,
        deleted: true,
        fields: const {},
        clocks: const {},
        baseClocks: const {},
        patches: const {},
      );
    }
    final fields = <String, Object?>{};
    final clocks = <String, String>{};
    final base = <String, String>{};
    final patches = <String, String>{};
    for (final f in r.changedFields) {
      fields[f] = r.fields[f];
      clocks[f] = r.clocks[f]!;
      if (r.baseClocks[f] != null) base[f] = r.baseClocks[f]!;
      final baseText = r.baseFields[f];
      final cur = r.fields[f];
      if (Entities.field(r.entity, f).text &&
          r.baseClocks[f] != null &&
          baseText is String &&
          cur is String) {
        patches[f] = TextPatch.encode(TextPatch.make(baseText, cur));
      }
    }
    return OutgoingChange(
      entity: r.entity,
      id: r.id,
      deleted: false,
      fields: fields,
      clocks: clocks,
      baseClocks: base,
      patches: patches,
    );
  }

  /// 推送成功（applied）：把已推送的字段记为基准；推送期间又修改过的字段保持待推送。
  Future<void> markPushed(
    OutgoingChange sent, {
    required int version,
    required int serverSeq,
  }) => db.transaction(() async {
    final cur = await get(sent.id);
    if (cur == null) return;
    if (sent.deleted) {
      await _setSynced(cur, version, serverSeq);
      return;
    }
    final baseFields = {...cur.baseFields};
    final baseClocks = {...cur.baseClocks};
    for (final f in sent.clocks.keys) {
      baseFields[f] = sent.fields[f];
      baseClocks[f] = sent.clocks[f]!;
    }
    await _save(
      id: cur.id,
      entity: cur.entity,
      fields: cur.fields,
      clocks: cur.clocks,
      baseFields: baseFields,
      baseClocks: baseClocks,
      version: version,
      serverSeq: serverSeq,
      deleted: cur.deleted,
      // 推送期间被删除的记录还要推送墓碑
      dirty:
          cur.deleted ||
          cur.clocks.keys.any((f) => cur.clocks[f] != baseClocks[f]),
      hasConflict: cur.hasConflict,
    );
  });

  /// 推送被拒绝：记录原因，不再自动重试，直到用户再次修改。
  Future<void> markRejected(String id, String code) =>
      (db.update(db.records)..where((t) => t.id.equals(id))).write(
        RecordsCompanion(syncError: Value(code)),
      );

  /// 应用服务端记录（拉取结果，或推送结果为 merged/conflict 时的最终记录）。
  ///
  /// 本地未修改的字段直接采用服务端的值并更新基准。本地修改过、尚未被确认的字段保留本地值，
  /// **基准保持不变**：下次推送时服务端发现基准时钟不是自己的时钟，会用补丁合并或按最后修改覆盖。
  /// 如果把基准换成服务端的新值，补丁就会把对方的修改当成本地删除，快进时直接抹掉对方的修改。
  ///
  /// [sent] 为本次推送的内容（推送结果为 merged/conflict 时）：推送后没再改过的字段以服务端结果为准；
  /// 推送后又改过的字段以推送的值为基准，下次只推送之后的修改。
  /// 尚未推送的删除保留墓碑，等推送后由服务端裁决。
  Future<void> applyRemote(
    RemoteRecord r, {
    bool conflict = false,
    OutgoingChange? sent,
  }) => db.transaction(() async {
    r.clocks.values.forEach(clock.receive);
    final cur = await get(r.id);
    if (cur != null && cur.serverSeq >= r.serverSeq && !conflict) return;
    if (cur != null && cur.deleted && cur.dirty) return;
    if (r.deleted) {
      await _applyTombstone(cur, r);
      return;
    }
    final fields = <String, Object?>{...r.fields};
    final clocks = <String, String>{...r.clocks};
    final baseFields = <String, Object?>{...r.fields};
    final baseClocks = <String, String>{...r.clocks};
    var dirty = false;
    for (final f in cur?.changedFields ?? const <String>[]) {
      final local = cur!.clocks[f]!;
      if (sent?.clocks[f] == local || r.clocks[f] == local) continue;
      fields[f] = cur.fields[f];
      clocks[f] = local;
      _setBase(baseFields, baseClocks, f, cur.baseFields[f], cur.baseClocks[f]);
      if (sent != null && sent.clocks.containsKey(f)) {
        _setBase(baseFields, baseClocks, f, sent.fields[f], sent.clocks[f]);
      }
      dirty = true;
    }
    await _save(
      id: r.id,
      entity: r.entity,
      fields: fields,
      clocks: clocks,
      baseFields: baseFields,
      baseClocks: baseClocks,
      version: r.version,
      serverSeq: r.serverSeq,
      deleted: false,
      dirty: dirty,
      hasConflict: conflict || (cur?.hasConflict ?? false),
    );
    await db.setMeta(_clockKey, clock.last);
  });

  static void _setBase(
    Map<String, Object?> fields,
    Map<String, String> clocks,
    String f,
    Object? value,
    String? clock,
  ) {
    if (clock == null) {
      fields.remove(f);
      clocks.remove(f);
    } else {
      fields[f] = value;
      clocks[f] = clock;
    }
  }

  Future<void> _applyTombstone(LocalRecord? cur, RemoteRecord r) async {
    // 删除胜过编辑：本地未推送的修改已在推送阶段交给服务端，落败的内容保存在修订历史中
    await _save(
      id: r.id,
      entity: r.entity,
      fields: cur?.fields ?? const {},
      clocks: cur?.clocks ?? const {},
      baseFields: cur?.fields ?? const {},
      baseClocks: cur?.clocks ?? const {},
      version: r.version,
      serverSeq: r.serverSeq,
      deleted: true,
      dirty: false,
      hasConflict: false,
    );
  }

  Future<void> _setSynced(LocalRecord cur, int version, int seq) =>
      (db.update(db.records)..where((t) => t.id.equals(cur.id))).write(
        RecordsCompanion(
          version: Value(version),
          serverSeq: Value(seq),
          dirty: const Value(false),
        ),
      );

  Future<void> _save({
    required String id,
    required String entity,
    required Map<String, Object?> fields,
    required Map<String, String> clocks,
    required Map<String, Object?> baseFields,
    required Map<String, String> baseClocks,
    required int version,
    required int serverSeq,
    required bool deleted,
    required bool dirty,
    required bool hasConflict,
  }) => db
      .into(db.records)
      .insertOnConflictUpdate(
        RecordsCompanion.insert(
          id: id,
          entity: entity,
          fields: jsonEncode(fields),
          clocks: jsonEncode(clocks),
          baseFields: Value(jsonEncode(baseFields)),
          baseClocks: Value(jsonEncode(baseClocks)),
          version: Value(version),
          serverSeq: Value(serverSeq),
          deleted: Value(deleted),
          dirty: Value(dirty),
          hasConflict: Value(hasConflict),
          syncError: const Value(null),
          updatedAt: _now().millisecondsSinceEpoch,
          sortKey: Value(_sortKey(entity, fields, clocks)),
          ownerId: Value(
            entity == Entities.attachment ? fields['ownerId'] as String? : null,
          ),
        ),
      )
      .then((_) => db.setRefs(id, deleted ? const [] : refsOf(entity, fields)));

  /// 派生的排序键：工作日志按日期；笔记置顶在前，再按最后修改的字段时钟（HLC 可按字典序比较）；
  /// 备忘录按时间（补齐为 13 位毫秒数，字典序即时间顺序，便于按日期范围查询）。
  static String _sortKey(
    String entity,
    Map<String, Object?> fields,
    Map<String, String> clocks,
  ) => switch (entity) {
    Entities.worklog => fields['date'] as String? ?? '',
    Entities.note =>
      '${fields['pinned'] == 1 ? 1 : 0}|'
          '${clocks.values.fold('', (a, b) => b.compareTo(a) > 0 ? b : a)}',
    Entities.memo => memoSortKey(fields['at'] as int? ?? 0),
    // 流水按日期，同一天内按最后修改先后
    Entities.ledgerEntry =>
      '${fields['date'] as String? ?? ''}|'
          '${clocks.values.fold('', (a, b) => b.compareTo(a) > 0 ? b : a)}',
    _ => '',
  };

  /// 备忘录时间对应的排序键。
  static String memoSortKey(int atMillis) =>
      atMillis.toString().padLeft(13, '0');

  /// 启动时恢复 HLC，保证重启后时钟仍单调。
  static Future<HybridClock> loadClock(
    AppDatabase db,
    String installationId,
  ) async => HybridClock(
    installationId: installationId,
    last: await db.meta(_clockKey),
  );
}
