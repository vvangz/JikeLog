import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/sync_engine.dart';

import '../../support/fake_sync_server.dart';

/// 一台模拟设备：独立的本地库、时钟与连接。
class Device {
  Device(FakeSyncServer server, String name, {int Function()? nowMs})
    : db = AppDatabase(NativeDatabase.memory()),
      transport = FakeTransport(server) {
    store = RecordStore(db, HybridClock(installationId: name, nowMs: nowMs));
    engine = SyncEngine(
      transport: transport,
      store: store,
      db: db,
      debounce: Duration.zero,
    );
  }

  final AppDatabase db;
  final FakeTransport transport;
  late final RecordStore store;
  late final SyncEngine engine;

  Future<Map<String, Object?>?> fields(String id) async {
    final r = await store.get(id);
    return r == null || r.deleted ? null : r.fields;
  }

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

void main() {
  // 每台模拟设备各有一个内存数据库，属于预期行为
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeSyncServer server;
  late Device a;
  late Device b;
  var now = 1791553544000;

  setUp(() {
    server = FakeSyncServer();
    a = Device(server, 'device-a', nowMs: () => now);
    b = Device(server, 'device-b', nowMs: () => now);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  const id = '0192a000-0000-7000-8000-000000000001';

  test('离线创建后同步，另一台设备拉到相同内容', () async {
    a.transport.online = false;
    await a.store.write('worklog', id, {
      'date': '2026-10-09',
      'location': '公司',
      'content': '内容',
    });
    await a.engine.sync();
    expect(a.engine.status.phase, SyncPhase.offline);
    expect((await a.store.pending()).length, 1);

    a.transport.online = true;
    await a.engine.sync();
    expect(a.engine.status.phase, SyncPhase.idle);
    expect(await a.store.pending(), isEmpty);
    expect(server.records[id]!.fields['content'], '内容');

    await b.engine.sync();
    expect(await b.fields(id), {
      'date': '2026-10-09',
      'location': '公司',
      'content': '内容',
    });
    expect(await b.db.meta(SyncEngine.sinceKey), '1');
  });

  test('两台设备分别修改不同段落时合并，最终一致', () async {
    final base = List.generate(10, (i) => '第$i段：工作内容。').join('\n');
    await a.store.write('worklog', id, {'date': '2026-10-09', 'content': base});
    await a.engine.sync();
    await b.engine.sync();

    now += 10;
    await a.store.write('worklog', id, {
      'content': base.replaceFirst('第1段：工作内容。', '第1段：工作内容，补充 A。'),
    });
    now += 10;
    await b.store.write('worklog', id, {
      'content': base.replaceFirst('第8段：工作内容。', '第8段：工作内容，补充 B。'),
    });
    await a.engine.sync();
    await b.engine.sync(); // 服务端合并，返回 merged
    await a.engine.sync();

    final expected = base
        .replaceFirst('第1段：工作内容。', '第1段：工作内容，补充 A。')
        .replaceFirst('第8段：工作内容。', '第8段：工作内容，补充 B。');
    expect((await a.fields(id))!['content'], expected);
    expect((await b.fields(id))!['content'], expected);
    expect(await b.store.pending(), isEmpty, reason: '合并结果不能被本地旧值再次覆盖');
    expect((await b.store.get(id))!.hasConflict, isFalse);
  });

  test('同一字段冲突时最后修改胜出，落败的设备标记冲突', () async {
    await a.store.write('worklog', id, {
      'date': '2026-10-09',
      'location': '公司',
    });
    await a.engine.sync();
    await b.engine.sync();

    now += 10;
    await b.store.write('worklog', id, {'location': '家'}); // 较早
    now += 10;
    await a.store.write('worklog', id, {'location': '客户现场'}); // 较晚
    await a.engine.sync();
    await b.engine.sync();
    await a.engine.sync();

    expect((await a.fields(id))!['location'], '客户现场');
    expect((await b.fields(id))!['location'], '客户现场');
    expect((await b.store.get(id))!.hasConflict, isTrue);
    await b.store.clearConflict(id);
    expect((await b.store.get(id))!.hasConflict, isFalse);
  });

  test('删除胜过编辑', () async {
    await a.store.write('worklog', id, {'date': '2026-10-09', 'content': 'x'});
    await a.engine.sync();
    await b.engine.sync();
    await a.store.remove(id);
    now += 10;
    await b.store.write('worklog', id, {'content': '离线时的修改'});
    await a.engine.sync();
    await b.engine.sync();
    expect(await a.fields(id), isNull);
    expect(await b.fields(id), isNull);
  });

  test('从未同步过的记录删除后不会推送', () async {
    await a.store.write('worklog', id, {'date': '2026-10-09'});
    await a.store.remove(id);
    await a.engine.sync();
    expect(a.transport.pushCount, 0);
    expect(server.records, isEmpty);
  });

  test('推送期间继续编辑的字段保持待推送', () async {
    await a.store.write('worklog', id, {'date': '2026-10-09', 'content': 'v1'});
    a.transport.beforePush = () async {
      a.transport.beforePush = null;
      now += 10;
      await a.store.write('worklog', id, {'content': 'v2'});
    };
    await a.engine.sync();
    expect(server.records[id]!.fields['content'], 'v2');
    expect(await a.store.pending(), isEmpty);
  });

  test('被拒绝的变更记录原因，不再自动重试，再次修改后重试', () async {
    server.rejectIds.add(id);
    await a.store.write('worklog', id, {'date': '2026-10-09'});
    await a.engine.sync();
    expect((await a.store.get(id))!.syncError, 'VALIDATION_FAILED');
    final pushes = a.transport.pushCount;
    await a.engine.sync();
    expect(a.transport.pushCount, pushes);

    server.rejectIds.clear();
    await a.store.write('worklog', id, {'date': '2026-10-10'});
    await a.engine.sync();
    expect(server.records[id]!.fields['date'], '2026-10-10');
  });

  test('值未变化的写入不产生新的修改', () async {
    await a.store.write('worklog', id, {'date': '2026-10-09'});
    await a.engine.sync();
    await a.store.write('worklog', id, {'date': '2026-10-09'});
    expect(await a.store.pending(), isEmpty);
  });

  test('随机操作与随机同步顺序下，所有设备最终收敛', () async {
    final rnd = Random(42);
    final c = Device(server, 'device-c', nowMs: () => now);
    addTearDown(c.close);
    final devices = [a, b, c];
    final ids = List.generate(
      4,
      (i) => '0192a000-0000-7000-8000-00000000010$i',
    );
    const words = ['会议', '编码', '评审', '出差', '培训'];
    for (var step = 0; step < 200; step++) {
      now += 1 + rnd.nextInt(5);
      final d = devices[rnd.nextInt(devices.length)];
      final rid = ids[rnd.nextInt(ids.length)];
      switch (rnd.nextInt(10)) {
        case < 6:
          final cur = await d.fields(rid);
          final content = (cur?['content'] as String? ?? '');
          await d.store.write('worklog', rid, {
            'date': '2026-10-${10 + rnd.nextInt(9)}',
            'content': '$content${words[rnd.nextInt(words.length)]}\n',
            if (rnd.nextBool()) 'location': words[rnd.nextInt(words.length)],
          });
        case < 7:
          await d.store.remove(rid);
        default:
          await d.engine.sync();
      }
    }
    // 收尾：轮流同步直到没有待推送的修改
    for (var round = 0; round < 3; round++) {
      for (final d in devices) {
        await d.engine.sync();
      }
    }
    for (final rid in ids) {
      final expected = server.records[rid];
      final want = expected == null || expected.deleted
          ? null
          : expected.fields;
      for (final d in devices) {
        expect(await d.fields(rid), want, reason: '记录 $rid 在设备上不一致');
      }
    }
  });
}
