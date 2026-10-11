import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/schema.dart';
import 'package:jikelog/features/search/search_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late RecordStore store;
  late SearchRepository repo;
  var now = 1791553544000;
  var seq = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = RecordStore(
      db,
      HybridClock(installationId: 'device-a', nowMs: () => now += 10),
    );
    repo = SearchRepository(db);
  });

  tearDown(() => db.close());

  String id() =>
      '0192a000-0000-7000-8000-${(++seq).toRadixString(16).padLeft(12, '0')}';

  Future<String> put(String entity, Map<String, Object?> fields) async {
    final i = id();
    await store.write(entity, i, fields);
    return i;
  }

  Future<List<String>> ids(SearchQuery q) async =>
      (await repo.search(q)).hits.map((h) => h.record.id).toList();

  test('四个模块都能搜到；结果按日期从新到旧，统计各模块条数', () async {
    final w = await put(Entities.worklog, {
      'date': '2026-10-01',
      'location': '上海',
      'content': '项目评审会议',
    });
    final n = await put(Entities.note, {'title': '评审记录', 'body': '要点'});
    final m = await put(Entities.memo, {
      'content': '准备评审材料',
      'at': DateTime(2026, 10, 20).millisecondsSinceEpoch,
    });
    final e = await put(Entities.ledgerEntry, {
      'type': 'expense',
      'amount': '100',
      'date': '2026-10-05',
      'note': '评审后聚餐',
    });
    await put(Entities.worklog, {'date': '2026-10-02', 'content': '无关'});

    final r = await repo.search(const SearchQuery(text: '评审'));
    expect(r.hits.map((h) => h.record.id).toList()..remove(n), [m, e, w]);
    expect(r.counts, {
      SearchModule.worklog: 1,
      SearchModule.note: 1,
      SearchModule.memo: 1,
      SearchModule.ledger: 1,
    });
    expect(r.truncated, isFalse);
    final hit = r.hits.firstWhere((h) => h.record.id == w);
    expect(
      (hit.module, hit.day, hit.title, hit.body),
      (SearchModule.worklog, '2026-10-01', '上海', '项目评审会议'),
    );
  });

  test('短关键词用 LIKE、长关键词用全文索引，都不区分大小写；特殊字符按字面匹配', () async {
    final a = await put(Entities.note, {
      'title': 'Flutter 笔记',
      'body': '100% 完成_了',
    });
    final b = await put(Entities.note, {'title': '其他', 'body': '1000 完成'});
    expect(await ids(const SearchQuery(text: 'flu')), [a]);
    expect(await ids(const SearchQuery(text: 'fl')), [a]);
    expect(await ids(const SearchQuery(text: '笔')), [a]);
    expect(await ids(const SearchQuery(text: '0%')), [a]);
    expect(await ids(const SearchQuery(text: '成_')), [a]);
    expect((await ids(const SearchQuery(text: '完成'))).toSet(), {a, b});
    expect(await ids(const SearchQuery(text: '"引号"')), isEmpty);
  });

  test('多个关键词须同时满足', () async {
    final a = await put(Entities.memo, {'content': '周五 交房租', 'at': 1});
    await put(Entities.memo, {'content': '周五 开会', 'at': 2});
    expect(await ids(const SearchQuery(text: ' 周五   房租 ')), [a]);
    expect(await ids(const SearchQuery(text: '房租 开会')), isEmpty);
    expect(await ids(const SearchQuery(text: '   ')), isEmpty);
  });

  test('按模块和日期区间筛选', () async {
    final w = await put(Entities.worklog, {
      'date': '2026-10-01',
      'content': '出差',
    });
    final w2 = await put(Entities.worklog, {
      'date': '2026-10-09',
      'content': '出差',
    });
    final m = await put(Entities.memo, {
      'content': '出差报销',
      'at': DateTime(2026, 10, 5, 9).millisecondsSinceEpoch,
    });
    expect(
      await ids(const SearchQuery(text: '出差', modules: {SearchModule.worklog})),
      [w2, w],
    );
    expect(
      await ids(
        SearchQuery(
          text: '出差',
          from: DateTime(2026, 10, 1, 18),
          to: DateTime(2026, 10, 5),
        ),
      ),
      [m, w],
    );
    expect(await ids(SearchQuery(text: '出差', from: DateTime(2026, 10, 6))), [
      w2,
    ]);
  });

  test('命中分类（含其二级分类）、账户、借贷对方时带出相关流水；它们本身不是结果', () async {
    final food = await put(Entities.ledgerCategory, {
      'name': '餐饮',
      'kind': 'expense',
    });
    final lunch = await put(Entities.ledgerCategory, {
      'name': '午餐',
      'kind': 'expense',
      'parentId': food,
    });
    final alipay = await put(Entities.ledgerAccount, {'name': '支付宝'});
    final cash = await put(Entities.ledgerAccount, {'name': '现金'});
    final loan = await put(Entities.ledgerLoan, {
      'counterparty': '李四',
      'note': '',
    });
    Future<String> entry(Map<String, Object?> f) => put(Entities.ledgerEntry, {
      'type': 'expense',
      'amount': '100',
      'date': '2026-10-0${seq % 9 + 1}',
      'note': '',
      ...f,
    });
    final e1 = await entry({'categoryId': lunch, 'accountId': cash});
    final e2 = await entry({
      'categoryId': food,
      'accountId': alipay,
      'note': '请客',
    });
    final e3 = await entry({
      'type': 'transfer',
      'accountId': cash,
      'toAccountId': alipay,
    });
    final e4 = await entry({'type': 'lend', 'accountId': cash, 'loanId': loan});

    expect((await ids(const SearchQuery(text: '餐饮'))).toSet(), {e1, e2});
    expect(await ids(const SearchQuery(text: '午餐')), [e1]);
    expect((await ids(const SearchQuery(text: '支付宝'))).toSet(), {e2, e3});
    expect(await ids(const SearchQuery(text: '李四')), [e4]);
    // 关键词可以分别命中备注和分类
    expect(await ids(const SearchQuery(text: '请客 餐饮')), [e2]);
    expect(await ids(const SearchQuery(text: '请客 午餐')), isEmpty);
  });

  test('修改与删除后索引随之更新；同步下来的记录同样建立索引', () async {
    final a = await put(Entities.note, {'title': '旧标题', 'body': ''});
    await store.write(Entities.note, a, {'title': '新标题'});
    expect(await ids(const SearchQuery(text: '旧标题')), isEmpty);
    expect(await ids(const SearchQuery(text: '新标题')), [a]);
    await store.remove(a);
    expect(await ids(const SearchQuery(text: '新标题')), isEmpty);

    final b = id();
    await store.applyRemote(
      RemoteRecord(
        entity: Entities.memo,
        id: b,
        version: 1,
        serverSeq: 1,
        deleted: false,
        fields: {'content': '来自另一台设备', 'at': 1},
        clocks: {'content': '1791553544000-0000-device-b'},
      ),
    );
    expect(await ids(const SearchQuery(text: '另一台')), [b]);
    await store.applyRemote(
      RemoteRecord(
        entity: Entities.memo,
        id: b,
        version: 2,
        serverSeq: 2,
        deleted: true,
        fields: const {},
        clocks: const {},
      ),
    );
    expect(await ids(const SearchQuery(text: '另一台')), isEmpty);
  });

  test('最多返回 200 条，统计仍是全部命中数', () async {
    for (var i = 0; i < 205; i++) {
      await put(Entities.memo, {'content': '批量 $i', 'at': i});
    }
    final r = await repo.search(const SearchQuery(text: '批量'));
    expect(r.hits, hasLength(SearchRepository.maxHits));
    expect(r.counts[SearchModule.memo], 205);
    expect(r.total, 205);
    expect(r.truncated, isTrue);
  });

  test('退出登录清空本地数据时一并清空索引', () async {
    await put(Entities.note, {'title': '机密', 'body': ''});
    await db.wipe();
    expect(await ids(const SearchQuery(text: '机密')), isEmpty);
  });

  test('1 万条记录时查询在 100ms 量级', () async {
    await db.transaction(() async {
      for (var i = 0; i < 10000; i++) {
        await store.write(Entities.worklog, id(), {
          'date': '2026-01-${(i % 28 + 1).toString().padLeft(2, '0')}',
          'location': '地点$i',
          'content': '第 $i 天的工作内容，包含会议、编码与评审。',
        });
      }
    });
    final sw = Stopwatch()..start();
    final long = await repo.search(const SearchQuery(text: '地点9999'));
    final longMs = sw.elapsedMilliseconds;
    sw.reset();
    final short = await repo.search(const SearchQuery(text: '9 编码'));
    final shortMs = sw.elapsedMilliseconds;
    expect(long.hits, hasLength(1));
    expect(short.total, greaterThan(1000));
    // CI 机器较慢，留出余量；本机实测见开发日志
    expect(longMs, lessThan(500));
    expect(shortMs, lessThan(1000));
    stdout.writeln('10k 记录：长关键词 ${longMs}ms，短关键词 ${shortMs}ms');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('本地库从 v3 升级时由已有记录重建索引', () async {
    final dir = await Directory.systemTemp.createTemp('jikelog-search');
    final file = File('${dir.path}/db.sqlite');
    try {
      var old = AppDatabase(NativeDatabase(file));
      final s = RecordStore(old, HybridClock(installationId: 'x'));
      final a = id();
      await s.write(Entities.note, a, {'title': '升级前的笔记', 'body': ''});
      // 退回 v3：没有搜索表
      await old.customStatement('DROP TABLE search_fts');
      await old.customStatement('DROP TABLE search_docs');
      await old.customStatement('PRAGMA user_version = 3');
      await old.close();

      old = AppDatabase(NativeDatabase(file));
      expect(
        await SearchRepository(old)
            .search(const SearchQuery(text: '升级前'))
            .then((r) => r.hits.map((h) => h.record.id).toList()),
        [a],
      );
      await old.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
