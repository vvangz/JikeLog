import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/text/markdown_text.dart';
import '../settings/settings_controller.dart';
import '../worklog/worklog_repository.dart';
import 'memo_models.dart';
import 'memo_repository.dart';
import 'memo_tile.dart';
import 'memo_widgets.dart';

/// 日历中某天的一项：备忘或工作日志。
sealed class DayItem {
  const DayItem();
}

class MemoItem extends DayItem {
  const MemoItem(this.memo);
  final Memo memo;
}

class WorklogItem extends DayItem {
  const WorklogItem(this.worklog);
  final Worklog worklog;
}

/// 按日期归类备忘与工作日志（本地日期）。
Map<DateTime, List<DayItem>> groupByDay(
  List<Memo> memos,
  List<Worklog> worklogs,
) {
  final out = <DateTime, List<DayItem>>{};
  for (final m in memos) {
    (out[m.day] ??= []).add(MemoItem(m));
  }
  for (final w in worklogs) {
    (out[dateOnly(w.date)] ??= []).add(WorklogItem(w));
  }
  return out;
}

/// 备忘录模块的日历视图：月、两周、周视图，日期下方标记备忘与工作日志，下方列出选中日期的内容。
class MemoCalendar extends ConsumerStatefulWidget {
  const MemoCalendar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  ConsumerState<MemoCalendar> createState() => _MemoCalendarState();
}

class _MemoCalendarState extends ConsumerState<MemoCalendar> {
  CalendarFormat _format = CalendarFormat.month;
  late DateTime _focused = widget.selected;

  @override
  Widget build(BuildContext context) {
    final memos = ref.watch(memoListProvider).value ?? const [];
    final worklogs = ref.watch(worklogListProvider).value ?? const [];
    final days = groupByDay(memos, worklogs);
    final weekStart = ref.watch(settingsControllerProvider).weekStart;
    final calendar = _calendar(context, days, weekStart);
    final agenda = DayAgenda(
      day: widget.selected,
      items: days[dateOnly(widget.selected)] ?? const [],
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 720
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(child: calendar),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: agenda),
              ],
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: calendar),
                const SliverToBoxAdapter(child: Divider(height: 1)),
                SliverFillRemaining(hasScrollBody: true, child: agenda),
              ],
            ),
    );
  }

  Widget _calendar(
    BuildContext context,
    Map<DateTime, List<DayItem>> days,
    int weekStart,
  ) {
    final c = context.jkColors;
    return TableCalendar<DayItem>(
      key: const Key('memo-calendar'),
      firstDay: DateTime(2000),
      lastDay: DateTime(2199, 12, 31),
      focusedDay: _focused,
      currentDay: DateTime.now(),
      calendarFormat: _format,
      availableCalendarFormats: const {
        CalendarFormat.month: '月',
        CalendarFormat.twoWeeks: '两周',
        CalendarFormat.week: '周',
      },
      startingDayOfWeek: weekStart == 7
          ? StartingDayOfWeek.sunday
          : StartingDayOfWeek.monday,
      selectedDayPredicate: (d) => isSameDay(d, widget.selected),
      eventLoader: (d) => days[dateOnly(d)] ?? const [],
      onDaySelected: (selected, focused) {
        setState(() => _focused = focused);
        widget.onSelect(dateOnly(selected));
      },
      onPageChanged: (f) => _focused = f,
      onFormatChanged: (f) => setState(() => _format = f),
      headerStyle: HeaderStyle(
        formatButtonShowsNext: false,
        titleTextFormatter: (d, _) => '${d.year} 年 ${d.month} 月',
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        dowTextFormatter: (d, _) => weekdayNames[d.weekday - 1].substring(1),
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: c.primaryContainer,
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(color: c.onPrimaryContainer),
        selectedDecoration: BoxDecoration(
          color: c.primary,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(color: c.onPrimary),
      ),
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, day, items) =>
            items.isEmpty ? null : _Markers(items: items),
      ),
    );
  }
}

/// 日期下方的标记：咖色点为备忘，灰色点为工作日志。
class _Markers extends StatelessWidget {
  const _Markers({required this.items});

  final List<DayItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final memo = items.any((i) => i is MemoItem);
    final worklog = items.any((i) => i is WorklogItem);
    Widget dot(Color color) => Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Positioned(
      bottom: 4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [if (memo) dot(c.primary), if (worklog) dot(c.textSecondary)],
      ),
    );
  }
}

/// 选中日期的备忘与工作日志。
class DayAgenda extends StatelessWidget {
  const DayAgenda({super.key, required this.day, required this.items});

  final DateTime day;
  final List<DayItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final memos = [
      for (final i in items)
        if (i is MemoItem) i.memo,
    ];
    final worklogs = [
      for (final i in items)
        if (i is WorklogItem) i.worklog,
    ];
    return ListView(
      key: const Key('memo-agenda'),
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        JkTokens.spacingMd,
        JkTokens.spacingLg,
        96,
      ),
      children: [
        Text(
          friendlyDate(day, DateTime.now()),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: JkTokens.spacingSm),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingLg),
            child: Text(
              '这一天没有备忘和工作日志',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        for (final m in memos) MemoTile(memo: m, showDate: false),
        for (final w in worklogs)
          Card(
            margin: const EdgeInsets.only(bottom: JkTokens.spacingSm),
            child: ListTile(
              key: Key('agenda-worklog-${w.id}'),
              leading: const Icon(Icons.work_outline),
              title: Text(w.location.isEmpty ? '工作日志' : w.location),
              subtitle: Text(
                plainPreview(w.content).isEmpty
                    ? '（未填写内容）'
                    : plainPreview(w.content),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => context.push('/worklog/${w.id}'),
            ),
          ),
      ],
    );
  }
}
