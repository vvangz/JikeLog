import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_icon.dart';
import '../auth/auth_controller.dart';
import '../memos/memos_page.dart';
import '../notes/notes_list_page.dart';
import '../worklog/worklog_list_page.dart';
import 'overview_cards.dart';
import 'overview_providers.dart';
import 'overview_stats.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 内容区宽度达到此值时卡片两列排列。
const _twoColumnWidth = 600.0;
const _maxContentWidth = 1040.0;

/// 概览（默认首页）：问候与快捷操作，以及四个模块的统计卡片。
class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({super.key});

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 卡片错落淡入。
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// 到下一个零点时重新计算（页面一直开着时"今天"也随之更新）。
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight?.cancel();
    // 多等一秒，避免计时器略早触发时仍算作前一天
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _refreshNow();
      _scheduleMidnight();
    });
  }

  /// 概况按计算时的当前时间统计：回到前台或跨过零点后重新计算。
  void _refreshNow() {
    if (!mounted) return;
    ref
      ..invalidate(worklogSummaryProvider)
      ..invalidate(memoSummaryProvider)
      ..invalidate(noteSummaryProvider)
      ..invalidate(ledgerSummaryProvider);
    setState(() {}); // 主卡的日期与问候
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNow();
      _scheduleMidnight();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reveal.isDismissed) {
      MediaQuery.of(context).disableAnimations
          ? _reveal.value = 1
          : _reveal.forward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  Widget _item(int index, Widget child) =>
      _Reveal(animation: _reveal, index: index, child: child);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).sync(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _twoColumnWidth;
          final gutter = wide ? JkTokens.spacingXl : JkTokens.spacingLg;
          final width = math.min(
            constraints.maxWidth - gutter * 2,
            _maxContentWidth,
          );
          const gap = SizedBox.square(dimension: JkTokens.spacingLg);
          final cards = [
            WorklogCard(heatmapHeight: wide ? 136 : 95),
            const MemoCard(),
            const LedgerCard(),
            const NoteCard(),
          ];
          Widget pair(int i) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _item(i + 1, cards[i])),
                gap,
                Expanded(child: _item(i + 2, cards[i + 1])),
              ],
            ),
          );
          return ListView(
            key: const Key('overview-page'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              gutter,
              JkTokens.spacingLg,
              gutter,
              JkTokens.spacingXxl,
            ),
            children: [
              Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _item(0, const _Hero()),
                      gap,
                      if (wide) ...[
                        pair(0),
                        gap,
                        pair(2),
                      ] else
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) gap,
                          _item(i + 1, cards[i]),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 按序号错开的淡入上移。
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.index,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = math.min(index * 0.1, 0.4);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, start + 0.6, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// 顶部主卡：日期、问候、今日摘要与快捷操作。
class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? c.onPrimaryContainer : c.onPrimary;
    final now = DateTime.now();
    final auth = ref.watch(authControllerProvider);
    final name = auth is SignedIn ? auth.user.displayName : null;
    final greeting = name == null || name.isEmpty
        ? greetingFor(now)
        : '${greetingFor(now)}，$name';
    final summary = _summary(
      ref.watch(memoSummaryProvider).value,
      ref.watch(worklogSummaryProvider).value,
    );

    return Container(
      key: const Key('overview-hero'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(JkTokens.radiusLg + 4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [c.primaryContainer, c.surfaceVariant]
              : [c.primary, c.onPrimaryContainer],
        ),
      ),
      child: CustomPaint(
        painter: _HeroRings(fg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            JkTokens.spacingXl,
            JkTokens.spacingXl,
            JkTokens.spacingXl,
            JkTokens.spacingLg + 4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${now.month}月${now.day}日 ${_weekdays[now.weekday - 1]}',
                style: t.bodySmall?.copyWith(
                  color: fg.withValues(alpha: 0.72),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: JkTokens.spacingXs),
              Text(
                greeting,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.headlineSmall?.copyWith(color: fg),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: JkTokens.spacingXs),
                Text(
                  summary,
                  key: const Key('overview-summary'),
                  style: t.bodyMedium?.copyWith(
                    color: fg.withValues(alpha: 0.82),
                  ),
                ),
              ],
              const SizedBox(height: JkTokens.spacingXl),
              Row(
                children: [
                  for (final (i, a) in _actions(context, ref).indexed) ...[
                    if (i > 0) const SizedBox(width: JkTokens.spacingSm),
                    Expanded(
                      child: _QuickAction(action: a, color: fg),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _summary(MemoSummary? memos, WorklogSummary? logs) => [
    if (memos != null) ...[
      memos.today > 0 ? '今天 ${memos.today} 条备忘待完成' : '今天没有待办',
      if (memos.overdue > 0) '${memos.overdue} 条已逾期',
    ],
    if (logs != null) logs.writtenToday ? '今日日志已写' : '今日日志还没写',
  ].join(' · ');

  static List<_Action> _actions(BuildContext context, WidgetRef ref) => [
    _Action(
      id: 'worklog',
      label: '写日志',
      icon: JkIcons.worklog,
      onTap: () => unawaited(createWorklog(context, ref)),
    ),
    _Action(
      id: 'note',
      label: '新笔记',
      icon: JkIcons.notes,
      onTap: () => unawaited(createNote(context, ref)),
    ),
    _Action(
      id: 'memo',
      label: '新备忘',
      icon: JkIcons.memos,
      onTap: () => createMemo(context, ref),
    ),
    _Action(
      id: 'entry',
      label: '记一笔',
      icon: JkIcons.ledger,
      onTap: () => unawaited(context.push('/ledger/entry/new')),
    ),
  ];
}

class _Action {
  const _Action({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String id;
  final String label;
  final JkIcons icon;
  final VoidCallback onTap;
}

/// 主卡上的半透明快捷按钮。
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.action, required this.color});

  final _Action action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(JkTokens.radiusMd);
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      onTap: action.onTap,
      child: Material(
        color: color.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: color.withValues(alpha: 0.16)),
        ),
        child: InkWell(
          key: Key('overview-action-${action.id}'),
          borderRadius: radius,
          onTap: action.onTap,
          splashColor: color.withValues(alpha: 0.12),
          highlightColor: color.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: JkTokens.spacingMd,
              horizontal: JkTokens.spacingXs,
            ),
            child: Column(
              children: [
                JkIcon(action.icon, size: 22, color: color),
                const SizedBox(height: JkTokens.spacingXs + 2),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 主卡右上角的装饰同心圆。
class _HeroRings extends CustomPainter {
  const _HeroRings(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 24, 8);
    final p = Paint()..style = PaintingStyle.fill;
    canvas
      ..drawCircle(center, 132, p..color = color.withValues(alpha: 0.04))
      ..drawCircle(center, 88, p..color = color.withValues(alpha: 0.05))
      ..drawCircle(center, 48, p..color = color.withValues(alpha: 0.06));
  }

  @override
  bool shouldRepaint(_HeroRings old) => old.color != color;
}
