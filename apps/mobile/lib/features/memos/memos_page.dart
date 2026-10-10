import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_icon.dart';
import '../../shared/ui/jk_states.dart';
import '../worklog/worklog_repository.dart';
import 'memo_calendar.dart';
import 'memo_models.dart';
import 'memo_repository.dart';
import 'memo_tile.dart';
import 'memo_widgets.dart';
import 'reminder_banner.dart';

enum MemoView { list, calendar }

/// 列表与日历的切换（本次运行内记住）。
final memoViewProvider = NotifierProvider<MemoViewController, MemoView>(
  MemoViewController.new,
);

class MemoViewController extends Notifier<MemoView> {
  @override
  MemoView build() => MemoView.list;

  void set(MemoView v) => state = v;
}

/// 日历中选中的日期。
final memoSelectedDayProvider =
    NotifierProvider<MemoSelectedDayController, DateTime>(
      MemoSelectedDayController.new,
    );

class MemoSelectedDayController extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(DateTime.now());

  void set(DateTime d) => state = d;
}

/// 备忘录主界面：待办列表（按日期分组）或日历。
class MemosPage extends ConsumerWidget {
  const MemosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(memoViewProvider);
    final day = ref.watch(memoSelectedDayProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('memo-create'),
        onPressed: () => context.push(
          view == MemoView.calendar
              ? '/memos/new?day=${formatDate(day)}'
              : '/memos/new',
        ),
        icon: const Icon(Icons.add),
        label: const Text('新建备忘'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              JkTokens.spacingLg,
              JkTokens.spacingSm,
              JkTokens.spacingLg,
              0,
            ),
            child: Center(
              child: SegmentedButton<MemoView>(
                key: const Key('memo-view'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: MemoView.list,
                    icon: Icon(Icons.checklist),
                    label: Text('列表'),
                  ),
                  ButtonSegment(
                    value: MemoView.calendar,
                    icon: Icon(Icons.calendar_month_outlined),
                    label: Text('日历'),
                  ),
                ],
                selected: {view},
                onSelectionChanged: (v) =>
                    ref.read(memoViewProvider.notifier).set(v.first),
              ),
            ),
          ),
          Expanded(
            child: switch (view) {
              MemoView.list => const _MemoList(),
              MemoView.calendar => MemoCalendar(
                selected: day,
                onSelect: ref.read(memoSelectedDayProvider.notifier).set,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _MemoList extends ConsumerWidget {
  const _MemoList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(memoListProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).sync(),
      child: list.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(JkTokens.spacingLg),
          child: JkSkeleton(lines: 6),
        ),
        error: (e, _) => JkErrorState(
          message: '读取备忘失败',
          onRetry: () => ref.invalidate(memoListProvider),
        ),
        data: (items) => items.isEmpty
            ? const _Empty()
            : _Sections(items: items, now: DateTime.now()),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: c.maxHeight,
        child: JkEmptyState(
          icon: const JkIcon(JkIcons.memos, size: 32),
          title: '还没有备忘',
          message: '记下要做的事和时间，到点提醒你；备忘也会显示在日历上。',
          actionLabel: '新建备忘',
          onAction: () => context.push('/memos/new'),
        ),
      ),
    ),
  );
}

/// 一个分组的标题。
String sectionOf(Memo m, DateTime now) {
  if (m.overdue(now)) return '已逾期';
  return friendlyDate(m.day, now);
}

class _Sections extends StatelessWidget {
  const _Sections({required this.items, required this.now});

  final List<Memo> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // 逾期的放在最前面，其余按日期分组（全天备忘的时刻是 9:00，不能让它把"今天"拆成两段）
    final open = [
      ...items.where((m) => m.overdue(now)),
      ...items.where((m) => !m.done && !m.overdue(now)),
    ];
    final done = items.where((m) => m.done).toList().reversed.toList();
    final rows = <Widget>[const ReminderBanner()];
    String? section;
    for (final m in open) {
      final s = sectionOf(m, now);
      if (s != section) {
        section = s;
        rows.add(_Header(s, warn: s == '已逾期'));
      }
      rows.add(MemoTile(memo: m, showDate: s == '已逾期'));
    }
    if (open.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(JkTokens.spacingLg),
          child: Text(
            '没有待办的备忘',
            style: TextStyle(color: context.jkColors.textSecondary),
          ),
        ),
      );
    }
    if (done.isNotEmpty) {
      rows.add(
        ExpansionTile(
          key: const Key('memo-done-section'),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: JkTokens.spacingXs,
          ),
          title: Text('已完成 ${done.length}'),
          children: [for (final m in done) MemoTile(memo: m)],
        ),
      );
    }
    return ListView(
      key: const Key('memo-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        JkTokens.spacingSm,
        JkTokens.spacingLg,
        96,
      ),
      children: [
        for (final r in rows)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: r,
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      JkTokens.spacingXs,
      JkTokens.spacingMd,
      0,
      JkTokens.spacingSm,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: warn ? context.jkColors.error : context.jkColors.textSecondary,
      ),
    ),
  );
}
