import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// 同步记录（离线优先：所有写入先落本地，见 ADR-005）。结构与服务端 records 表对应。
@DataClassName('RecordRow')
class Records extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()();

  /// 当前字段（明文 JSON）。
  TextColumn get fields => text()();

  /// 字段 → 最后修改的 HLC（JSON）。
  TextColumn get clocks => text()();

  /// 最后一次与服务端一致时的字段与时钟：用于判断本地改了哪些字段、生成文本补丁。
  TextColumn get baseFields => text().withDefault(const Constant('{}'))();
  TextColumn get baseClocks => text().withDefault(const Constant('{}'))();

  IntColumn get version => integer().withDefault(const Constant(0))();
  IntColumn get serverSeq => integer().withDefault(const Constant(0))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// 有尚未推送的本地修改。
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// 服务端返回冲突，修订历史中有落败的版本可供查看。
  BoolColumn get hasConflict => boolean().withDefault(const Constant(false))();

  /// 推送被拒绝的错误码；再次修改后清除并重试。
  TextColumn get syncError => text().nullable()();

  /// 本地最后修改时间（毫秒）。
  IntColumn get updatedAt => integer()();

  /// 派生列，便于查询：工作日志为日期，附件为空。
  TextColumn get sortKey => text().withDefault(const Constant(''))();

  /// 派生列：附件所属记录。
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 同步元数据：拉取游标、HLC 状态、所属账号等。
@DataClassName('MetaRow')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 附件在本机的文件：待上传的原文件副本，或已下载的缓存。
@DataClassName('LocalFileRow')
class LocalFiles extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();

  /// pending（待上传）/ uploaded（已上传）/ cached（已下载）。
  TextColumn get state => text()();
  TextColumn get ownerEntity => text()();
  TextColumn get ownerId => text()();
  TextColumn get fileName => text()();
  TextColumn get mime => text()();
  IntColumn get size => integer()();
  TextColumn get sha256 => text()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 派生索引：记录引用的标签、工作日志、文件夹（ADR-007），随记录写入而更新。
@DataClassName('RefRow')
class RecordRefs extends Table {
  TextColumn get recordId => text()();

  /// tag / worklog / folder。
  TextColumn get kind => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {recordId, kind, value};
}

@DriftDatabase(tables: [Records, SyncMeta, LocalFiles, RecordRefs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'jikelog'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX records_entity_sort ON records (entity, deleted, sort_key)',
      );
      await customStatement('CREATE INDEX records_dirty ON records (dirty)');
      await customStatement('CREATE INDEX records_owner ON records (owner_id)');
      await _createRefsIndex();
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2：笔记的关联索引（v1 中还没有笔记，无需回填）
      if (from < 2) {
        await m.createTable(recordRefs);
        await _createRefsIndex();
      }
    },
  );

  Future<void> _createRefsIndex() => customStatement(
    'CREATE INDEX record_refs_value ON record_refs (kind, value)',
  );

  /// 一条记录的全部引用。
  Future<List<RefRow>> refsOf(String recordId) =>
      (select(recordRefs)..where((t) => t.recordId.equals(recordId))).get();

  /// 替换一条记录的引用。
  Future<void> setRefs(String recordId, List<(String, String)> refs) =>
      transaction(() async {
        await (delete(
          recordRefs,
        )..where((t) => t.recordId.equals(recordId))).go();
        await batch(
          (b) => b.insertAll(recordRefs, [
            for (final (kind, value) in refs)
              RecordRefsCompanion.insert(
                recordId: recordId,
                kind: kind,
                value: value,
              ),
          ], mode: InsertMode.insertOrIgnore),
        );
      });

  /// 清空全部本地数据（退出登录或切换账号时）。
  Future<void> wipe() => transaction(() async {
    await delete(records).go();
    await delete(syncMeta).go();
    await delete(localFiles).go();
    await delete(recordRefs).go();
  });

  Future<String?> meta(String key) async => (await (select(
    syncMeta,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setMeta(String key, String value) => into(syncMeta)
      .insertOnConflictUpdate(SyncMetaCompanion.insert(key: key, value: value));
}
