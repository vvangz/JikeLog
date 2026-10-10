import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/sync_engine.dart';
import 'package:jikelog/features/ledger/ledger_models.dart';
import 'package:jikelog/features/ledger/ledger_presets.dart';
import 'package:jikelog/features/ledger/ledger_repository.dart';

import '../../support/fake_sync_server.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late RecordStore store;
  late SyncEngine engine;
  late LedgerRepository repo;
  var now = 1791553544000;
  const user = '0192a000-0000-7000-8000-000000000001';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = RecordStore(
      db,
      HybridClock(installationId: 'device-a', nowMs: () => now += 10),
    );
    final transport = FakeTransport(FakeSyncServer())..online = false;
    engine = SyncEngine(transport: transport, store: store, db: db);
    repo = LedgerRepository(db: db, store: store, engine: engine);
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  final day = DateTime(2026, 10, 11);

  test('预置分类：ID 由账号确定、重复初始化不重复写入、时钟最早', () async {
    await repo.ensurePresets(user);
    await repo.ensurePresets(user);
    final cats = await repo.watchCategories().first;
    expect(cats, hasLength(presetCategories.length));
    final food = cats.firstWhere((c) => c.name == '餐饮');
    expect(food.id, presetCategoryId(user, 'expense.food'));
    expect(
      presetCategoryId(user, 'expense.food'),
      isNot(presetCategoryId('other', 'expense.food')),
    );
    final lunch = cats.firstWhere((c) => c.name == '午餐');
    expect(lunch.parentId, food.id);
    final rec = (await store.get(food.id))!;
    expect(rec.clocks.values.toSet(), {RecordStore.seedClock});
    expect(rec.dirty, isTrue);

    // 用户改名后再初始化不会覆盖
    await repo.updateCategory(food.id, name: '吃饭');
    await repo.ensurePresets(user);
    final renamed = (await repo.watchCategories().first).firstWhere(
      (c) => c.id == food.id,
    );
    expect(renamed.name, '吃饭');
  });

  test('流水：校验字段约束，按服务端格式写入，修改与删除', () async {
    final cash = await repo.createAccount(
      name: '现金',
      type: AccountType.cash,
      initialBalance: 10000,
    );
    final card = await repo.createAccount(
      name: '信用卡',
      type: AccountType.credit,
      initialBalance: -500,
    );
    final cat = await repo.createCategory(
      name: '餐饮',
      kind: CategoryKind.expense,
    );

    expect(
      () => repo.createEntry(
        EntryDraft(
          type: EntryType.expense,
          amount: 100,
          date: day,
          accountId: cash,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.createEntry(
        EntryDraft(
          type: EntryType.transfer,
          amount: 100,
          date: day,
          accountId: cash,
          toAccountId: cash,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.createEntry(
        EntryDraft(
          type: EntryType.expense,
          amount: 0,
          date: day,
          accountId: cash,
          categoryId: cat,
        ),
      ),
      throwsArgumentError,
    );

    final id = await repo.createEntry(
      EntryDraft(
        type: EntryType.expense,
        amount: 3850,
        date: day,
        accountId: cash,
        categoryId: cat,
        note: '午饭',
        fee: 99,
      ),
    );
    final rec = (await store.get(id))!;
    expect(rec.fields['amount'], '3850');
    expect(rec.fields['date'], '2026-10-11');
    expect(rec.fields['fee'], isNull, reason: '只有转账有手续费');
    expect(rec.fields['toAccountId'], isNull);

    await repo.updateEntry(
      id,
      EntryDraft(
        type: EntryType.transfer,
        amount: 20000,
        fee: 100,
        date: day,
        accountId: cash,
        toAccountId: card,
      ),
    );
    final e = (await repo.getEntry(id))!;
    expect(e.type, EntryType.transfer);
    expect(e.fee, 100);
    expect(e.categoryId, isNull);
    expect(e.toAccountId, card);

    await repo.deleteEntry(id);
    expect(await repo.getEntry(id), isNull);
    expect(await repo.watchEntries().first, isEmpty);

    final accounts = await repo.watchAccounts().first;
    expect(accounts.firstWhere((a) => a.id == card).initialBalance, -500);
  });

  test('删除账户与分类：有流水引用时只隐藏', () async {
    final used = await repo.createAccount(name: '在用', type: AccountType.debit);
    final unused = await repo.createAccount(
      name: '没用',
      type: AccountType.other,
    );
    final parent = await repo.createCategory(
      name: '交通',
      kind: CategoryKind.expense,
    );
    final child = await repo.createCategory(
      name: '打车',
      kind: CategoryKind.expense,
      parentId: parent,
    );
    final spare = await repo.createCategory(
      name: '空分类',
      kind: CategoryKind.expense,
    );
    await repo.createEntry(
      EntryDraft(
        type: EntryType.expense,
        amount: 100,
        date: day,
        accountId: used,
        categoryId: child,
      ),
    );

    expect(await repo.deleteAccount(used), isFalse);
    expect(await repo.deleteAccount(unused), isTrue);
    final accounts = await repo.watchAccounts().first;
    expect(accounts.single.archived, isTrue);

    expect(
      await repo.deleteCategory(parent, preset: false),
      isFalse,
      reason: '二级分类有流水',
    );
    expect(
      await repo.deleteCategory(spare, preset: true),
      isFalse,
      reason: '预置分类只隐藏',
    );
    final cats = {for (final c in await repo.watchCategories().first) c.id: c};
    expect(
      cats[parent]!.archived && cats[child]!.archived && cats[spare]!.archived,
      isTrue,
    );

    final gone = await repo.createCategory(
      name: '临时',
      kind: CategoryKind.income,
    );
    expect(await repo.deleteCategory(gone, preset: false), isTrue);
    await repo.updateCategory(
      parent,
      archived: false,
      name: '出行',
      icon: 'flight',
    );
    final restored = (await repo.watchCategories().first).firstWhere(
      (c) => c.id == parent,
    );
    expect(
      [restored.archived, restored.name, restored.icon],
      [false, '出行', 'flight'],
    );
  });

  test('借贷：新建时记下借出流水，修改、结清与删除', () async {
    final cash = await repo.createAccount(name: '现金', type: AccountType.cash);
    expect(
      () => repo.createLoan(
        direction: LoanDirection.lend,
        counterparty: ' ',
        amount: 100,
        accountId: cash,
        date: day,
      ),
      throwsArgumentError,
    );
    final loan = await repo.createLoan(
      direction: LoanDirection.lend,
      counterparty: ' 李四 ',
      amount: 50000,
      accountId: cash,
      date: day,
      dueDate: DateTime(2026, 12, 31),
      note: '周转',
    );
    final l = (await repo.watchLoans().first).single;
    expect(l.counterparty, '李四');
    expect(l.dueDate, DateTime(2026, 12, 31));
    final entries = await repo.watchEntries().first;
    expect(entries.single.type, EntryType.lend);
    expect(entries.single.loanId, loan);
    expect(entries.single.note, '周转');

    await repo.createEntry(
      EntryDraft(
        type: EntryType.collect,
        amount: 50000,
        date: day,
        accountId: cash,
        loanId: loan,
      ),
    );
    await repo.updateLoan(loan, settled: true, clearDueDate: true, note: '已还清');
    final settled = (await repo.watchLoans().first).single;
    expect(
      [settled.settled, settled.dueDate, settled.note],
      [true, null, '已还清'],
    );

    await repo.deleteLoan(loan);
    expect(await repo.watchLoans().first, isEmpty);
    expect(await repo.watchEntries().first, isEmpty);
    await repo.updateAccount(
      cash,
      name: '钱包',
      type: AccountType.other,
      initialBalance: 300,
      archived: true,
    );
    final a = (await repo.watchAccounts().first).single;
    expect(
      [a.name, a.type, a.initialBalance, a.archived],
      ['钱包', AccountType.other, 300, true],
    );
  });

  test('流水按日期倒序', () async {
    final cash = await repo.createAccount(name: '现金', type: AccountType.cash);
    final cat = await repo.createCategory(
      name: '工资',
      kind: CategoryKind.income,
    );
    final old = await repo.createEntry(
      EntryDraft(
        type: EntryType.income,
        amount: 1,
        date: DateTime(2026, 9, 1),
        accountId: cash,
        categoryId: cat,
      ),
    );
    final recent = await repo.createEntry(
      EntryDraft(
        type: EntryType.income,
        amount: 1,
        date: day,
        accountId: cash,
        categoryId: cat,
      ),
    );
    expect((await repo.watchEntries().first).map((e) => e.id), [recent, old]);
  });

  test('收款还款：方向必须一致、不能超过待收待还；修改不存在的流水报错', () async {
    final cash = await repo.createAccount(name: '现金', type: AccountType.cash);
    final lent = await repo.createLoan(
      direction: LoanDirection.lend,
      counterparty: '李四',
      amount: 1000,
      accountId: cash,
      date: day,
    );
    EntryDraft back(EntryType t, int amount) => EntryDraft(
      type: t,
      amount: amount,
      date: day,
      accountId: cash,
      loanId: lent,
    );
    expect(
      () => repo.createEntry(back(EntryType.repay, 100)),
      throwsArgumentError,
    );
    expect(
      () => repo.createEntry(back(EntryType.collect, 1001)),
      throwsArgumentError,
    );
    final first = await repo.createEntry(back(EntryType.collect, 600));
    expect(
      () => repo.createEntry(back(EntryType.collect, 500)),
      throwsArgumentError,
    );
    // 修改自己时不把自己算进已收
    await repo.updateEntry(first, back(EntryType.collect, 1000));
    expect((await repo.getEntry(first))!.amount, 1000);
    expect(
      () => repo.createEntry(
        EntryDraft(
          type: EntryType.collect,
          amount: 1,
          date: day,
          accountId: cash,
          loanId: 'missing',
        ),
      ),
      throwsArgumentError,
    );
    await repo.deleteEntry(first);
    expect(
      () => repo.updateEntry(first, back(EntryType.collect, 1)),
      throwsStateError,
    );
  });

  test('字段不完整的流水也阻止删除账户；金额不为正的流水不计入', () async {
    final cash = await repo.createAccount(name: '现金', type: AccountType.cash);
    await store.write('ledger_entry', 'broken', {
      'type': 'expense',
      'amount': '-5',
      'date': '2026-10-11',
      'accountId': cash,
    });
    expect(await repo.watchEntries().first, isEmpty);
    expect(await repo.deleteAccount(cash), isFalse);
    expect((await repo.watchAccounts().first).single.archived, isTrue);
  });
}
