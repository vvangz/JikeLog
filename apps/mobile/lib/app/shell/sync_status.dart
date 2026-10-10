import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import '../theme/app_theme.dart';
import '../theme/jk_tokens.g.dart';

/// 侧栏底部的同步状态：同步中、离线、待同步条数、最后同步时间。点击立即同步。
class SyncStatusLine extends ConsumerWidget {
  const SyncStatusLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final status = ref.watch(syncStatusProvider).value;
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final last = status?.lastSyncedAt;
    final (text, color) = switch (status?.phase) {
      SyncPhase.syncing => ('同步中…', c.info),
      SyncPhase.offline => (
        pending > 0 ? '离线 · $pending 条待同步' : '离线，联网后自动同步',
        c.warning,
      ),
      SyncPhase.error => ('同步失败，稍后自动重试', c.error),
      _ when pending > 0 => ('$pending 条待同步', c.warning),
      _ when last != null => (
        '已同步 · ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}',
        c.success,
      ),
      _ => ('已同步', c.success),
    };
    return InkWell(
      key: const Key('sync-status'),
      onTap: () => ref.read(syncEngineProvider).sync(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingXs),
        child: Row(
          children: [
            Icon(Icons.sync, size: 14, color: color),
            const SizedBox(width: JkTokens.spacingSm),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
