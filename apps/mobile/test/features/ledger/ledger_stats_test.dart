import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/ledger/ledger_models.dart';
import 'package:jikelog/features/ledger/ledger_stats.dart';
import 'package:jikelog/features/ledger/money.dart';

void main() {
  group('金额', () {
    test('输入解析：最多两位小数，拒绝负数与非法格式', () {
      expect(parseYuan('12'), 1200);
      expect(parseYuan('12.5'), 1250);
      expect(parseYuan('0.01'), 1);
      expect(parseYuan(' 1,234.56 '), 123456);
      expect(parseYuan('12.'), 1200);
      for (final bad in [
        '',
        '-1',
        '1.234',
        'abc',
        '1e3',
        '.5',
        '99999999999999',
      ]) {
        expect(parseYuan(bad), isNull, reason: bad);
      }
    });

    test('显示：千分位与两位小数', () {
      expect(formatYuan(0), '0.00');
      expect(formatYuan(5), '0.05');
      expect(formatYuan(123456), '1,234.56');
      expect(formatYuan(100000000), '1,000,000.00');
      expect(formatYuan(-5000), '-50.00');
      expect(formatYuan(1200, sign: true), '+12.00');
      expect(editableYuan(1200), '12');
      expect(editableYuan(1250), '12.5');
      expect(editableYuan(1205), '12.05');
      expect(parseCents('3850'), 3850);
      expect(parseCents(3850), isNull);
      for (final bad in ['+5', '007', '-0', '1000000000000000', '1.5', '']) {
        expect(parseCents(bad), isNull, reason: bad);
      }
      expect(parseCents('-999999999999999'), -999999999999999);
      expect(encodeCents(-12), '-12');
    });
  });

  const cash = Account(
    id: 'cash',
    name: '现金',
    type: AccountType.cash,
    initialBalance: 10000,
  );
  const card = Account(
    id: 'card',
    name: '信用卡',
    type: AccountType.credit,
    initialBalance: -50000,
  );
  const food = LedgerCategory(
    id: 'food',
    name: '餐饮',
    kind: CategoryKind.expense,
  );
  const lunch = LedgerCategory(
    id: 'lunch',
    name: '午餐',
    kind: CategoryKind.expense,
    parentId: 'food',
  );
  const taxi = LedgerCategory(
    id: 'taxi',
    name: '打车',
    kind: CategoryKind.expense,
  );
  const fee = LedgerCategory(
    id: 'fee',
    name: '手续费',
    kind: CategoryKind.expense,
  );
  const salary = LedgerCategory(
    id: 'salary',
    name: '工资',
    kind: CategoryKind.income,
  );
  final cats = {
    for (final c in [food, lunch, taxi, fee, salary]) c.id: c,
  };
  const lendLoan = Loan(
    id: 'l1',
    direction: LoanDirection.lend,
    counterparty: '李四',
  );
  const borrowLoan = Loan(
    id: 'l2',
    direction: LoanDirection.borrow,
    counterparty: '王五',
  );

  Entry e(
    String id,
    EntryType type,
    int amount, {
    String account = 'cash',
    String? to,
    String? category,
    String? loan,
    int fee = 0,
    DateTime? date,
  }) => Entry(
    id: id,
    type: type,
    amount: amount,
    fee: fee,
    date: date ?? DateTime(2026, 10, 11),
    accountId: account,
    toAccountId: to,
    categoryId: category,
    loanId: loan,
  );

  final entries = [
    e(
      '1',
      EntryType.income,
      800000,
      category: 'salary',
      date: DateTime(2026, 10, 1),
    ),
    e('2', EntryType.expense, 3000, category: 'lunch'),
    e('3', EntryType.expense, 2000, category: 'food'),
    e('4', EntryType.expense, 5000, category: 'taxi', account: 'card'),
    e('5', EntryType.transfer, 20000, to: 'card', fee: 100),
    e('6', EntryType.lend, 50000, loan: 'l1'),
    e('7', EntryType.collect, 10000, loan: 'l1'),
    e('8', EntryType.borrow, 30000, loan: 'l2'),
    e('9', EntryType.repay, 30000, loan: 'l2'),
    e('x', EntryType.expense, 99999), // 缺分类：不计入
    e(
      'sep',
      EntryType.expense,
      7000,
      category: 'taxi',
      date: DateTime(2026, 9, 30),
    ),
  ];

  test('账户余额：各类流水的影响，忽略不完整的流水', () {
    final b = accountBalances([cash, card], entries);
    // 现金：10000 + 800000 - 3000 - 2000 - 20100 - 50000 + 10000 + 30000 - 30000 - 7000
    expect(b['cash'], 737900);
    // 信用卡：-50000 - 5000 + 20000
    expect(b['card'], -35000);
    expect(effectOn(entries[4], 'cash'), -20100);
    expect(effectOn(entries[4], 'card'), 20000);
    expect(effectOn(entries[9], 'cash'), 0);
  });

  test('借贷待收待还与净资产', () {
    final loans = loanBalances(entries);
    expect(loans['l1']!.outstanding, 40000);
    expect(loans['l2']!.outstanding, 0);
    final w = netWorth([cash, card], [lendLoan, borrowLoan], entries);
    expect(w.accounts, 737900 - 35000);
    expect(w.receivable, 40000);
    expect(w.payable, 0);
    expect(w.total, 737900 - 35000 + 40000);
    // 已结清的借贷不再计入待收（剩余视为减免）
    const settled = Loan(
      id: 'l1',
      direction: LoanDirection.lend,
      counterparty: '李四',
      settled: true,
    );
    expect(
      netWorth([cash, card], [settled, borrowLoan], entries).receivable,
      0,
    );
  });

  test('月度收支：支出含转账手续费', () {
    final t = periodTotals(entries, Period.month(2026, 10));
    expect(t.income, 800000);
    expect(t.expense, 3000 + 2000 + 5000 + 100);
    expect(t.balance, 800000 - 10100);
    expect(periodTotals(entries, Period.month(2026, 9)).expense, 7000);
    expect(periodTotals(entries, Period.year(2026)).expense, 17100);
  });

  test('分类占比：按一级汇总，可展开二级，手续费单列', () {
    final shares = categoryShares(
      entries,
      cats,
      CategoryKind.expense,
      Period.month(2026, 10),
      feeCategoryId: 'fee',
    );
    expect(shares.map((s) => s.categoryId), ['food', 'taxi', 'fee']);
    expect(shares.first.amount, 5000);
    expect(shares.first.count, 2);
    expect(shares.first.ratio, closeTo(5000 / 10100, 1e-9));

    final inFood = categoryShares(
      entries,
      cats,
      CategoryKind.expense,
      Period.month(2026, 10),
      parentId: 'food',
    );
    expect(
      {for (final s in inFood) s.categoryId: s.amount},
      {'lunch': 3000, 'food': 2000},
    );

    final income = categoryShares(
      entries,
      cats,
      CategoryKind.income,
      Period.month(2026, 10),
    );
    expect(income.single.categoryId, 'salary');
    expect(income.single.ratio, 1);
    final unknown = categoryShares(
      [e('u', EntryType.expense, 100, category: 'gone')],
      cats,
      CategoryKind.expense,
      Period.month(2026, 10),
    );
    expect(unknown.single.categoryId, isNull);
  });

  test('趋势：按日或按月，没有流水的也列出', () {
    final days = trend(entries, Period.month(2026, 10), TrendUnit.day);
    expect(days, hasLength(31));
    expect(days.first.totals.income, 800000);
    expect(days[10].totals.expense, 10100);
    final months = trend(entries, Period.year(2026), TrendUnit.month);
    expect(months, hasLength(12));
    expect(months[8].totals.expense, 7000);
    expect(months[9].totals.expense, 10100);
  });

  test('流水的有效性', () {
    expect(e('t', EntryType.transfer, 1, to: 'cash').valid, isFalse);
    expect(e('t', EntryType.transfer, 1, to: 'card').valid, isTrue);
    expect(e('l', EntryType.lend, 1).valid, isFalse);
    expect(EntryType.parse('nope'), isNull);
    expect(EntryType.collect.isLoan, isTrue);
    expect(EntryType.income.hasCategory, isTrue);
    expect(AccountType.parse('nope'), AccountType.other);
    expect(Period.month(2026, 12).to, DateTime(2027));
  });
}
