import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../core/sync/record_store.dart';
import '../../core/sync/refs.dart';
import '../../core/sync/schema.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import '../attachments/attachment_providers.dart';
import 'note_models.dart';

/// 笔记与文件夹的读写：写入本地后由同步引擎在后台推送（ADR-005、ADR-007）。
class NoteRepository {
  NoteRepository({
    required this.db,
    required this.store,
    required this.engine,
    this.onDeleted,
  });

  final AppDatabase db;
  final RecordStore store;
  final SyncEngine engine;

  /// 笔记删除后调用，用于一并删除其附件。
  final Future<void> Function(String noteId)? onDeleted;

  SimpleSelectStatement<$RecordsTable, RecordRow> _entity(String entity) =>
      db.select(db.records)
        ..where((t) => t.entity.equals(entity) & t.deleted.not());

  /// 全部笔记：置顶在前，再按最后修改时间倒序。
  Stream<List<Note>> watchNotes() => (_entity(
    Entities.note,
  )..orderBy([(t) => OrderingTerm.desc(t.sortKey)])).watch().map(_notes);

  /// 单篇笔记；被删除（包括在其他设备上删除）后为 null。
  Stream<Note?> watch(String id) =>
      (db.select(
        db.records,
      )..where((t) => t.id.equals(id))).watchSingleOrNull().map(
        (r) => r == null || r.deleted || r.entity != Entities.note
            ? null
            : Note.fromRecord(LocalRecord.fromRow(r)),
      );

  Future<Note?> get(String id) async {
    final r = await store.get(id);
    return r == null || r.deleted || r.entity != Entities.note
        ? null
        : Note.fromRecord(r);
  }

  /// 关联了某条工作日志的笔记（通过本地索引反查）。
  Stream<List<Note>> watchLinkedTo(String worklogId) {
    final linked = db.selectOnly(db.recordRefs)
      ..addColumns([db.recordRefs.recordId])
      ..where(
        db.recordRefs.kind.equals(RefKind.worklog) &
            db.recordRefs.value.equals(worklogId),
      );
    return (_entity(Entities.note)
          ..where((t) => t.id.isInQuery(linked))
          ..orderBy([(t) => OrderingTerm.desc(t.sortKey)]))
        .watch()
        .map(_notes);
  }

  Stream<List<NoteFolder>> watchFolders() => _entity(Entities.noteFolder)
      .watch()
      .map(
        (rows) => [
          for (final r in rows) NoteFolder.fromRecord(LocalRecord.fromRow(r)),
        ],
      );

  static List<Note> _notes(List<RecordRow> rows) => [
    for (final r in rows) Note.fromRecord(LocalRecord.fromRow(r)),
  ];

  // ---- 笔记 ----

  /// 新建笔记，返回 ID（UUIDv7，由客户端生成）。
  Future<String> create({
    NoteFormat format = NoteFormat.markdown,
    String? folderId,
    String? tag,
    String? worklogId,
  }) async {
    final id = const Uuid().v7();
    await store.write(Entities.note, id, {
      'title': '',
      'body': '',
      'format': format.name,
      'folderId': folderId,
      'favorite': 0,
      'pinned': 0,
      'tags': tag ?? '',
      'worklogs': worklogId ?? '',
    });
    engine.schedule();
    return id;
  }

  /// 修改字段；只有值变化的字段会被记录与同步。
  Future<void> update(
    String id, {
    String? title,
    String? body,
    NoteFormat? format,
    bool? favorite,
    bool? pinned,
  }) async {
    await store.write(Entities.note, id, {
      'title': ?title,
      'body': ?body,
      'format': ?format?.name,
      'favorite': ?(favorite == null ? null : (favorite ? 1 : 0)),
      'pinned': ?(pinned == null ? null : (pinned ? 1 : 0)),
    });
    engine.schedule();
  }

  /// 移到文件夹（null 为未分类）。
  Future<void> moveTo(String id, String? folderId) async {
    await store.write(Entities.note, id, {'folderId': folderId});
    engine.schedule();
  }

  /// 修改多行文本字段（标签、关联）：在原文本上增删行，便于两台设备同时修改时按补丁合并。
  Future<void> _editLines(
    String id,
    String field,
    String Function(List<String> lines) edit,
  ) async {
    final cur = await store.get(id);
    if (cur == null || cur.deleted) return;
    final next = edit(parseLines(cur.fields[field]));
    await store.write(Entities.note, id, {field: next});
    engine.schedule();
  }

  /// 添加标签（已存在时不变）。返回 false 表示标签不合法。
  Future<bool> addTag(String id, String tag) async {
    final t = tag.trim();
    if (t.isEmpty || t.contains('\n') || t.runes.length > maxTagLength) {
      return false;
    }
    await _editLines(
      id,
      'tags',
      (lines) => (lines.contains(t) ? lines : [...lines, t]).join('\n'),
    );
    return true;
  }

  Future<void> removeTag(String id, String tag) => _editLines(
    id,
    'tags',
    (lines) => lines.where((l) => l != tag).join('\n'),
  );

  /// 关联到工作日志（双向显示：工作日志页通过本地索引反查）。
  Future<void> link(String id, String worklogId) => _editLines(
    id,
    'worklogs',
    (lines) =>
        (lines.contains(worklogId) ? lines : [...lines, worklogId]).join('\n'),
  );

  Future<void> unlink(String id, String worklogId) => _editLines(
    id,
    'worklogs',
    (lines) => lines.where((l) => l != worklogId).join('\n'),
  );

  Future<void> delete(String id) async {
    await store.remove(id);
    await onDeleted?.call(id);
    engine.schedule();
  }

  // ---- 标签（跨笔记）----

  /// 重命名标签：修改所有带该标签的笔记。新名称已存在时合并。
  Future<void> renameTag(String from, String to) async {
    final t = to.trim();
    if (t.isEmpty || t == from || t.runes.length > maxTagLength) return;
    for (final id in await _notesWithRef(RefKind.tag, from)) {
      await _editLines(id, 'tags', (lines) {
        final out = <String>[];
        for (final l in lines) {
          final v = l == from ? t : l;
          if (!out.contains(v)) out.add(v);
        }
        return out.join('\n');
      });
    }
  }

  /// 从所有笔记上移除标签（笔记本身不删除）。
  Future<void> deleteTag(String tag) async {
    for (final id in await _notesWithRef(RefKind.tag, tag)) {
      await removeTag(id, tag);
    }
  }

  Future<List<String>> _notesWithRef(String kind, String value) async {
    final q = db.selectOnly(db.recordRefs)
      ..addColumns([db.recordRefs.recordId])
      ..where(
        db.recordRefs.kind.equals(kind) & db.recordRefs.value.equals(value),
      );
    return [for (final r in await q.get()) r.read(db.recordRefs.recordId)!];
  }

  // ---- 文件夹 ----

  /// 新建文件夹，返回 ID。名称会去掉首尾空白并截断到上限。
  Future<String> createFolder(String name, {String? parentId}) async {
    final id = const Uuid().v7();
    await store.write(Entities.noteFolder, id, {
      'name': _folderName(name),
      'parentId': parentId,
    });
    engine.schedule();
    return id;
  }

  Future<void> renameFolder(String id, String name) async {
    await store.write(Entities.noteFolder, id, {'name': _folderName(name)});
    engine.schedule();
  }

  /// 移动文件夹。不能移到自己或自己的下级中，返回 false。
  Future<bool> moveFolder(String id, String? parentId) async {
    final tree = FolderTree(await watchFolders().first);
    if (!tree.canMove(id, parentId)) return false;
    await store.write(Entities.noteFolder, id, {'parentId': parentId});
    engine.schedule();
    return true;
  }

  /// 删除文件夹：其中的笔记和子文件夹移到上一级（ADR-007）。
  Future<void> deleteFolder(String id) async {
    final tree = FolderTree(await watchFolders().first);
    final parent = tree.parentOf(id);
    for (final noteId in await _notesWithRef(RefKind.folder, id)) {
      await store.write(Entities.note, noteId, {'folderId': parent});
    }
    for (final child in tree.byId.values.where((f) => f.parentId == id)) {
      await store.write(Entities.noteFolder, child.id, {'parentId': parent});
    }
    await store.remove(id);
    engine.schedule();
  }

  static String _folderName(String name) {
    final t = name.trim().replaceAll('\n', ' ');
    final runes = t.runes.toList();
    return runes.length <= maxFolderNameLength
        ? t
        : String.fromCharCodes(runes.take(maxFolderNameLength));
  }
}

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => NoteRepository(
    db: ref.watch(appDatabaseProvider),
    store: ref.watch(recordStoreProvider),
    engine: ref.watch(syncEngineProvider),
    onDeleted: ref.watch(attachmentServiceProvider).removeAll,
  ),
);

final noteListProvider = StreamProvider<List<Note>>(
  (ref) => ref.watch(noteRepositoryProvider).watchNotes(),
);

final noteProvider = StreamProvider.family<Note?, String>(
  (ref, id) => ref.watch(noteRepositoryProvider).watch(id),
);

final noteFoldersProvider = StreamProvider<FolderTree>(
  (ref) => ref.watch(noteRepositoryProvider).watchFolders().map(FolderTree.new),
);

/// 关联了某条工作日志的笔记。
final linkedNotesProvider = StreamProvider.family<List<Note>, String>(
  (ref, worklogId) =>
      ref.watch(noteRepositoryProvider).watchLinkedTo(worklogId),
);
