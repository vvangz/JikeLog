import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../core/sync/record_store.dart';
import '../../core/sync/schema.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import '../attachments/attachment_providers.dart';

/// 一条工作日志。
@immutable
class Worklog {
  const Worklog({
    required this.id,
    required this.date,
    required this.location,
    required this.content,
    required this.updatedAt,
    this.pending = false,
    this.hasConflict = false,
    this.syncError,
  });

  factory Worklog.fromRecord(LocalRecord r) => Worklog(
    id: r.id,
    date:
        DateTime.tryParse(r.fields['date'] as String? ?? '') ?? DateTime.now(),
    location: r.fields['location'] as String? ?? '',
    content: r.fields['content'] as String? ?? '',
    updatedAt: r.updatedAt,
    pending: r.dirty,
    hasConflict: r.hasConflict,
    syncError: r.syncError,
  );

  final String id;
  final DateTime date;
  final String location;

  /// Markdown 正文。
  final String content;
  final DateTime updatedAt;

  /// 有尚未同步到服务端的修改。
  final bool pending;

  /// 与其他设备的修改冲突，修订历史中有落败的版本。
  final bool hasConflict;

  /// 服务端拒绝了这条修改（错误码）。
  final String? syncError;
}

/// 日期按服务端格式（YYYY-MM-DD）编码。
String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 工作日志的读写：写入本地后由同步引擎在后台推送。
class WorklogRepository {
  WorklogRepository({
    required this.db,
    required this.store,
    required this.engine,
    this.onDeleted,
  });

  final AppDatabase db;
  final RecordStore store;
  final SyncEngine engine;

  /// 日志删除后调用，用于一并删除其附件。
  final Future<void> Function(String worklogId)? onDeleted;

  SimpleSelectStatement<$RecordsTable, RecordRow> _query() =>
      db.select(db.records)
        ..where((t) => t.entity.equals(Entities.worklog) & t.deleted.not())
        ..orderBy([
          (t) => OrderingTerm.desc(t.sortKey),
          (t) => OrderingTerm.desc(t.updatedAt),
        ]);

  /// 全部日志，按日期倒序。
  Stream<List<Worklog>> watchAll() => _query().watch().map(
    (rows) => [
      for (final r in rows) Worklog.fromRecord(LocalRecord.fromRow(r)),
    ],
  );

  /// 单条日志；被删除（包括在其他设备上删除）后为 null。
  Stream<Worklog?> watch(String id) =>
      (db.select(
        db.records,
      )..where((t) => t.id.equals(id))).watchSingleOrNull().map(
        (r) => r == null || r.deleted
            ? null
            : Worklog.fromRecord(LocalRecord.fromRow(r)),
      );

  /// 新建一条日志，返回 ID（UUIDv7，由客户端生成）。
  Future<String> create({DateTime? date, String location = ''}) async {
    final id = const Uuid().v7();
    await store.write(Entities.worklog, id, {
      'date': formatDate(date ?? DateTime.now()),
      'location': location,
      'content': '',
    });
    engine.schedule();
    return id;
  }

  /// 修改字段；只有值变化的字段会被记录与同步。
  Future<void> update(
    String id, {
    DateTime? date,
    String? location,
    String? content,
  }) async {
    await store.write(Entities.worklog, id, create: false, {
      'date': ?(date == null ? null : formatDate(date)),
      'location': ?location,
      'content': ?content,
    });
    engine.schedule();
  }

  Future<void> delete(String id) async {
    await store.remove(id);
    await onDeleted?.call(id);
    engine.schedule();
  }

  /// 历史工作地点（最近使用的在前，去重），用于输入联想。
  Future<List<String>> recentLocations({int limit = 20}) async {
    final rows = await (_query()..limit(200)).get();
    final seen = <String>{};
    for (final r in rows) {
      final loc = (LocalRecord.fromRow(r).fields['location'] as String? ?? '')
          .trim();
      if (loc.isNotEmpty && seen.add(loc) && seen.length >= limit) break;
    }
    return seen.toList();
  }
}

final worklogRepositoryProvider = Provider<WorklogRepository>(
  (ref) => WorklogRepository(
    db: ref.watch(appDatabaseProvider),
    store: ref.watch(recordStoreProvider),
    engine: ref.watch(syncEngineProvider),
    onDeleted: ref.watch(attachmentServiceProvider).removeAll,
  ),
);

final worklogListProvider = StreamProvider<List<Worklog>>(
  (ref) => ref.watch(worklogRepositoryProvider).watchAll(),
);

final worklogProvider = StreamProvider.family<Worklog?, String>(
  (ref, id) => ref.watch(worklogRepositoryProvider).watch(id),
);
