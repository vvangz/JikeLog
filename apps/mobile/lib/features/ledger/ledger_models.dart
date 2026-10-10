import 'package:flutter/foundation.dart';

import '../../core/sync/record_store.dart';
import 'money.dart';

/// 账户类型。
enum AccountType {
  cash('现金'),
  debit('储蓄卡'),
  credit('信用卡'),
  alipay('支付宝'),
  wechat('微信'),
  other('其他');

  const AccountType(this.label);
  final String label;

  static AccountType parse(Object? v) =>
      values.firstWhere((t) => t.name == v, orElse: () => other);
}

/// 流水类型（ADR-009 第 3 节）。
enum EntryType {
  expense('支出'),
  income('收入'),
  transfer('转账'),
  lend('借出'),
  borrow('借入'),
  collect('收款'),
  repay('还款');

  const EntryType(this.label);
  final String label;

  static EntryType? parse(Object? v) {
    for (final t in values) {
      if (t.name == v) return t;
    }
    return null;
  }

  /// 收入或支出：必须有分类。
  bool get hasCategory => this == expense || this == income;

  /// 借贷类：关联一笔借贷。
  bool get isLoan =>
      this == lend || this == borrow || this == collect || this == repay;
}

enum CategoryKind {
  expense('支出'),
  income('收入');

  const CategoryKind(this.label);
  final String label;

  static CategoryKind parse(Object? v) => v == 'income' ? income : expense;
}

enum LoanDirection {
  lend('借出'),
  borrow('借入');

  const LoanDirection(this.label);
  final String label;

  static LoanDirection parse(Object? v) => v == 'borrow' ? borrow : lend;
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

@immutable
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.initialBalance = 0,
    this.archived = false,
    this.sortOrder = 0,
  });

  factory Account.fromRecord(LocalRecord r) => Account(
    id: r.id,
    name: r.fields['name'] as String? ?? '',
    type: AccountType.parse(r.fields['type']),
    initialBalance: parseCents(r.fields['initialBalance']) ?? 0,
    archived: r.fields['archived'] == 1,
    sortOrder: r.fields['sortOrder'] as int? ?? 0,
  );

  final String id;
  final String name;
  final AccountType type;

  /// 初始余额（分），信用卡欠款为负。
  final int initialBalance;
  final bool archived;
  final int sortOrder;

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.initialBalance == initialBalance &&
      other.archived == archived &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode =>
      Object.hash(id, name, type, initialBalance, archived, sortOrder);
}

@immutable
class LedgerCategory {
  const LedgerCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.parentId,
    this.icon = '',
    this.archived = false,
    this.sortOrder = 0,
  });

  factory LedgerCategory.fromRecord(LocalRecord r) => LedgerCategory(
    id: r.id,
    name: r.fields['name'] as String? ?? '',
    kind: CategoryKind.parse(r.fields['kind']),
    parentId: _str(r.fields['parentId']),
    icon: r.fields['icon'] as String? ?? '',
    archived: r.fields['archived'] == 1,
    sortOrder: r.fields['sortOrder'] as int? ?? 0,
  );

  final String id;
  final String name;
  final CategoryKind kind;

  /// 上级分类；为空表示一级分类。
  final String? parentId;
  final String icon;
  final bool archived;
  final int sortOrder;

  @override
  bool operator ==(Object other) =>
      other is LedgerCategory &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.parentId == parentId &&
      other.icon == icon &&
      other.archived == archived &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode =>
      Object.hash(id, name, kind, parentId, icon, archived, sortOrder);
}

@immutable
class Loan {
  const Loan({
    required this.id,
    required this.direction,
    required this.counterparty,
    this.dueDate,
    this.note = '',
    this.settled = false,
  });

  factory Loan.fromRecord(LocalRecord r) => Loan(
    id: r.id,
    direction: LoanDirection.parse(r.fields['direction']),
    counterparty: r.fields['counterparty'] as String? ?? '',
    dueDate: DateTime.tryParse(r.fields['dueDate'] as String? ?? ''),
    note: r.fields['note'] as String? ?? '',
    settled: r.fields['settled'] == 1,
  );

  final String id;
  final LoanDirection direction;
  final String counterparty;
  final DateTime? dueDate;
  final String note;
  final bool settled;

  @override
  bool operator ==(Object other) =>
      other is Loan &&
      other.id == id &&
      other.direction == direction &&
      other.counterparty == counterparty &&
      other.dueDate == dueDate &&
      other.note == note &&
      other.settled == settled;

  @override
  int get hashCode =>
      Object.hash(id, direction, counterparty, dueDate, note, settled);
}

/// 一条流水。字段不完整（例如其他设备写入了无法识别的类型）时 [valid] 为 false，不计入统计。
@immutable
class Entry {
  const Entry({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.accountId,
    this.fee = 0,
    this.toAccountId,
    this.categoryId,
    this.loanId,
    this.note = '',
    this.pending = false,
    this.hasConflict = false,
    this.syncError,
  });

  static Entry? fromRecord(LocalRecord r) {
    final type = EntryType.parse(r.fields['type']);
    final amount = parseCents(r.fields['amount']);
    final date = DateTime.tryParse(r.fields['date'] as String? ?? '');
    final account = _str(r.fields['accountId']);
    if (type == null || amount == null || date == null || account == null) {
      return null;
    }
    return Entry(
      id: r.id,
      type: type,
      amount: amount,
      fee: parseCents(r.fields['fee']) ?? 0,
      date: date,
      accountId: account,
      toAccountId: _str(r.fields['toAccountId']),
      categoryId: _str(r.fields['categoryId']),
      loanId: _str(r.fields['loanId']),
      note: r.fields['note'] as String? ?? '',
      pending: r.dirty,
      hasConflict: r.hasConflict,
      syncError: r.syncError,
    );
  }

  final String id;
  final EntryType type;

  /// 金额（分），大于 0。
  final int amount;

  /// 转账手续费（分）。
  final int fee;
  final DateTime date;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String? loanId;
  final String note;
  final bool pending;
  final bool hasConflict;
  final String? syncError;

  /// 字段之间的约束是否满足（ADR-009）。
  bool get valid => switch (type) {
    EntryType.expense || EntryType.income => categoryId != null,
    EntryType.transfer => toAccountId != null && toAccountId != accountId,
    _ => loanId != null,
  };

  @override
  bool operator ==(Object other) =>
      other is Entry &&
      other.id == id &&
      other.type == type &&
      other.amount == amount &&
      other.fee == fee &&
      other.date == date &&
      other.accountId == accountId &&
      other.toAccountId == toAccountId &&
      other.categoryId == categoryId &&
      other.loanId == loanId &&
      other.note == note &&
      other.pending == pending &&
      other.hasConflict == hasConflict &&
      other.syncError == syncError;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amount,
    fee,
    date,
    accountId,
    toAccountId,
    categoryId,
    loanId,
    note,
    pending,
    hasConflict,
    syncError,
  );
}
