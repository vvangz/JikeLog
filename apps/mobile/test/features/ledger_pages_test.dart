import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/router.dart';
import 'package:jikelog/features/ledger/ledger_models.dart';
import 'package:jikelog/features/ledger/ledger_presets.dart';
import 'package:jikelog/features/ledger/ledger_repository.dart';

import '../support/app_harness.dart';
import '../support/fake_backend.dart';
import '../support/fake_sync_server.dart';

const _user = '0192a000-0000-7000-8000-000000000001';

ProviderContainer _c(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

LedgerRepository _repo(WidgetTester tester) =>
    _c(tester).read(ledgerRepositoryProvider);

Future<T> _run<T>(WidgetTester tester, Future<T> Function() body) async {
  T? result;
  var done = false;
  Object? error;
  unawaited(
    body().then(
      (v) {
        result = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: '操作未完成');
  await settleApp(tester);
  return result as T;
}

Future<void> _go(WidgetTester tester, String path) async {
  _c(tester).read(routerProvider).go(path);
  await settleApp(tester);
}

Future<void> _push(WidgetTester tester, String path) async {
  unawaited(_c(tester).read(routerProvider).push(path));
  await settleApp(tester);
}

Future<List<Entry>> _entries(WidgetTester tester) async =>
    (await tester.runAsync(() => _repo(tester).watchEntries().first))!;

Future<String> _account(
  WidgetTester tester, {
  String name = '现金',
  AccountType type = AccountType.cash,
  int balance = 0,
}) => _run(
  tester,
  () =>
      _repo(tester)
          .createAccount(name: name, type: type, initialBalance: balance),
);

Future<void> _tapText(WidgetTester tester, String text) =>
    tapAndSettle(tester, find.text(text).last);

String _preset(String key) => presetCategoryId(_user, key);

void main() {
  tearDown(TestHooks.reset);

  testWidgets('首次进入写入预置分类；没有账户时先添加账户，再记一笔支出', (tester) async {
    final server = FakeSyncServer();
    await pumpApp(tester, syncServer: server);
    await _go(tester, '/ledger');
    expect(find.text('这个月还没有记账'), findsOneWidget);
    final cats = (await tester.runAsync(
      () => _repo(tester).watchCategories().first,
    ))!;
    expect(cats, hasLength(presetCategories.length));

    await tapAndSettle(tester, find.byKey(const Key('entry-create')));
    expect(find.text('还没有账户'), findsOneWidget);
    await _tapText(tester, '添加账户');
    await tester.enterText(find.byKey(const Key('account-name')), '钱包');
    await tester.enterText(find.byKey(const Key('account-balance')), '100');
    await tapAndSettle(tester, find.byKey(const Key('account-save')));

    await tester.enterText(find.byKey(const Key('entry-amount')), '38.5');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('请选择账户'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('entry-account')));
    await _tapText(tester, '钱包（现金）');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('请选择分类'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(Key('category-${_preset('expense.food')}')),
    );
    await tapAndSettle(
      tester,
      find.byKey(Key('category-${_preset('expense.food.lunch')}')),
    );
    await tester.enterText(find.byKey(const Key('entry-note')), '牛肉面');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));

    expect(find.text('餐饮 · 午餐'), findsOneWidget);
    expect(find.textContaining('牛肉面'), findsOneWidget);
    expect(find.text('-38.50'), findsWidgets);
    final e = (await _entries(tester)).single;
    expect([e.amount, e.categoryId], [3850, _preset('expense.food.lunch')]);

    await tapAndSettle(tester, find.byKey(const Key('ledger-tab')));
    await _tapText(tester, '账户');
    expect(find.text('61.50'), findsWidgets, reason: '100 - 38.5');
  });

  testWidgets('转账：手续费、同一账户校验；修改与删除流水', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    final a = await _account(
      tester,
      name: '银行卡',
      type: AccountType.debit,
      balance: 100000,
    );
    final b = await _account(tester, name: '支付宝', type: AccountType.alipay);
    await _push(tester, '/ledger/entry/new');
    await _tapText(tester, '转账');
    await tester.enterText(find.byKey(const Key('entry-amount')), '200');
    await tapAndSettle(tester, find.byKey(const Key('entry-account')));
    await _tapText(tester, '银行卡（储蓄卡）');
    await tapAndSettle(tester, find.byKey(const Key('entry-to-account')));
    await _tapText(tester, '银行卡（储蓄卡）');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('转出与转入不能是同一个账户'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('entry-to-account')));
    await _tapText(tester, '支付宝（支付宝）');
    await tester.enterText(find.byKey(const Key('entry-fee')), '1.5');
    await tester.enterText(find.byKey(const Key('entry-amount')), '1.234');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('请输入正确的金额，最多两位小数'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('entry-amount')), '200');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('银行卡 → 支付宝'), findsOneWidget);
    var e = (await _entries(tester)).single;
    expect(
      [e.type, e.amount, e.fee, e.accountId, e.toAccountId],
      [EntryType.transfer, 20000, 150, a, b],
    );

    await tapAndSettle(tester, find.text('银行卡 → 支付宝'));
    expect(find.text('修改流水'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('entry-amount')), '300');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    e = (await _entries(tester)).single;
    expect(e.amount, 30000);

    await tapAndSettle(tester, find.text('银行卡 → 支付宝'));
    await tapAndSettle(tester, find.byKey(const Key('entry-delete')));
    await _tapText(tester, '删除');
    expect(await _entries(tester), isEmpty);
  });

  testWidgets('借贷：借出 → 待收 → 从借贷详情记收款 → 结清 → 删除', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    await _account(tester, name: '现金', balance: 100000);
    await _push(tester, '/ledger/entry/new');
    await _tapText(tester, '借贷');
    await tapAndSettle(tester, find.byKey(const Key('entry-type-lend')));
    await tester.enterText(find.byKey(const Key('entry-amount')), '500');
    await tapAndSettle(tester, find.byKey(const Key('entry-account')));
    await _tapText(tester, '现金（现金）');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('请填写对方'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('entry-counterparty')), '李四');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('借出 · 李四'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('ledger-tab')));
    await _tapText(tester, '账户');
    expect(find.textContaining('待收 500.00'), findsOneWidget);
    final loan = (await tester.runAsync(
      () => _repo(tester).watchLoans().first,
    ))!.single;
    await tapAndSettle(tester, find.byKey(Key('loan-${loan.id}')));
    await tapAndSettle(tester, find.byKey(const Key('loan-back')));
    expect(find.text('记一笔'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('entry-amount')), '500');
    await tapAndSettle(tester, find.byKey(const Key('entry-account')));
    await _tapText(tester, '现金（现金）');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('0.00'), findsWidgets, reason: '已全部收回');

    await tapAndSettle(tester, find.byKey(const Key('loan-settled')));
    expect(
      (await tester.runAsync(() => _repo(tester).watchLoans().first))!
          .single
          .settled,
      isTrue,
    );
    await tapAndSettle(tester, find.byKey(const Key('loan-delete')));
    await _tapText(tester, '删除');
    expect(await _entries(tester), isEmpty);
  });

  testWidgets('统计：分类占比、展开二级分类、收入构成、按年查看', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    final acc = await _account(tester);
    final today = DateTime.now();
    Future<void> add(EntryType type, int amount, String key) => _run(
      tester,
      () => _repo(tester).createEntry(
        EntryDraft(
          type: type,
          amount: amount,
          date: today,
          accountId: acc,
          categoryId: _preset(key),
        ),
      ),
    );
    await add(EntryType.expense, 3000, 'expense.food.lunch');
    await add(EntryType.expense, 1000, 'expense.food.dinner');
    await add(EntryType.expense, 2000, 'expense.transport.taxi');
    await add(EntryType.income, 800000, 'income.salary');

    await tapAndSettle(tester, find.byKey(const Key('ledger-tab')));
    await _tapText(tester, '统计');
    expect(find.byKey(Key('share-${_preset('expense.food')}')), findsOneWidget);
    expect(find.text('66.7% · 2 笔'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(Key('share-${_preset('expense.food')}')),
    );
    expect(find.text('餐饮 的明细'), findsOneWidget);
    expect(
      find.byKey(Key('share-${_preset('expense.food.lunch')}')),
      findsOneWidget,
    );
    await tapAndSettle(tester, find.byKey(const Key('stats-back')));
    await _tapText(tester, '收入构成');
    expect(
      find.byKey(Key('share-${_preset('income.salary')}')),
      findsOneWidget,
    );
    await _tapText(tester, '年');
    expect(find.text('${today.year}年'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('period-prev')));
    expect(find.text('这段时间没有收入'), findsOneWidget);
  });

  testWidgets('账户：负数余额、隐藏与删除', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    await tapAndSettle(tester, find.byKey(const Key('ledger-tab')));
    await _tapText(tester, '账户');
    await tapAndSettle(tester, find.byKey(const Key('account-add')));
    await tester.enterText(find.byKey(const Key('account-name')), '信用卡');
    await tapAndSettle(tester, find.byKey(const Key('account-type')));
    await _tapText(tester, '信用卡');
    await tester.enterText(find.byKey(const Key('account-balance')), '-1200');
    await tapAndSettle(tester, find.byKey(const Key('account-save')));
    expect(find.text('-1,200.00'), findsWidgets);
    final acc = (await tester.runAsync(
      () => _repo(tester).watchAccounts().first,
    ))!.single;
    expect(acc.type, AccountType.credit);

    await tapAndSettle(tester, find.byKey(Key('account-${acc.id}')));
    await tapAndSettle(tester, find.byKey(const Key('account-hide')));
    expect(find.text('已隐藏的账户 1'), findsOneWidget);
    await tapAndSettle(tester, find.text('已隐藏的账户 1'));
    await tapAndSettle(tester, find.byKey(Key('account-${acc.id}')));
    await tapAndSettle(tester, find.byKey(const Key('account-delete')));
    await _tapText(tester, '删除');
    expect(
      (await tester.runAsync(() => _repo(tester).watchAccounts().first))!,
      isEmpty,
    );
  });

  testWidgets('分类管理：新增一级与二级分类、预置分类只能隐藏', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    await _push(tester, '/ledger/categories');
    await tapAndSettle(tester, find.byKey(const Key('category-add')));
    await tapAndSettle(tester, find.byKey(const Key('category-save')));
    expect(find.text('请填写名称'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('category-name')), '宠物');
    await tapAndSettle(tester, find.byKey(const Key('icon-pets')));
    await tapAndSettle(tester, find.byKey(const Key('category-save')));
    final pet = (await tester.runAsync(
      () => _repo(tester).watchCategories().first,
    ))!.firstWhere((c) => c.name == '宠物');
    expect(pet.icon, 'pets');

    await tester.scrollUntilVisible(
      find.byKey(Key('category-add-child-${pet.id}')),
      300,
    );
    await tapAndSettle(tester, find.byKey(Key('category-add-child-${pet.id}')));
    await tester.enterText(find.byKey(const Key('category-name')), '猫粮');
    await tapAndSettle(tester, find.byKey(const Key('category-save')));
    final cats = (await tester.runAsync(
      () => _repo(tester).watchCategories().first,
    ))!;
    expect(cats.firstWhere((c) => c.name == '猫粮').parentId, pet.id);

    await tester.scrollUntilVisible(
      find.byKey(Key('category-row-${pet.id}')),
      -300,
    );
    await tapAndSettle(tester, find.byKey(Key('category-row-${pet.id}')));
    await tapAndSettle(tester, find.byKey(const Key('category-delete')));
    await _tapText(tester, '删除');
    expect(
      (await tester.runAsync(() => _repo(tester).watchCategories().first))!
          .where((c) => c.name == '宠物'),
      isEmpty,
    );

    final food = _preset('expense.food');
    await tester.scrollUntilVisible(
      find.byKey(Key('category-row-$food')),
      -300,
    );
    await tapAndSettle(tester, find.byKey(Key('category-row-$food')));
    expect(find.byKey(const Key('category-delete')), findsNothing);
    await tapAndSettle(tester, find.byKey(const Key('category-hide')));
    expect(find.text('已隐藏'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('category-kind')),
      -500,
    );
    await _tapText(tester, '收入');
    expect(
      find.byKey(Key('category-row-${_preset('income.salary')}')),
      findsOneWidget,
    );
  });

  testWidgets('流水按月查看', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    final acc = await _account(tester);
    final now = DateTime.now();
    await _run(
      tester,
      () => _repo(tester).createEntry(
        EntryDraft(
          type: EntryType.income,
          amount: 100,
          date: DateTime(now.year, now.month - 1, 15),
          accountId: acc,
          categoryId: _preset('income.bonus'),
        ),
      ),
    );
    expect(find.text('这个月还没有记账'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('period-prev')));
    expect(find.text('奖金'), findsOneWidget);
    expect(find.text('+1.00'), findsWidgets);
    await tapAndSettle(tester, find.byKey(const Key('period-next')));
    expect(find.text('这个月还没有记账'), findsOneWidget);
  });

  testWidgets('窄屏 + 大字号：三个页签与借贷详情不溢出', (tester) async {
    await pumpApp(tester, width: 360, height: 760, textScale: 1.5);
    await _go(tester, '/ledger');
    final acc = await _account(
      tester,
      name: '一个名字很长的招商银行储蓄卡账户',
      balance: 123456789,
    );
    final loan = await _run(
      tester,
      () => _repo(tester).createLoan(
        direction: LoanDirection.borrow,
        counterparty: '名字很长的一位朋友',
        amount: 99999999,
        accountId: acc,
        date: DateTime.now(),
        dueDate: DateTime(2020),
      ),
    );
    await _run(
      tester,
      () => _repo(tester).createEntry(
        EntryDraft(
          type: EntryType.expense,
          amount: 88888888,
          date: DateTime.now(),
          accountId: acc,
          categoryId: _preset('expense.housing.rent'),
          note: '很长的备注' * 10,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final tab in ['统计', '账户']) {
      await tapAndSettle(tester, find.byKey(const Key('ledger-tab')));
      await _tapText(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }
    expect(find.textContaining('已逾期'), findsOneWidget);
    await _push(tester, '/ledger/loans/$loan');
    expect(tester.takeException(), isNull);
    expect(find.text('记一笔还款'), findsOneWidget);
  });

  testWidgets('借贷详情：修改对方、到期日；不存在时提示', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    final acc = await _account(tester);
    final loan = await _run(
      tester,
      () => _repo(tester).createLoan(
        direction: LoanDirection.lend,
        counterparty: '张三',
        amount: 1000,
        accountId: acc,
        date: DateTime(2026, 10, 1),
      ),
    );
    await _push(tester, '/ledger/loans/$loan');
    expect(find.text('没有到期日'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('loan-edit-counterparty')));
    await tester.enterText(find.byKey(const Key('loan-counterparty')), '张小三');
    await tapAndSettle(tester, find.byKey(const Key('loan-counterparty-save')));
    expect(find.text('借出 · 张小三'), findsWidgets);

    await tapAndSettle(tester, find.byKey(const Key('loan-due')));
    await tapAndSettle(tester, find.text('OK'));
    expect(find.textContaining('到期'), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('清除到期日'));
    expect(find.text('没有到期日'), findsOneWidget);

    await _go(tester, '/ledger');
    await _push(tester, '/ledger/loans/0192a000-0000-7000-8000-00000000ffff');
    expect(find.text('借贷不存在'), findsOneWidget);
  });

  testWidgets('记一笔：切换类型后隐藏的手续费不挡住保存；收款与还款切换时借贷重新选择', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    final acc = await _account(tester, balance: 100000);
    await _run(
      tester,
      () => _repo(tester).createLoan(
        direction: LoanDirection.lend,
        counterparty: '李四',
        amount: 5000,
        accountId: acc,
        date: DateTime.now(),
      ),
    );
    await _run(
      tester,
      () => _repo(tester).createLoan(
        direction: LoanDirection.borrow,
        counterparty: '王五',
        amount: 3000,
        accountId: acc,
        date: DateTime.now(),
      ),
    );
    await _push(tester, '/ledger/entry/new');
    await _tapText(tester, '转账');
    await tester.enterText(find.byKey(const Key('entry-fee')), '1..');
    await _tapText(tester, '支出');
    await tester.enterText(find.byKey(const Key('entry-amount')), '10');
    await tapAndSettle(tester, find.byKey(const Key('entry-account')));
    await _tapText(tester, '现金（现金）');
    await tapAndSettle(
      tester,
      find.byKey(Key('category-${_preset('expense.fun')}')),
    );
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('手续费格式不正确'), findsNothing);
    expect(
      (await _entries(tester)).where((e) => e.type == EntryType.expense),
      hasLength(1),
    );

    await _push(tester, '/ledger/entry/new');
    await _tapText(tester, '借贷');
    await tapAndSettle(tester, find.byKey(const Key('entry-type-collect')));
    await tapAndSettle(tester, find.byKey(const Key('entry-loan')));
    await _tapText(tester, '李四 · 待收 50.00');
    await tapAndSettle(tester, find.byKey(const Key('entry-type-repay')));
    expect(tester.takeException(), isNull);
    await tapAndSettle(tester, find.byKey(const Key('entry-loan')));
    await _tapText(tester, '王五 · 待还 30.00');
    await tester.enterText(find.byKey(const Key('entry-amount')), '40');
    await tapAndSettle(tester, find.byKey(const Key('entry-account')));
    await _tapText(tester, '现金（现金）');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(find.text('还款不能超过待还 30.00 元'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('entry-amount')), '30');
    await tapAndSettle(tester, find.byKey(const Key('entry-save')));
    expect(
      (await _entries(tester)).where((e) => e.type == EntryType.repay),
      hasLength(1),
    );
  });

  testWidgets('修改已有流水：不能改成借贷；流水不存在时提示', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    final acc = await _account(tester);
    final id = await _run(
      tester,
      () => _repo(tester).createEntry(
        EntryDraft(
          type: EntryType.expense,
          amount: 100,
          date: DateTime.now(),
          accountId: acc,
          categoryId: _preset('expense.fun'),
        ),
      ),
    );
    await _push(tester, '/ledger/entry/$id');
    expect(find.text('借贷'), findsNothing);
    expect(find.text('转账'), findsOneWidget);
    await tester.pageBack();
    await settleApp(tester);
    await _push(tester, '/ledger/entry/0192a000-0000-7000-8000-00000000eeee');
    expect(find.text('这条流水不存在，可能已在其他设备上删除'), findsOneWidget);
    expect(find.byKey(const Key('entry-save')), findsNothing);
  });

  testWidgets('到期当天的借贷不算逾期', (tester) async {
    await pumpApp(tester);
    await _go(tester, '/ledger');
    final acc = await _account(tester);
    final today = DateTime.now();
    await _run(
      tester,
      () => _repo(tester).createLoan(
        direction: LoanDirection.lend,
        counterparty: '赵六',
        amount: 100,
        accountId: acc,
        date: today,
        dueDate: DateTime(today.year, today.month, today.day),
      ),
    );
    await tapAndSettle(tester, find.byKey(const Key('ledger-tab')));
    await _tapText(tester, '账户');
    expect(find.textContaining('到期'), findsOneWidget);
    expect(find.textContaining('已逾期'), findsNothing);
  });
}
