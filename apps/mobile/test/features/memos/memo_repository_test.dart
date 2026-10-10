import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/sync_engine.dart';
import 'package:jikelog/features/memos/memo_models.dart';
import 'package:jikelog/features/memos/memo_repository.dart';

import '../../support/fake_sync_server.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late RecordStore store;
  late SyncEngine engine;
  late MemoRepository repo;
  var now = 1791553544000;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = RecordStore(
      db,
      HybridClock(installationId: 'device-a', nowMs: () => now += 10),
    );
    final transport = FakeTransport(FakeSyncServer())..online = false;
    engine = SyncEngine(transport: transport, store: store, db: db);
    repo = MemoRepository(db: db, store: store, engine: engine);
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  final oct12 = DateTime(2026, 10, 12, 15, 30);

  test('新建与读取：字段按服务端格式写入', () async {
    final id = await repo.create(
      content: '周会\n准备材料',
      at: oct12,
      reminders: [15, 0, 15],
    );
    final m = (await repo.get(id))!;
    expect(m.content, '周会\n准备材料');
    expect(m.title, '周会');
    expect(m.at, oct12);
    expect(m.reminders, [0, 15]);
    expect(m.fireTimes, [oct12, oct12.subtract(const Duration(minutes: 15))]);
    expect(m.pending, isTrue);
    final rec = (await store.get(id))!;
    expect(rec.fields['reminders'], '0,15');
    expect(rec.fields['at'], oct12.millisecondsSinceEpoch);
    expect(rec.fields['done'], 0);
  });

  test('内容不能为空', () async {
    expect(() => repo.create(content: '  ', at: oct12), throwsArgumentError);
    final id = await repo.create(content: '有内容', at: oct12);
    expect(() => repo.update(id, content: ''), throwsArgumentError);
  });

  test('全天备忘对齐到当天 9:00', () async {
    final id = await repo.create(content: '体检', at: oct12, allDay: true);
    expect((await repo.get(id))!.at, DateTime(2026, 10, 12, 9));
    final other = await repo.create(content: '出差', at: oct12);
    await repo.update(other, allDay: true);
    final m = (await repo.get(other))!;
    expect(m.allDay, isTrue);
    expect(m.at, DateTime(2026, 10, 12, 9));
  });

  test('按时间排序，修改与删除', () async {
    final late = await repo.create(content: '晚', at: oct12);
    final early = await repo.create(
      content: '早',
      at: oct12.subtract(const Duration(days: 20)),
    );
    expect((await repo.watchAll().first).map((m) => m.id), [early, late]);

    await repo.update(late, done: true, reminders: const []);
    final m = (await repo.get(late))!;
    expect(m.done, isTrue);
    expect(m.reminders, isEmpty);

    await repo.delete(early);
    expect(await repo.get(early), isNull);
    expect((await repo.watchAll().first).map((m) => m.id), [late]);
  });

  test('watch 在删除后为 null', () async {
    final id = await repo.create(content: '临时', at: oct12);
    final stream = repo.watch(id);
    expect((await stream.first)!.content, '临时');
    await repo.delete(id);
    expect(await repo.watch(id).first, isNull);
  });

  group('模型', () {
    test('提醒的编码、解析与文字', () {
      expect(encodeReminders([60, 0, 5, 0]), '0,5,60');
      expect(encodeReminders(const []), '');
      expect(parseReminders('0,15,x,-1,99999,15'), [0, 15]);
      expect(parseReminders(''), isEmpty);
      expect(reminderLabel(0), '准时');
      expect(reminderLabel(0, allDay: true), '当天 9:00');
      expect(reminderLabel(15), '提前 15 分钟');
      expect(reminderLabel(120), '提前 2 小时');
      expect(reminderLabel(2880), '提前 2 天');
    });

    test('逾期：全天备忘过了当天才算，已完成不算', () {
      final now = DateTime(2026, 10, 12, 18);
      Memo memo({
        required DateTime at,
        bool allDay = false,
        bool done = false,
      }) => Memo(
        id: 'm',
        content: 'x',
        at: at,
        allDay: allDay,
        done: done,
        updatedAt: now,
      );
      expect(memo(at: DateTime(2026, 10, 12, 9)).overdue(now), isTrue);
      expect(
        memo(at: DateTime(2026, 10, 12, 9), allDay: true).overdue(now),
        isFalse,
      );
      expect(
        memo(at: DateTime(2026, 10, 11, 9), allDay: true).overdue(now),
        isTrue,
      );
      expect(
        memo(at: DateTime(2026, 10, 11, 9), done: true).overdue(now),
        isFalse,
      );
      expect(memo(at: now).title, 'x');
      expect(
        Memo(id: 'e', content: '\n ', at: now, updatedAt: now).title,
        '（空白备忘）',
      );
      expect(
        defaultMemoTime(DateTime(2026, 10, 12, 23, 20)),
        DateTime(2026, 10, 13),
      );
    });
  });
}
