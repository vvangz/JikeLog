import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../core/sync/record_store.dart';
import '../../core/sync/schema.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import 'memo_models.dart';

/// 备忘录的读写：写入本地后由同步引擎在后台推送。
class MemoRepository {
  MemoRepository({required this.db, required this.store, required this.engine});

  final AppDatabase db;
  final RecordStore store;
  final SyncEngine engine;

  SimpleSelectStatement<$RecordsTable, RecordRow> _query() =>
      db.select(db.records)
        ..where((t) => t.entity.equals(Entities.memo) & t.deleted.not())
        ..orderBy([(t) => OrderingTerm.asc(t.sortKey)]);

  static List<Memo> _map(List<RecordRow> rows) => [
    for (final r in rows) Memo.fromRecord(LocalRecord.fromRow(r)),
  ];

  /// 全部备忘，按时间先后。
  Stream<List<Memo>> watchAll() =>
      _query().watch().map(_map).distinct(listEquals);

  /// 单条备忘；被删除（包括在其他设备上删除）后为 null。
  Stream<Memo?> watch(String id) =>
      (db.select(db.records)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map(
            (r) => r == null || r.deleted || r.entity != Entities.memo
                ? null
                : Memo.fromRecord(LocalRecord.fromRow(r)),
          )
          .distinct();

  Future<Memo?> get(String id) async {
    final r = await (db.select(
      db.records,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null || r.deleted || r.entity != Entities.memo) return null;
    return Memo.fromRecord(LocalRecord.fromRow(r));
  }

  /// 新建一条备忘，返回 ID（UUIDv7，由客户端生成）。内容不能为空（服务端必填）。
  Future<String> create({
    required String content,
    required DateTime at,
    bool allDay = false,
    List<int> reminders = const [],
  }) async {
    if (content.trim().isEmpty) throw ArgumentError('备忘内容不能为空');
    final id = const Uuid().v7();
    await store.write(Entities.memo, id, {
      'content': content,
      'at': (allDay ? allDayAt(at) : at).millisecondsSinceEpoch,
      'allDay': allDay ? 1 : 0,
      'reminders': encodeReminders(reminders),
      'done': 0,
    });
    engine.schedule();
    return id;
  }

  /// 修改字段；只有值变化的字段会被记录与同步。改为全天时时间对齐到当天 9:00。
  Future<void> update(
    String id, {
    String? content,
    DateTime? at,
    bool? allDay,
    List<int>? reminders,
    bool? done,
  }) async {
    if (content != null && content.trim().isEmpty) {
      throw ArgumentError('备忘内容不能为空');
    }
    var time = at;
    if (allDay == true) {
      time = allDayAt(at ?? (await get(id))?.at ?? DateTime.now());
    }
    await store.write(Entities.memo, id, create: false, {
      'content': ?content,
      'at': ?time?.millisecondsSinceEpoch,
      'allDay': ?(allDay == null ? null : (allDay ? 1 : 0)),
      'reminders': ?(reminders == null ? null : encodeReminders(reminders)),
      'done': ?(done == null ? null : (done ? 1 : 0)),
    });
    engine.schedule();
  }

  Future<void> delete(String id) async {
    await store.remove(id);
    engine.schedule();
  }
}

final memoRepositoryProvider = Provider<MemoRepository>(
  (ref) => MemoRepository(
    db: ref.watch(appDatabaseProvider),
    store: ref.watch(recordStoreProvider),
    engine: ref.watch(syncEngineProvider),
  ),
);

final memoListProvider = StreamProvider<List<Memo>>(
  (ref) => ref.watch(memoRepositoryProvider).watchAll(),
);

final memoProvider = StreamProvider.family<Memo?, String>(
  (ref, id) => ref.watch(memoRepositoryProvider).watch(id),
);
