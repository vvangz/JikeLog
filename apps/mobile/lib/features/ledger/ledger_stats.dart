/// 记账统计：全部由本地数据实时计算，金额单位为分（ADR-009 第 6 节）。
library;

import 'package:flutter/foundation.dart';

import 'ledger_models.dart';

/// 一个时间范围 [from, to)。
@immutable
class Period {
  const Period(this.from, this.to);

  /// 某个月。
  factory Period.month(int year, int month) =>
      Period(DateTime(year, month), DateTime(year, month + 1));

  /// 某一年。
  factory Period.year(int year) => Period(DateTime(year), DateTime(year + 1));

  final DateTime from;
  final DateTime to;

  bool contains(DateTime d) => !d.isBefore(from) && d.isBefore(to);

  @override
  bool operator ==(Object other) =>
      other is Period && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// 各账户余额：初始余额加上流水变动。
Map<String, int> accountBalances(List<Account> accounts, List<Entry> entries) {
  final out = {for (final a in accounts) a.id: a.initialBalance};
  void add(String? id, int delta) {
    if (id != null && out.containsKey(id)) out[id] = out[id]! + delta;
  }

  for (final e in entries) {
    if (!e.valid) continue;
    switch (e.type) {
      case EntryType.income || EntryType.borrow || EntryType.collect:
        add(e.accountId, e.amount);
      case EntryType.expense || EntryType.lend || EntryType.repay:
        add(e.accountId, -e.amount);
      case EntryType.transfer:
        add(e.accountId, -e.amount - e.fee);
        add(e.toAccountId, e.amount);
    }
  }
  return out;
}

/// 一笔借贷的金额：借出（借入）合计、已收（已还）合计、待收（待还）。
@immutable
class LoanBalance {
  const LoanBalance({required this.principal, required this.returned});

  final int principal;
  final int returned;

  int get outstanding => principal - returned;
}

Map<String, LoanBalance> loanBalances(List<Entry> entries) {
  final principal = <String, int>{};
  final returned = <String, int>{};
  for (final e in entries) {
    final id = e.loanId;
    if (!e.valid || id == null) continue;
    switch (e.type) {
      case EntryType.lend || EntryType.borrow:
        principal[id] = (principal[id] ?? 0) + e.amount;
      case EntryType.collect || EntryType.repay:
        returned[id] = (returned[id] ?? 0) + e.amount;
      default:
        break;
    }
  }
  return {
    for (final id in {...principal.keys, ...returned.keys})
      id: LoanBalance(
        principal: principal[id] ?? 0,
        returned: returned[id] ?? 0,
      ),
  };
}

/// 资产概况。
@immutable
class NetWorth {
  const NetWorth({
    required this.accounts,
    required this.receivable,
    required this.payable,
  });

  /// 各账户余额之和。
  final int accounts;

  /// 待收（借出未收回）。
  final int receivable;

  /// 待还（借入未还清）。
  final int payable;

  int get total => accounts + receivable - payable;
}

NetWorth netWorth(
  List<Account> accounts,
  List<Loan> loans,
  List<Entry> entries,
) {
  final balances = accountBalances(accounts, entries);
  final byLoan = loanBalances(entries);
  var receivable = 0;
  var payable = 0;
  for (final l in loans) {
    // 已结清的借贷不再计入（剩余部分视为减免或坏账）
    final out = l.settled ? 0 : byLoan[l.id]?.outstanding ?? 0;
    if (out <= 0) continue;
    if (l.direction == LoanDirection.lend) {
      receivable += out;
    } else {
      payable += out;
    }
  }
  return NetWorth(
    accounts: balances.values.fold(0, (a, b) => a + b),
    receivable: receivable,
    payable: payable,
  );
}

/// 一段时间的收入与支出（支出含转账手续费）。
@immutable
class Totals {
  const Totals({this.income = 0, this.expense = 0});

  final int income;
  final int expense;

  int get balance => income - expense;

  Totals operator +(Totals o) =>
      Totals(income: income + o.income, expense: expense + o.expense);

  @override
  bool operator ==(Object other) =>
      other is Totals && other.income == income && other.expense == expense;

  @override
  int get hashCode => Object.hash(income, expense);
}

Totals totalsOf(Entry e) {
  if (!e.valid) return const Totals();
  return switch (e.type) {
    EntryType.income => Totals(income: e.amount),
    EntryType.expense => Totals(expense: e.amount),
    EntryType.transfer => Totals(expense: e.fee),
    _ => const Totals(),
  };
}

Totals periodTotals(List<Entry> entries, Period p) => entries
    .where((e) => p.contains(e.date))
    .fold(const Totals(), (t, e) => t + totalsOf(e));

/// 分类占比中的一项。
@immutable
class CategoryShare {
  const CategoryShare({
    required this.categoryId,
    required this.amount,
    required this.ratio,
    required this.count,
  });

  /// 分类 ID；找不到分类时为 null（"未分类"）。
  final String? categoryId;
  final int amount;

  /// 占合计的比例（0–1）。
  final double ratio;
  final int count;
}

/// 分类占比：[parentId] 为空时按一级分类汇总（二级计入其上级），否则只看该分类下的二级分类
/// （直接记在一级分类上的计为该一级分类自身）。按金额从大到小排列。
/// 转账手续费计入 [feeCategoryId]。
List<CategoryShare> categoryShares(
  List<Entry> entries,
  Map<String, LedgerCategory> categories,
  CategoryKind kind,
  Period p, {
  String? parentId,
  String? feeCategoryId,
}) {
  final sums = <String?, int>{};
  final counts = <String?, int>{};
  String? bucket(String? categoryId) {
    final c = categoryId == null ? null : categories[categoryId];
    // 找不到分类时归入"未分类"（只在一级汇总中出现）
    if (c == null) return parentId == null ? null : '';
    if (parentId == null) return c.parentId ?? c.id;
    if (c.id == parentId || c.parentId == parentId) return c.id;
    return '';
  }

  for (final e in entries) {
    if (!e.valid || !p.contains(e.date)) continue;
    final (String? cat, int amount) = switch (e.type) {
      EntryType.expense when kind == CategoryKind.expense => (
        e.categoryId,
        e.amount,
      ),
      EntryType.income when kind == CategoryKind.income => (
        e.categoryId,
        e.amount,
      ),
      EntryType.transfer when kind == CategoryKind.expense && e.fee > 0 => (
        feeCategoryId,
        e.fee,
      ),
      _ => (null, 0),
    };
    if (amount == 0) continue;
    final b = bucket(cat);
    if (b == '') continue; // 不属于要看的一级分类
    sums[b] = (sums[b] ?? 0) + amount;
    counts[b] = (counts[b] ?? 0) + 1;
  }
  final total = sums.values.fold(0, (a, b) => a + b);
  final out = [
    for (final MapEntry(key: id, value: amount) in sums.entries)
      CategoryShare(
        categoryId: id,
        amount: amount,
        ratio: total == 0 ? 0 : amount / total,
        count: counts[id]!,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return out;
}

/// 趋势的粒度。
enum TrendUnit { day, month }

/// 趋势中的一点：某天或某月的收支。
@immutable
class TrendPoint {
  const TrendPoint(this.start, this.totals);

  final DateTime start;
  final Totals totals;
}

/// 收支趋势：[p] 内每天（或每月）一个点，没有流水的也列出。
List<TrendPoint> trend(List<Entry> entries, Period p, TrendUnit unit) {
  DateTime keyOf(DateTime d) => unit == TrendUnit.day
      ? DateTime(d.year, d.month, d.day)
      : DateTime(d.year, d.month);
  final sums = <DateTime, Totals>{};
  for (final e in entries) {
    if (!p.contains(e.date)) continue;
    final k = keyOf(e.date);
    sums[k] = (sums[k] ?? const Totals()) + totalsOf(e);
  }
  final out = <TrendPoint>[];
  var cur = keyOf(p.from);
  while (cur.isBefore(p.to)) {
    out.add(TrendPoint(cur, sums[cur] ?? const Totals()));
    cur = unit == TrendUnit.day
        ? DateTime(cur.year, cur.month, cur.day + 1)
        : DateTime(cur.year, cur.month + 1);
  }
  return out;
}

/// 流水对某个账户余额的影响（账户详情中显示）。
int effectOn(Entry e, String accountId) {
  if (!e.valid) return 0;
  var delta = 0;
  if (e.accountId == accountId) {
    delta += switch (e.type) {
      EntryType.income || EntryType.borrow || EntryType.collect => e.amount,
      EntryType.expense || EntryType.lend || EntryType.repay => -e.amount,
      EntryType.transfer => -e.amount - e.fee,
    };
  }
  if (e.type == EntryType.transfer && e.toAccountId == accountId) {
    delta += e.amount;
  }
  return delta;
}
