import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/sync_badges.dart';
import 'memo_models.dart';
import 'memo_repository.dart';
import 'memo_widgets.dart';

/// 列表中的一条备忘：勾选完成、标题、时间与提醒。
class MemoTile extends ConsumerWidget {
  const MemoTile({super.key, required this.memo, this.showDate = true});

  final Memo memo;

  /// 列表按日期分组时只显示时间。
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final m = memo;
    final now = DateTime.now();
    final overdue = m.overdue(now);
    final when = showDate
        ? memoWhen(m, now)
        : (m.allDay ? '全天' : formatClock(m.at));
    return Card(
      key: Key('memo-${m.id}'),
      margin: const EdgeInsets.only(bottom: JkTokens.spacingSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        onTap: () => context.push('/memos/${m.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: JkTokens.spacingSm,
            vertical: JkTokens.spacingXs,
          ),
          child: Row(
            children: [
              Checkbox(
                key: Key('memo-check-${m.id}'),
                value: m.done,
                onChanged: (v) => ref
                    .read(memoRepositoryProvider)
                    .update(m.id, done: v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: JkTokens.spacingSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(
                          decoration: m.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: m.done ? c.textDisabled : null,
                        ),
                      ),
                      const SizedBox(height: JkTokens.spacingXxs),
                      Row(
                        children: [
                          Text(
                            when,
                            style: t.bodySmall?.copyWith(
                              color: overdue ? c.error : c.textSecondary,
                            ),
                          ),
                          if (m.reminders.isNotEmpty && !m.done) ...[
                            const SizedBox(width: JkTokens.spacingSm),
                            Icon(
                              Icons.notifications_none,
                              size: 14,
                              color: c.textSecondary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SyncBadges(
                pending: m.pending,
                hasConflict: m.hasConflict,
                syncError: m.syncError,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
