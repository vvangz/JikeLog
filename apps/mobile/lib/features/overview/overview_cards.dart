import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_icon.dart';
import '../../shared/ui/jk_states.dart';
import '../ledger/money.dart';
import '../memos/memo_models.dart';
import 'overview_charts.dart';
import 'overview_providers.dart';
import 'overview_stats.dart';

const _tabular = [FontFeature.tabularFigures()];

/// 概览卡片外框：图标 + 标题 + 右箭头，整张卡片点击进入模块。
class OverviewCard extends StatelessWidget {
  const OverviewCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    required this.child,
    this.trailing,
  });

  final JkIcons icon;
  final String title;
  final VoidCallback onTap;
  final Widget child;

  /// 标题行右侧、箭头之前的附加按钮。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JkTokens.radiusLg),
        side: BorderSide(color: c.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            JkTokens.spacingLg + 4,
            JkTokens.spacingLg,
            JkTokens.spacingMd,
            JkTokens.spacingLg + 4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.primaryContainer,
                        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
                      ),
                      child: JkIcon(
                        icon,
                        size: 18,
                        color: c.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: JkTokens.spacingMd),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ?trailing,
                    Icon(Icons.chevron_right, size: 20, color: c.textDisabled),
                  ],
                ),
              ),
              const SizedBox(height: JkTokens.spacingMd),
              Padding(
                padding: const EdgeInsets.only(right: JkTokens.spacingSm),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 数字从旧值滚动到新值（减少动画时直接显示）。
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.style,
    this.format,
  });

  final num value;
  final TextStyle? style;

  /// 格式化（默认取整）。
  final String Function(double v)? format;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        format?.call(v) ?? v.round().toString(),
        style: style,
        maxLines: 1,
      ),
    );
  }
}

/// 大号数字 + 单位，下方一行说明。
class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.value,
    required this.unit,
    required this.label,
    this.color,
  });

  final int value;
  final String unit;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$label $value $unit',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AnimatedNumber(value: value, style: _bigStyle(context, color)),
              const SizedBox(width: JkTokens.spacingXs),
              Flexible(
                child: Text(
                  unit,
                  style: t.bodyMedium?.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          Text(label, style: t.bodySmall?.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

TextStyle? _bigStyle(BuildContext context, [Color? color]) =>
    Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: 34,
      height: 1.15,
      letterSpacing: -0.5,
      fontWeight: FontWeight.w600,
      color: color ?? context.jkColors.textPrimary,
      fontFeatures: _tabular,
    );

/// 小号指标：上方说明，下方数值。
class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          const SizedBox(height: JkTokens.spacingXxs),
          Text(
            value,
            style: t.titleMedium?.copyWith(
              color: color ?? c.textPrimary,
              fontWeight: FontWeight.w600,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// 左侧大号指标，右侧若干小指标（空间不足时小指标换行）。
class _StatRow extends StatelessWidget {
  const _StatRow({required this.big, required this.minis});

  final Widget big;
  final List<Widget> minis;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(child: big),
      Flexible(
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: JkTokens.spacingXl,
          runSpacing: JkTokens.spacingSm,
          children: minis,
        ),
      ),
    ],
  );
}

/// 卡片内的小标题（如"接下来""最近编辑"）。
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: JkTokens.spacingXs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: context.jkColors.textSecondary),
    ),
  );
}

/// 卡片内的一行可点击条目：左侧主文字，右侧次要文字。
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.itemKey,
    required this.title,
    required this.meta,
    required this.onTap,
    this.leading,
  });

  final Key itemKey;
  final String title;
  final String meta;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      key: itemKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(JkTokens.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: JkTokens.spacingSm),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium,
              ),
            ),
            const SizedBox(width: JkTokens.spacingSm),
            Text(
              meta,
              style: t.bodySmall?.copyWith(
                color: c.textSecondary,
                fontFeatures: _tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片内容的加载与出错状态。
Widget _async<T>(AsyncValue<T> value, Widget Function(T data) data) =>
    value.when(
      skipLoadingOnReload: true,
      loading: () => const JkSkeleton(lines: 3),
      error: (_, _) => const _CardError(),
      data: data,
    );

class _CardError extends StatelessWidget {
  const _CardError();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingLg),
    child: Text(
      '读取失败，下拉刷新重试',
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.jkColors.error),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingSm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.jkColors.textSecondary),
    ),
  );
}

/// 工作日志：连续天数、本月篇数、记录热力图。
class WorklogCard extends ConsumerWidget {
  const WorklogCard({super.key, this.heatmapHeight = 95});

  /// 热力图高度（格子大小随之变化）；宽屏两列时加大以填满卡片。
  final double heatmapHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    return OverviewCard(
      key: const Key('overview-worklog'),
      icon: JkIcons.worklog,
      title: '工作日志',
      onTap: () => context.go('/worklog'),
      child: _async(
        ref.watch(worklogSummaryProvider),
        (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatRow(
              big: _BigStat(value: s.streak, unit: '天', label: '连续记录'),
              minis: [
                _MiniStat(label: '本月', value: '${s.thisMonth} 篇'),
                _MiniStat(
                  label: '今日',
                  value: s.writtenToday ? '已写' : '未写',
                  color: s.writtenToday ? c.success : c.warning,
                ),
              ],
            ),
            const SizedBox(height: JkTokens.spacingLg),
            Heatmap(weeks: s.heatmap, height: heatmapHeight),
            const SizedBox(height: JkTokens.spacingSm),
            const Row(
              children: [
                Expanded(child: _Caption('按天记录')),
                HeatmapLegend(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 备忘录：今日待办、已逾期、本周完成率、接下来的备忘。
class MemoCard extends ConsumerWidget {
  const MemoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final now = DateTime.now();
    return OverviewCard(
      key: const Key('overview-memos'),
      icon: JkIcons.memos,
      title: '备忘录',
      onTap: () => context.go('/memos'),
      child: _async(
        ref.watch(memoSummaryProvider),
        (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: JkTokens.spacingXl,
                    runSpacing: JkTokens.spacingSm,
                    children: [
                      _BigStat(value: s.today, unit: '条', label: '今日待办'),
                      _BigStat(
                        value: s.overdue,
                        unit: '条',
                        label: '已逾期',
                        color: s.overdue > 0 ? c.error : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: JkTokens.spacingMd),
                Column(
                  children: [
                    CompletionRing(ratio: s.weekRate),
                    const SizedBox(height: JkTokens.spacingXs),
                    Text(
                      '本周完成',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: JkTokens.spacingLg),
            const _Caption('接下来'),
            if (s.upcoming.isEmpty)
              const _EmptyHint('接下来没有待办')
            else
              for (final m in s.upcoming)
                _ItemRow(
                  itemKey: Key('overview-memo-${m.id}'),
                  title: m.title,
                  meta: memoWhen(m, now),
                  onTap: () => context.push('/memos/${m.id}'),
                  leading: Icon(Icons.circle, size: 6, color: c.primary),
                ),
          ],
        ),
      ),
    );
  }
}

/// 备忘时间的简短说明：今天 14:00 / 明天 全天 / 10月30日 09:30。
String memoWhen(Memo m, DateTime now) {
  final days = m.day.difference(dateOnly(now)).inDays;
  final day = switch (days) {
    0 => '今天',
    1 => '明天',
    2 => '后天',
    _ =>
      m.at.year == now.year
          ? '${m.at.month}月${m.at.day}日'
          : '${m.at.year}年${m.at.month}月${m.at.day}日',
  };
  if (m.allDay) return '$day 全天';
  final hh = m.at.hour.toString().padLeft(2, '0');
  final mm = m.at.minute.toString().padLeft(2, '0');
  return '$day $hh:$mm';
}

/// 记账：本月收支、近 30 天支出走势、净资产；金额可隐藏。
class LedgerCard extends ConsumerWidget {
  const LedgerCard({super.key});

  static const _mask = '****';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final hidden = ref.watch(amountsHiddenProvider);
    String money(int cents, {bool sign = false}) =>
        hidden ? _mask : formatYuan(cents, sign: sign);
    return OverviewCard(
      key: const Key('overview-ledger'),
      icon: JkIcons.ledger,
      title: '记账',
      onTap: () => context.go('/ledger'),
      trailing: IconButton(
        key: const Key('overview-hide-amounts'),
        tooltip: hidden ? '显示金额' : '隐藏金额',
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: c.textSecondary,
        icon: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        onPressed: () => ref.read(amountsHiddenProvider.notifier).toggle(),
      ),
      child: _async(ref.watch(ledgerSummaryProvider), (s) {
        if (!s.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _EmptyHint('还没有记账。记下第一笔，收支走势会显示在这里。'),
              TextButton.icon(
                onPressed: () => context.push('/ledger/entry/new'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('记一笔'),
              ),
            ],
          );
        }
        final expense = s.month.expense;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: '本月支出 ${hidden ? '已隐藏' : '${formatYuan(expense)} 元'}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '¥',
                        style: t.titleMedium?.copyWith(color: c.textSecondary),
                      ),
                      const SizedBox(width: JkTokens.spacingXxs),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: hidden
                              ? Text(
                                  _mask,
                                  key: const Key('overview-expense'),
                                  style: _bigStyle(context),
                                )
                              : AnimatedNumber(
                                  key: const Key('overview-expense'),
                                  value: expense,
                                  style: _bigStyle(context),
                                  format: (v) => formatYuan(v.round()),
                                ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '本月支出',
                    style: t.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: JkTokens.spacingMd),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: '本月收入',
                    value: money(s.month.income),
                    color: hidden ? null : c.success,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: '本月结余',
                    value: money(s.month.balance, sign: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: JkTokens.spacingLg),
            Sparkline(values: s.daily),
            const SizedBox(height: JkTokens.spacingXs),
            const _Caption('近 30 天支出'),
            Divider(height: JkTokens.spacingLg, color: c.divider),
            Semantics(
              label:
                  '净资产 ${hidden ? '已隐藏' : '${formatYuan(s.netWorth.total)} 元'}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '净资产',
                      style: t.bodyMedium?.copyWith(color: c.textSecondary),
                    ),
                  ),
                  Text(
                    money(s.netWorth.total),
                    key: const Key('overview-net-worth'),
                    style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// 笔记：总数、近 7 天编辑、收藏、最近编辑的笔记。
class NoteCard extends ConsumerWidget {
  const NoteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return OverviewCard(
      key: const Key('overview-notes'),
      icon: JkIcons.notes,
      title: '笔记',
      onTap: () => context.go('/notes'),
      child: _async(
        ref.watch(noteSummaryProvider),
        (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatRow(
              big: _BigStat(value: s.total, unit: '篇', label: '全部笔记'),
              minis: [
                _MiniStat(label: '近 7 天编辑', value: '${s.recentlyEdited}'),
                _MiniStat(label: '收藏', value: '${s.favorites}'),
              ],
            ),
            const SizedBox(height: JkTokens.spacingLg),
            const _Caption('最近编辑'),
            if (s.recent.isEmpty)
              const _EmptyHint('还没有笔记')
            else
              for (final n in s.recent)
                _ItemRow(
                  itemKey: Key('overview-note-${n.id}'),
                  title: n.displayTitle,
                  meta: relativeTime(n.updatedAt, now),
                  onTap: () => context.push('/notes/${n.id}'),
                ),
          ],
        ),
      ),
    );
  }
}
