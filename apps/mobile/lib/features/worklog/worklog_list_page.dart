import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_icon.dart';
import '../../shared/text/markdown_text.dart';
import '../../shared/ui/jk_states.dart';
import '../../shared/ui/sync_badges.dart';
import 'worklog_repository.dart';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 工作日志主界面：按月分组的日志列表。
class WorklogListPage extends ConsumerWidget {
  const WorklogListPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final id = await ref.read(worklogRepositoryProvider).create();
    if (context.mounted) await context.push('/worklog/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(worklogListProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('worklog-create'),
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('写日志'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncEngineProvider).sync(),
        child: list.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(JkTokens.spacingLg),
            child: JkSkeleton(lines: 6),
          ),
          error: (e, _) => JkErrorState(
            message: '读取日志失败',
            onRetry: () => ref.invalidate(worklogListProvider),
          ),
          data: (items) => items.isEmpty
              ? _Empty(onCreate: () => _create(context, ref))
              : _List(items: items),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // 内容不足一屏时也能下拉刷新
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: c.maxHeight,
        child: JkEmptyState(
          icon: const JkIcon(JkIcons.worklog, size: 32),
          title: '还没有工作日志',
          message: '记录每天的工作地点、内容和附件，内容加密传输，多设备自动同步。',
          actionLabel: '写第一篇日志',
          onAction: onCreate,
        ),
      ),
    ),
  );
}

class _List extends StatelessWidget {
  const _List({required this.items});

  final List<Worklog> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? month;
    for (final w in items) {
      final m = '${w.date.year} 年 ${w.date.month} 月';
      if (m != month) {
        month = m;
        rows.add(_MonthHeader(m));
      }
      rows.add(_WorklogTile(worklog: w));
    }
    return ListView(
      key: const Key('worklog-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        JkTokens.spacingSm,
        JkTokens.spacingLg,
        96, // 给悬浮按钮留出空间
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

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      JkTokens.spacingXs,
      JkTokens.spacingLg,
      0,
      JkTokens.spacingSm,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: context.jkColors.textSecondary),
    ),
  );
}

class _WorklogTile extends StatelessWidget {
  const _WorklogTile({required this.worklog});

  final Worklog worklog;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final w = worklog;
    final preview = plainPreview(w.content);
    return Card(
      margin: const EdgeInsets.only(bottom: JkTokens.spacingSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        onTap: () => context.push('/worklog/${w.id}'),
        child: Padding(
          padding: const EdgeInsets.all(JkTokens.spacingLg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    Text('${w.date.day}', style: t.headlineSmall),
                    Text(
                      _weekdays[w.date.weekday - 1],
                      style: t.bodySmall?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: JkTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (w.location.isNotEmpty) ...[
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: JkTokens.spacingXxs),
                          Flexible(
                            child: Text(
                              w.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelLarge,
                            ),
                          ),
                        ],
                        const Spacer(),
                        SyncBadges(
                          pending: w.pending,
                          hasConflict: w.hasConflict,
                          syncError: w.syncError,
                        ),
                      ],
                    ),
                    const SizedBox(height: JkTokens.spacingXs),
                    Text(
                      preview.isEmpty ? '（未填写内容）' : preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        color: preview.isEmpty ? c.textDisabled : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
