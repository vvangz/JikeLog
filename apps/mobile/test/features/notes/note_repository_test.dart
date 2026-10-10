import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/sync_engine.dart';
import 'package:jikelog/features/notes/note_filters.dart';
import 'package:jikelog/features/notes/note_models.dart';
import 'package:jikelog/features/notes/note_repository.dart';

import '../../support/fake_sync_server.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late RecordStore store;
  late SyncEngine engine;
  late NoteRepository repo;
  late List<String> deleted;
  var now = 1791553544000;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = RecordStore(
      db,
      HybridClock(installationId: 'device-a', nowMs: () => now += 10),
    );
    final transport = FakeTransport(FakeSyncServer())..online = false;
    engine = SyncEngine(transport: transport, store: store, db: db);
    deleted = [];
    repo = NoteRepository(
      db: db,
      store: store,
      engine: engine,
      onDeleted: (id) async => deleted.add(id),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  Future<Note> note(String id) async => (await repo.get(id))!;
  Future<FolderTree> tree() async =>
      FolderTree(await repo.watchFolders().first);

  test('新建、修改与列表排序：置顶在前，再按最后修改', () async {
    final a = await repo.create();
    final b = await repo.create(format: NoteFormat.rich, tag: '草稿');
    await repo.update(a, title: '甲', body: '正文', favorite: true);
    var list = await repo.watchNotes().first;
    expect(list.map((n) => n.id), [a, b]);
    await repo.update(b, pinned: true);
    await repo.update(a, title: '甲改');
    list = await repo.watchNotes().first;
    expect(list.map((n) => n.id), [b, a]);
    final n = await note(b);
    expect(n.format, NoteFormat.rich);
    expect(n.tags, ['草稿']);
    expect((await note(a)).favorite, isTrue);
    await repo.update(a, format: NoteFormat.rich, favorite: false);
    expect((await note(a)).favorite, isFalse);
  });

  test('标签：添加、去重、校验、移除、跨笔记重命名与删除', () async {
    final a = await repo.create();
    final b = await repo.create();
    expect(await repo.addTag(a, ' 后端 '), isTrue);
    expect(await repo.addTag(a, '后端'), isTrue);
    expect(await repo.addTag(a, ''), isFalse);
    expect(await repo.addTag(a, '长' * 31), isFalse);
    await repo.addTag(a, '草稿');
    await repo.addTag(b, '草稿');
    expect((await note(a)).tags, ['后端', '草稿']);

    await repo.renameTag('草稿', '后端'); // 与已有标签合并
    expect((await note(a)).tags, ['后端']);
    expect((await note(b)).tags, ['后端']);
    await repo.renameTag('后端', '   '); // 空名称忽略
    expect((await note(a)).tags, ['后端']);

    await repo.removeTag(a, '后端');
    expect((await note(a)).tags, isEmpty);
    await repo.deleteTag('后端');
    expect((await note(b)).tags, isEmpty);
    expect(await repo.get(b), isNotNull, reason: '删除标签不删除笔记');
  });

  test('关联工作日志：双向显示（工作日志页反查）', () async {
    const wl = '0192a000-0000-7000-8000-0000000000a1';
    final a = await repo.create(worklogId: wl);
    final b = await repo.create();
    expect((await repo.watchLinkedTo(wl).first).map((n) => n.id), [a]);
    await repo.link(b, wl);
    await repo.link(b, wl);
    expect((await note(b)).worklogIds, [wl]);
    expect((await repo.watchLinkedTo(wl).first).map((n) => n.id).toSet(), {
      a,
      b,
    });
    await repo.unlink(a, wl);
    expect((await repo.watchLinkedTo(wl).first).map((n) => n.id), [b]);
  });

  test('删除笔记一并删除附件；已删除的笔记读不到也不能再写', () async {
    final a = await repo.create();
    await repo.delete(a);
    expect(deleted, [a]);
    expect(await repo.get(a), isNull);
    expect(await repo.watch(a).first, isNull);
    await repo.addTag(a, '不会写入');
    expect(await repo.get(a), isNull);
  });

  test('文件夹：新建、重命名、移动、删除时内容移到上一级', () async {
    final work = await repo.createFolder('  工作  ');
    final proj = await repo.createFolder('项目', parentId: work);
    final sub = await repo.createFolder('子项', parentId: proj);
    expect((await tree()).path(sub), '工作 / 项目 / 子项');

    await repo.renameFolder(proj, '项目 A\n第二行');
    expect((await tree()).byId[proj]!.name, '项目 A 第二行');
    final long = await repo.createFolder('名' * 60);
    expect((await tree()).byId[long]!.name.runes.length, maxFolderNameLength);

    expect(await repo.moveFolder(work, sub), isFalse, reason: '不能移到自己的下级');
    expect(await repo.moveFolder(sub, work), isTrue);
    expect((await tree()).path(sub), '工作 / 子项');
    await repo.moveFolder(sub, proj);

    final n = await repo.create(folderId: proj);
    await repo.deleteFolder(proj);
    final t = await tree();
    expect(t.byId.containsKey(proj), isFalse);
    expect(t.byId[sub]!.parentId, work);
    expect((await note(n)).folderId, work);

    await repo.moveTo(n, null);
    expect((await note(n)).folderId, isNull);
  });

  group('筛选', () {
    test('全部、收藏、未分类、文件夹（含下级）、标签', () async {
      final work = await repo.createFolder('工作');
      final proj = await repo.createFolder('项目', parentId: work);
      final a = await repo.create(folderId: work, tag: '后端');
      final b = await repo.create(folderId: proj);
      final c = await repo.create();
      final d = await repo.create(
        folderId: '0192a000-0000-7000-8000-0000000000ff', // 文件夹已不存在
      );
      await repo.update(c, favorite: true);
      final notes = await repo.watchNotes().first;
      final t = await tree();
      Set<String> ids(NoteFilter f) => {
        for (final n in applyFilter(notes, f, t)) n.id,
      };
      expect(ids(const AllNotes()), {a, b, c, d});
      expect(ids(const FavoriteNotes()), {c});
      expect(ids(const UnfiledNotes()), {c, d});
      expect(ids(FolderNotes(work)), {a, b});
      expect(ids(FolderNotes(proj)), {b});
      expect(ids(const TagNotes('后端')), {a});
      expect(folderCounts(notes, t), {work: 2, proj: 1});

      expect(const AllNotes().label(t), '全部笔记');
      expect(const FavoriteNotes().label(t), '收藏');
      expect(const UnfiledNotes().label(t), '未分类');
      expect(FolderNotes(proj).label(t), '工作 / 项目');
      expect(const FolderNotes('x').label(t), '文件夹');
      expect(const TagNotes('后端').label(t), '#后端');
      expect(const TagNotes('a'), const TagNotes('a'));
      expect(FolderNotes(work).hashCode, FolderNotes(work).hashCode);
    });

    test('标签按使用次数排序', () async {
      final a = await repo.create(tag: 'b');
      await repo.addTag(a, 'a');
      final b = await repo.create(tag: 'b');
      await repo.addTag(b, 'c');
      expect(tagCounts(await repo.watchNotes().first), [
        ('b', 2),
        ('a', 1),
        ('c', 1),
      ]);
    });
  });
}
