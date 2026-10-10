import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import 'ledger_models.dart';
import 'ledger_presets.dart';
import 'ledger_repository.dart';
import 'ledger_stats.dart';
import 'ledger_widgets.dart';
import 'money.dart';

/// 统计页的查看条件。
@immutable
class StatsQuery {
  const StatsQuery({
    required this.anchor,
    this.yearly = false,
    this.kind = CategoryKind.expense,
    this.parentId,
  });

  final DateTime anchor;
  final bool yearly;
  final CategoryKind kind;

  /// 展开查看的一级分类。
  final String? parentId;

  Period get period => yearly
      ? Period.year(anchor.year)
      : Period.month(anchor.year, anchor.month);

  StatsQuery copyWith({
    DateTime? anchor,
    bool? yearly,
    CategoryKind? kind,
    String? Function()? parentId,
  }) => StatsQuery(
    anchor: anchor ?? this.anchor,
    yearly: yearly ?? this.yearly,
    kind: kind ?? this.kind,
    parentId: parentId == null ? this.parentId : parentId(),
  );
}

final statsQueryProvider = NotifierProvider<StatsQueryController, StatsQuery>(
  StatsQueryController.new,
);

class StatsQueryController extends Notifier<StatsQuery> {
  @override
  StatsQuery build() => StatsQuery(anchor: DateTime.now());

  void set(StatsQuery q) => state = q;
}

/// 饼图配色：咖色系与互补色，依次使用。
const _palette = [
  Color(0xFF6F4E37),
  Color(0xFFC8A27C),
  Color(0xFF8C6A4F),
  Color(0xFF4F7C82),
  Color(0xFFB5838D),
  Color(0xFF7D8F69),
  Color(0xFFD9B38C),
  Color(0xFF9E9E9E),
];

/// 饼图最多单独显示的分类数，其余合并为"其他"。
const _maxSlices = 7;

/// 统计：收支合计、分类占比（饼图与排行，可展开二级分类）、收支趋势。
class StatsTab extends ConsumerWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(statsQueryProvider);
    final ctl = ref.read(statsQueryProvider.notifier);
    final entries = ref.watch(entriesProvider).value ?? const <Entry>[];
    final cats = {
      for (final c
          in ref.watch(categoriesProvider).value ?? const <LedgerCategory>[])
        c.id: c,
    };
    final totals = periodTotals(entries, q.period);
    final shares = categoryShares(
      entries,
      cats,
      q.kind,
      q.period,
      parentId: q.parentId,
      feeCategoryId: ref.watch(feeCategoryIdProvider),
    );
    final points = trend(
      entries,
      q.period,
      q.yearly ? TrendUnit.month : TrendUnit.day,
    );
    final parent = cats[q.parentId];
    return ListView(
      key: const Key('ledger-stats'),
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        0,
        JkTokens.spacingLg,
        96,
      ),
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              key: const Key('stats-range'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('月')),
                ButtonSegment(value: true, label: Text('年')),
              ],
              selected: {q.yearly},
              onSelectionChanged: (v) => ctl.set(q.copyWith(yearly: v.first)),
            ),
            PeriodSwitcher(
              anchor: q.anchor,
              yearly: q.yearly,
              onChanged: (d) => ctl.set(q.copyWith(anchor: d)),
            ),
          ],
        ),
        _TotalsRow(totals: totals),
        const SizedBox(height: JkTokens.spacingMd),
        Center(
          child: SegmentedButton<CategoryKind>(
            key: const Key('stats-kind'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: CategoryKind.expense, label: Text('支出构成')),
              ButtonSegment(value: CategoryKind.income, label: Text('收入构成')),
            ],
            selected: {q.kind},
            onSelectionChanged: (v) =>
                ctl.set(q.copyWith(kind: v.first, parentId: () => null)),
          ),
        ),
        if (parent != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('stats-back'),
              onPressed: () => ctl.set(q.copyWith(parentId: () => null)),
              icon: const Icon(Icons.arrow_back),
              label: Text('${parent.name} 的明细'),
            ),
          ),
        if (shares.isEmpty)
          Padding(
            padding: const EdgeInsets.all(JkTokens.spacingXl),
            child: Center(
              child: Text(
                '这段时间没有${q.kind.label}',
                style: TextStyle(color: context.jkColors.textSecondary),
              ),
            ),
          )
        else ...[
          _Pie(shares: shares, categories: cats),
          for (final (i, s) in shares.indexed)
            _ShareRow(
              share: s,
              category: cats[s.categoryId],
              color: _palette[i < _maxSlices ? i : _palette.length - 1],
              canDrill:
                  q.parentId == null &&
                  s.categoryId != null &&
                  cats.values.any((c) => c.parentId == s.categoryId),
              onDrill: () => ctl.set(q.copyWith(parentId: () => s.categoryId)),
            ),
        ],
        const SizedBox(height: JkTokens.spacingLg),
        Text('收支趋势', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: JkTokens.spacingSm),
        _Trend(points: points, yearly: q.yearly),
      ],
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.totals});

  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget cell(String label, int v, {bool signed = false}) => Expanded(
      child: Column(
        children: [
          Text(label, style: t.bodySmall),
          AmountText(v, signed: signed, colored: signed, style: t.titleMedium),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
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

class _Pie extends StatelessWidget {
  const _Pie({required this.shares, required this.categories});

  final List<CategoryShare> shares;
  final Map<String, LedgerCategory> categories;

  @override
  Widget build(BuildContext context) {
    final total = shares.fold(0, (a, s) => a + s.amount);
    final head = shares.take(_maxSlices).toList();
    final rest = shares.skip(_maxSlices).fold(0, (a, s) => a + s.amount);
    final sections = [
      for (final (i, s) in head.indexed)
        PieChartSectionData(
          value: s.amount.toDouble(),
          color: _palette[i],
          radius: 48,
          showTitle: s.ratio >= 0.08,
          title: '${(s.ratio * 100).round()}%',
          titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      if (rest > 0)
        PieChartSectionData(
          value: rest.toDouble(),
          color: _palette.last,
          radius: 48,
          showTitle: false,
        ),
    ];
    return Semantics(
      label: '分类占比图，合计 ${formatYuan(total)} 元',
      child: SizedBox(
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 56,
                sectionsSpace: 1,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('合计', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  formatYuan(total),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.share,
    required this.category,
    required this.color,
    required this.canDrill,
    required this.onDrill,
  });

  final CategoryShare share;
  final LedgerCategory? category;
  final Color color;
  final bool canDrill;
  final VoidCallback onDrill;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final name = category?.name ?? '未分类';
    return ListTile(
      key: Key('share-${share.categoryId}'),
      contentPadding: EdgeInsets.zero,
      leading: LedgerAvatar(icon: categoryIcon(category?.icon ?? '')),
      title: Row(
        children: [
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: JkTokens.spacingSm),
          Flexible(child: AmountText(share.amount, colored: false)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: JkTokens.spacingXs),
        child: Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: share.ratio,
                color: color,
                backgroundColor: c.surfaceVariant,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: JkTokens.spacingSm),
            Flexible(
              child: Text(
                '${(share.ratio * 100).toStringAsFixed(1)}% · ${share.count} 笔',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
      trailing: canDrill ? const Icon(Icons.chevron_right) : null,
      onTap: canDrill ? onDrill : null,
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.points, required this.yearly});

  final List<TrendPoint> points;
  final bool yearly;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final groups = [
      for (final (i, p) in points.indexed)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: p.totals.income / 100,
              color: c.success,
              width: yearly ? 8 : 3,
            ),
            BarChartRodData(
              toY: p.totals.expense / 100,
              color: c.primary,
              width: yearly ? 8 : 3,
            ),
          ],
        ),
    ];
    String label(double v) {
      final i = v.toInt();
      if (i < 0 || i >= points.length) return '';
      final d = points[i].start;
      if (yearly) return '${d.month}';
      return d.day == 1 || d.day % 5 == 0 ? '${d.day}' : '';
    }

    return Semantics(
      label: '收支趋势图，绿色为收入，咖色为支出',
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            barGroups: groups,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: const BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, _) => Text(
                    label(v),
                    style: TextStyle(fontSize: 10, color: c.textSecondary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
