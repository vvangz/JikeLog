import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/sync_badges.dart';
import 'ledger_models.dart';
import 'ledger_presets.dart';
import 'money.dart';

/// 金额文字：收入为成功色，支出为默认色；[signed] 为 true 时带正负号。
class AmountText extends StatelessWidget {
  const AmountText(
    this.cents, {
    super.key,
    this.signed = false,
    this.style,
    this.colored = true,
  });

  final int cents;
  final bool signed;
  final bool colored;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final color = !colored || cents == 0
        ? null
        : cents > 0
        ? c.success
        : c.error;
    // 金额很大或字号很大时在可用宽度内缩小显示，不溢出
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        formatYuan(cents, sign: signed),
        maxLines: 1,
        style: (style ?? const TextStyle()).copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 月份（或年份）切换：‹ 2026年10月 ›。
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.anchor,
    required this.yearly,
    required this.onChanged,
  });

  /// 当前月（或年）中的任意一天。
  final DateTime anchor;
  final bool yearly;
  final ValueChanged<DateTime> onChanged;

  DateTime _shift(int n) => yearly
      ? DateTime(anchor.year + n)
      : DateTime(anchor.year, anchor.month + n);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: const Key('period-prev'),
        tooltip: yearly ? '上一年' : '上个月',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(_shift(-1)),
      ),
      Text(
        yearly ? '${anchor.year}年' : '${anchor.year}年${anchor.month}月',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      IconButton(
        key: const Key('period-next'),
        tooltip: yearly ? '下一年' : '下个月',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => onChanged(_shift(1)),
      ),
    ],
  );
}

/// 分类或流水类型的圆形图标。
class LedgerAvatar extends StatelessWidget {
  const LedgerAvatar({super.key, required this.icon, this.highlight = false});

  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return CircleAvatar(
      radius: 18,
      backgroundColor: highlight ? c.primary : c.primaryContainer,
      child: Icon(
        icon,
        size: 20,
        color: highlight ? c.onPrimary : c.onPrimaryContainer,
      ),
    );
  }
}

/// 流水类型（转账、借贷）的图标。
IconData entryTypeIcon(EntryType t) => switch (t) {
  EntryType.transfer => Icons.swap_horiz,
  EntryType.lend => Icons.call_made,
  EntryType.borrow => Icons.call_received,
  EntryType.collect => Icons.south_west,
  EntryType.repay => Icons.north_east,
  _ => Icons.label_outline,
};

/// 列表中显示的流水标题：收支为分类名，转账为"A → B"，借贷为"借出 · 李四"。
String entryTitle(
  Entry e, {
  required Map<String, LedgerCategory> categories,
  required Map<String, Account> accounts,
  required Map<String, Loan> loans,
}) {
  switch (e.type) {
    case EntryType.expense || EntryType.income:
      final c = categories[e.categoryId];
      if (c == null) return '未分类';
      final parent = categories[c.parentId];
      return parent == null ? c.name : '${parent.name} · ${c.name}';
    case EntryType.transfer:
      final from = accounts[e.accountId]?.name ?? '?';
      final to = accounts[e.toAccountId]?.name ?? '?';
      return '$from → $to';
    default:
      final who = loans[e.loanId]?.counterparty;
      return who == null ? e.type.label : '${e.type.label} · $who';
  }
}

/// 流水对账户余额的方向：收入、借入、收款为正，其余为负（转账显示为负，含手续费）。
int signedAmount(Entry e) => switch (e.type) {
  EntryType.income || EntryType.borrow || EntryType.collect => e.amount,
  EntryType.transfer => -(e.amount + e.fee),
  _ => -e.amount,
};

/// 列表中的一条流水。
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.categories,
    required this.accounts,
    required this.loans,
  });

  final Entry entry;
  final Map<String, LedgerCategory> categories;
  final Map<String, Account> accounts;
  final Map<String, Loan> loans;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final e = entry;
    final cat = categories[e.categoryId];
    final icon = e.type.hasCategory
        ? categoryIcon(cat?.icon ?? '')
        : entryTypeIcon(e.type);
    final account = accounts[e.accountId]?.name ?? '';
    final subtitle = [
      if (e.note.trim().isNotEmpty) e.note.trim().split('\n').first,
      if (e.type != EntryType.transfer) account,
      if (e.type == EntryType.transfer && e.fee > 0) '手续费 ${formatYuan(e.fee)}',
    ].join(' · ');
    final amount = signedAmount(e);
    return ListTile(
      key: Key('entry-${e.id}'),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: JkTokens.spacingSm,
      ),
      leading: LedgerAvatar(icon: icon),
      title: Text(
        entryTitle(e, categories: categories, accounts: accounts, loans: loans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textSecondary),
            ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SyncBadges(
              pending: e.pending,
              hasConflict: e.hasConflict,
              syncError: e.syncError,
            ),
            const SizedBox(width: JkTokens.spacingXs),
            Flexible(
              child: AmountText(
                amount,
                signed: true,
                colored: e.type == EntryType.income,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
      onTap: () => context.push('/ledger/entry/${e.id}'),
    );
  }
}
