import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_icon.dart';
import '../../shared/ui/jk_states.dart';
import '../memos/memo_widgets.dart' show weekdayNames;
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'ledger_stats.dart';
import 'ledger_widgets.dart';
import 'money.dart';

/// 流水列表当前查看的月份。
final ledgerMonthProvider = NotifierProvider<LedgerMonthController, DateTime>(
  LedgerMonthController.new,
);

class LedgerMonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void set(DateTime d) => state = DateTime(d.year, d.month);
}

/// 流水：按月查看，按日分组，顶部是本月收支合计。
class EntriesTab extends ConsumerWidget {
  const EntriesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(ledgerMonthProvider);
    final entries = ref.watch(entriesProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final loans = ref.watch(loansProvider).value ?? const [];
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).sync(),
      child: entries.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(JkTokens.spacingLg),
          child: JkSkeleton(lines: 6),
        ),
        error: (e, _) => JkErrorState(
          message: '读取流水失败',
          onRetry: () => ref.invalidate(entriesProvider),
        ),
        data: (all) {
          final period = Period.month(month.year, month.month);
          final inMonth = [
            for (final e in all)
              if (period.contains(e.date)) e,
          ];
          return _EntryList(
            month: month,
            entries: inMonth,
            totals: periodTotals(inMonth, period),
            categories: {for (final c in categories) c.id: c},
            accounts: {for (final a in accounts) a.id: a},
            loans: {for (final l in loans) l.id: l},
          );
        },
      ),
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({
    required this.month,
    required this.entries,
    required this.totals,
    required this.categories,
    required this.accounts,
    required this.loans,
  });

  final DateTime month;
  final List<Entry> entries;
  final Totals totals;
  final Map<String, LedgerCategory> categories;
  final Map<String, Account> accounts;
  final Map<String, Loan> loans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[
      Center(
        child: PeriodSwitcher(
          anchor: month,
          yearly: false,
          onChanged: ref.read(ledgerMonthProvider.notifier).set,
        ),
      ),
      _Summary(totals: totals),
    ];
    if (entries.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: JkTokens.spacingXl),
          child: JkEmptyState(
            icon: const JkIcon(JkIcons.ledger, size: 32),
            title: '这个月还没有记账',
            message: '记录收入、支出、转账与借贷，统计分类占比和账户余额。',
            actionLabel: '记一笔',
            onAction: () => context.push('/ledger/entry/new'),
          ),
        ),
      );
    }
    final byDay = <DateTime, Totals>{};
    for (final e in entries) {
      byDay[e.date] = (byDay[e.date] ?? const Totals()) + totalsOf(e);
    }
    DateTime? day;
    for (final e in entries) {
      if (e.date != day) {
        day = e.date;
        rows.add(_DayHeader(day: e.date, totals: byDay[e.date]!));
      }
      rows.add(
        EntryTile(
          entry: e,
          categories: categories,
          accounts: accounts,
          loans: loans,
        ),
      );
    }
    return ListView.builder(
      key: const Key('ledger-entries'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        0,
        JkTokens.spacingLg,
        96,
      ),
      itemCount: rows.length,
      itemBuilder: (_, i) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: rows[i],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.totals});

  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.jkColors;
    Widget cell(String label, int cents, {bool signed = false}) => Expanded(
      child: Column(
        children: [
          Text(label, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          const SizedBox(height: JkTokens.spacingXxs),
          AmountText(
            cents,
            signed: signed,
            colored: signed,
            style: t.titleMedium,
          ),
        ],
      ),
    );
    return Card(
      key: const Key('ledger-summary'),
      margin: const EdgeInsets.only(bottom: JkTokens.spacingSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingMd),
        child: Row(
          children: [
            cell('收入', totals.income),
            cell('支出', totals.expense),
            cell('结余', totals.balance, signed: true),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.totals});

  final DateTime day;
  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: context.jkColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingXs,
        JkTokens.spacingMd,
        JkTokens.spacingXs,
        JkTokens.spacingXs,
      ),
      child: Row(
        children: [
          Text(
            '${day.month}月${day.day}日 ${weekdayNames[day.weekday - 1]}',
            style: style,
          ),
          const SizedBox(width: JkTokens.spacingSm),
          // 金额很大或字号很大时缩小显示，不能溢出
          Expanded(
            child: Text(
              [
                if (totals.income > 0) '收 ${formatYuan(totals.income)}',
                if (totals.expense > 0) '支 ${formatYuan(totals.expense)}',
              ].join('  '),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
