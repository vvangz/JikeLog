import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/record_store.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late RecordStore store;
  var now = 1791553544000;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = RecordStore(
      db,
      HybridClock(installationId: 'device-a', nowMs: () => now++),
    );
  });

  tearDown(() => db.close());

  const note = '0192a000-0000-7000-8000-000000000001';
  const wl1 = '0192a000-0000-7000-8000-0000000000a1';
  const wl2 = '0192a000-0000-7000-8000-0000000000a2';
  const folder = '0192a000-0000-7000-8000-0000000000f1';

  Future<Set<String>> refs(String id) async => {
    for (final r in await db.refsOf(id)) '${r.kind}:${r.value}',
  };

  group('关联索引 record_refs', () {
    test('写入笔记时按标签、关联日志、文件夹建立索引，非法与重复的行被忽略', () async {
      await store.write('note', note, {
        'format': 'markdown',
        'tags': ' 后端 \n草稿\n\n后端',
        'worklogs': '$wl1\nnot-a-uuid\n$wl1',
        'folderId': folder,
      });
      expect(await refs(note), {
        'tag:后端',
        'tag:草稿',
        'worklog:$wl1',
        'folder:$folder',
      });

      await store.write('note', note, {
        'tags': '草稿',
        'worklogs': wl2,
        'folderId': null,
      });
      expect(await refs(note), {'tag:草稿', 'worklog:$wl2'});
    });

    test('删除与墓碑会清除索引', () async {
      await store.write('note', note, {'format': 'markdown', 'tags': '甲'});
      await store.remove(note); // 从未同步：直接删除
      expect(await refs(note), isEmpty);

      await store.applyRemote(
        const RemoteRecord(
          entity: 'note',
          id: note,
          version: 1,
          serverSeq: 1,
          deleted: false,
          fields: {'format': 'rich', 'tags': '乙', 'worklogs': wl1},
          clocks: {'format': 'c1', 'tags': 'c1', 'worklogs': 'c1'},
        ),
      );
      expect(await refs(note), {'tag:乙', 'worklog:$wl1'});
      await store.applyRemote(
        const RemoteRecord(
          entity: 'note',
          id: note,
          version: 2,
          serverSeq: 2,
          deleted: true,
          fields: {},
          clocks: {},
        ),
      );
      expect(await refs(note), isEmpty);
    });

    test('本机删除已同步的笔记（墓碑待推送）时清除索引', () async {
      await store.applyRemote(
        const RemoteRecord(
          entity: 'note',
          id: note,
          version: 1,
          serverSeq: 1,
          deleted: false,
          fields: {'format': 'rich', 'tags': '乙'},
          clocks: {'format': 'c1', 'tags': 'c1'},
        ),
      );
      await store.remove(note);
      expect(await refs(note), isEmpty);
    });

    test('工作日志等其他实体不建立索引；清空本地数据时一并清空', () async {
      await store.write('worklog', wl1, {'date': '2026-10-10', 'content': ''});
      expect(await refs(wl1), isEmpty);
      await store.write('note', note, {'format': 'markdown', 'tags': '甲'});
      await db.wipe();
      expect(await refs(note), isEmpty);
    });
  });

  test('置顶的笔记排在前面，其余按最后修改时间', () async {
    const other = '0192a000-0000-7000-8000-000000000002';
    await store.write('note', note, {'format': 'markdown', 'pinned': 1});
    await store.write('note', other, {'format': 'markdown', 'pinned': 0});
    final pinnedKey = await _sortKey(db, note);
    final otherKey = await _sortKey(db, other);
    expect(pinnedKey, startsWith('1|'));
    expect(otherKey, startsWith('0|'));
    // 降序排列时置顶在前；同为未置顶时后修改的在前
    expect(pinnedKey.compareTo(otherKey), greaterThan(0));
    await store.write('note', note, {'pinned': 0});
    expect(
      (await _sortKey(db, note)).compareTo(await _sortKey(db, other)),
      greaterThan(0),
    );
  });

  group('推送批次大小', () {
    test('按估算的请求体大小分批，单条超大的变更也能单独推送', () async {
      final big = '长' * 90000; // 约 27 万字节，加密后更大
      for (var i = 0; i < 12; i++) {
        await store.write('note', '0192a000-0000-7000-8000-00000000010$i', {
          'format': 'markdown',
          'body': big,
        });
      }
      final first = await store.pending(maxBytes: 1000000);
      expect(first.length, inInclusiveRange(1, 3));
      final one = await store.pending(maxBytes: 10);
      expect(one, hasLength(1));
      final all = await store.pending(maxBytes: 100000000);
      expect(all, hasLength(12));
    });
  });

  test('从 schema v1 升级：保留原有数据并建立关联索引表', () async {
    final dir = await Directory.systemTemp.createTemp('jikelog-db');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/v1.sqlite');
    // 先建出完整结构，再退回 v1：删掉 v2 新增的表并改回版本号
    final v2 = AppDatabase(NativeDatabase(file));
    await RecordStore(
      v2,
      HybridClock(installationId: 'x'),
    ).write('worklog', wl1, {'date': '2026-10-01', 'content': '旧数据'});
    await v2.customStatement('DROP TABLE record_refs');
    await v2.customStatement('DROP TABLE calendar_links');
    await v2.customStatement('PRAGMA user_version = 1');
    await v2.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final s = RecordStore(upgraded, HybridClock(installationId: 'x'));
    expect((await s.get(wl1))!.fields['content'], '旧数据');
    await s.write('note', note, {'format': 'markdown', 'tags': '升级后'});
    expect((await upgraded.refsOf(note)).single.value, '升级后');
    // v3 的系统日历对应表同样建好
    expect(await upgraded.select(upgraded.calendarLinks).get(), isEmpty);
  });

  test('从 schema v2 升级：建立系统日历对应表', () async {
    final dir = await Directory.systemTemp.createTemp('jikelog-db');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/v2.sqlite');
    final v3 = AppDatabase(NativeDatabase(file));
    await RecordStore(
      v3,
      HybridClock(installationId: 'x'),
    ).write('note', note, {'format': 'markdown', 'tags': '保留'});
    await v3.customStatement('DROP TABLE calendar_links');
    await v3.customStatement('PRAGMA user_version = 2');
    await v3.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    expect((await upgraded.refsOf(note)).single.value, '保留');
    await upgraded
        .into(upgraded.calendarLinks)
        .insert(
          CalendarLinksCompanion.insert(
            memoId: 'm',
            eventId: 'e',
            signature: 's',
          ),
        );
    expect(await upgraded.select(upgraded.calendarLinks).get(), hasLength(1));
    await upgraded.wipe();
    expect(await upgraded.select(upgraded.calendarLinks).get(), isEmpty);
  });

  test('备忘录按时间排序', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final s = RecordStore(db, HybridClock(installationId: 'x'));
    await s.write('memo', wl1, {'content': '晚', 'at': 1791553544000});
    expect(await _sortKey(db, wl1), '1791553544000');
    expect(RecordStore.memoSortKey(5), '0000000000005');
  });
}

Future<String> _sortKey(AppDatabase db, String id) async => (await (db.select(
  db.records,
)..where((t) => t.id.equals(id))).getSingle()).sortKey;
