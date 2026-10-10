import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_icon.dart';
import '../../shared/ui/jk_states.dart';
import '../../shared/ui/sync_badges.dart';
import 'note_filter_panel.dart';
import 'note_filters.dart';
import 'note_models.dart';
import 'note_repository.dart';

/// 页面宽度达到此值时筛选面板常驻左侧。
const _panelBreakpoint = 720.0;

/// 笔记主界面：按文件夹、标签、收藏筛选的笔记列表。
class NotesListPage extends ConsumerWidget {
  const NotesListPage({super.key});

  /// 新建笔记：在当前文件夹或标签下，默认富文本格式。
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final filter = ref.read(noteFilterProvider);
    final id = await ref
        .read(noteRepositoryProvider)
        .create(
          format: NoteFormat.rich,
          folderId: filter is FolderNotes ? filter.folderId : null,
          tag: filter is TagNotes ? filter.tag : null,
          favorite: filter is FavoriteNotes,
        );
    if (context.mounted) await context.push('/notes/$id');
  }

  void _openPanel(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scroll) => NoteFilterPanel(
        scroll: scroll,
        onSelected: () => Navigator.of(sheet).pop(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('note-create'),
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建笔记'),
      ),
      // 按页面自身的宽度判断（宽屏时左侧还有常驻的导航侧栏）
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _panelBreakpoint) {
            return _NoteList(onOpenPanel: () => _openPanel(context));
          }
          return Row(
            children: [
              const SizedBox(width: 280, child: NoteFilterPanel()),
              VerticalDivider(width: 1, color: context.jkColors.divider),
              const Expanded(child: _NoteList()),
            ],
          );
        },
      ),
    );
  }
}

class _NoteList extends ConsumerWidget {
  const _NoteList({this.onOpenPanel});

  final VoidCallback? onOpenPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(noteListProvider);
    final tree = ref.watch(noteFoldersProvider).value ?? FolderTree(const []);
    final filter = ref.watch(noteFilterProvider);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        JkTokens.spacingSm,
        JkTokens.spacingSm,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              filter.label(tree),
              key: const Key('note-filter-label'),
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onOpenPanel != null)
            TextButton.icon(
              key: const Key('note-filter-open'),
              onPressed: onOpenPanel,
              icon: const Icon(Icons.filter_list, size: 18),
              label: const Text('文件夹与标签'),
            ),
        ],
      ),
    );
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).sync(),
      child: notes.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(JkTokens.spacingLg),
          child: JkSkeleton(lines: 6),
        ),
        error: (e, _) => JkErrorState(
          message: '读取笔记失败',
          onRetry: () => ref.invalidate(noteListProvider),
        ),
        data: (all) {
          final items = applyFilter(all, filter, tree);
          final empty = Padding(
            padding: const EdgeInsets.only(top: JkTokens.spacingXxl),
            child: JkEmptyState(
              icon: const JkIcon(JkIcons.notes, size: 32),
              title: all.isEmpty ? '还没有笔记' : '这里还没有笔记',
              message: all.isEmpty
                  ? '支持 Markdown 与富文本、代码块、表格、待办清单，可以插入图片、PDF、录音等附件'
                  : '点击右下角新建笔记',
            ),
          );
          // 按需构建：笔记多时只构建屏幕上的条目
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96), // 给悬浮按钮留出空间
            itemCount: 1 + (items.isEmpty ? 1 : items.length),
            itemBuilder: (context, i) {
              if (i == 0) return header;
              if (items.isEmpty) return empty;
              final n = items[i - 1];
              return Center(
                key: ValueKey(n.id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: JkTokens.spacingLg,
                    ),
                    child: _NoteTile(note: n, tree: tree),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.tree});

  final Note note;
  final FolderTree tree;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final n = note;
    final excerpt = n.excerpt;
    final folder = n.folderId != null && tree.byId.containsKey(n.folderId)
        ? tree.byId[n.folderId]!.name
        : null;
    return Card(
      margin: const EdgeInsets.only(top: JkTokens.spacingSm),
      child: InkWell(
        key: Key('note-${n.id}'),
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        onTap: () => context.push('/notes/${n.id}'),
        child: Padding(
          padding: const EdgeInsets.all(JkTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (n.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: JkTokens.spacingXs),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: c.primary,
                        semanticLabel: '已置顶',
                      ),
                    ),
                  Expanded(
                    child: Text(
                      n.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium,
                    ),
                  ),
                  if (n.favorite)
                    Icon(
                      Icons.star,
                      size: 16,
                      color: c.warning,
                      semanticLabel: '已收藏',
                    ),
                  SyncBadges(
                    pending: n.pending,
                    hasConflict: n.hasConflict,
                    syncError: n.syncError,
                  ),
                ],
              ),
              if (excerpt.isNotEmpty && n.title.trim().isNotEmpty) ...[
                const SizedBox(height: JkTokens.spacingXs),
                Text(
                  excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(color: c.textSecondary),
                ),
              ],
              const SizedBox(height: JkTokens.spacingSm),
              Wrap(
                spacing: JkTokens.spacingSm,
                runSpacing: JkTokens.spacingXxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _when(n.updatedAt),
                    style: t.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                  if (folder != null)
                    _Meta(icon: Icons.folder_outlined, text: folder),
                  for (final tag in n.tags.take(3))
                    _Meta(icon: Icons.tag, text: tag),
                  if (n.worklogIds.isNotEmpty)
                    _Meta(icon: Icons.link, text: '${n.worklogIds.length} 条日志'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '今天 $time';
    }
    if (t.year == now.year) return '${t.month} 月 ${t.day} 日 $time';
    return '${t.year} 年 ${t.month} 月 ${t.day} 日';
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = context.jkColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: JkTokens.spacingXxs),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
