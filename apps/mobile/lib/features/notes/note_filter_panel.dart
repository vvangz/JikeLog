import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/refs.dart';
import '../../shared/ui/jk_feedback.dart';
import 'note_dialogs.dart';
import 'note_filters.dart';
import 'note_models.dart';
import 'note_repository.dart';

/// 当前的筛选条件。
final noteFilterProvider = NotifierProvider<NoteFilterNotifier, NoteFilter>(
  NoteFilterNotifier.new,
);

class NoteFilterNotifier extends Notifier<NoteFilter> {
  @override
  NoteFilter build() => const AllNotes();

  void select(NoteFilter f) => state = f;
}

/// 筛选面板：全部、收藏、未分类、文件夹树、标签；文件夹与标签可在此管理。
class NoteFilterPanel extends ConsumerWidget {
  const NoteFilterPanel({super.key, this.onSelected});

  /// 选中后调用（窄屏时关闭面板）。
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(noteListProvider).value ?? const <Note>[];
    final tree = ref.watch(noteFoldersProvider).value ?? FolderTree(const []);
    final current = ref.watch(noteFilterProvider);
    final counts = folderCounts(notes, tree);
    final tags = tagCounts(notes);

    Widget item(
      NoteFilter f,
      IconData icon,
      String label,
      int count, {
      Key? key,
      int depth = 0,
      Widget? menu,
    }) => ListTile(
      key: key,
      dense: true,
      selected: current == f,
      contentPadding: EdgeInsets.only(
        left: JkTokens.spacingLg + depth * JkTokens.spacingLg,
        right: menu == null ? JkTokens.spacingLg : 0,
      ),
      leading: Icon(icon, size: 20),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(color: context.jkColors.textSecondary),
          ),
          ?menu,
        ],
      ),
      onTap: () {
        ref.read(noteFilterProvider.notifier).select(f);
        onSelected?.call();
      },
    );

    return ListView(
      key: const Key('note-filter-panel'),
      padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingSm),
      children: [
        item(const AllNotes(), Icons.notes, '全部笔记', notes.length),
        item(
          const FavoriteNotes(),
          Icons.star_border,
          '收藏',
          applyFilter(notes, const FavoriteNotes(), tree).length,
          key: const Key('filter-favorites'),
        ),
        item(
          const UnfiledNotes(),
          Icons.inbox_outlined,
          '未分类',
          applyFilter(notes, const UnfiledNotes(), tree).length,
          key: const Key('filter-unfiled'),
        ),
        _Section(
          title: '文件夹',
          action: IconButton(
            key: const Key('folder-create'),
            tooltip: '新建文件夹',
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            onPressed: () => _createFolder(context, ref, null),
          ),
        ),
        for (final n in tree.flatten())
          item(
            FolderNotes(n.folder.id),
            Icons.folder_outlined,
            n.folder.name,
            counts[n.folder.id] ?? 0,
            key: Key('filter-folder-${n.folder.id}'),
            depth: n.depth,
            menu: _FolderMenu(folder: n.folder, tree: tree),
          ),
        if (tags.isNotEmpty) const _Section(title: '标签'),
        for (final (t, count) in tags)
          item(
            TagNotes(t),
            Icons.tag,
            t,
            count,
            key: Key('filter-tag-$t'),
            menu: _TagMenu(tag: t),
          ),
      ],
    );
  }
}

Future<void> _createFolder(
  BuildContext context,
  WidgetRef ref,
  String? parentId,
) async {
  final name = await showTextInputDialog(
    context,
    title: parentId == null ? '新建文件夹' : '新建子文件夹',
    hint: '文件夹名称',
    maxLength: maxFolderNameLength,
    confirmLabel: '新建',
  );
  if (name != null) {
    await ref
        .read(noteRepositoryProvider)
        .createFolder(name, parentId: parentId);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      JkTokens.spacingLg,
      JkTokens.spacingMd,
      JkTokens.spacingXs,
      0,
    ),
    child: Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: context.jkColors.textSecondary),
        ),
        const Spacer(),
        ?action,
      ],
    ),
  );
}

class _FolderMenu extends ConsumerWidget {
  const _FolderMenu({required this.folder, required this.tree});

  final NoteFolder folder;
  final FolderTree tree;

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repo = ref.read(noteRepositoryProvider);
    switch (action) {
      case 'sub':
        await _createFolder(context, ref, folder.id);
      case 'rename':
        final name = await showTextInputDialog(
          context,
          title: '重命名文件夹',
          initial: folder.name,
          maxLength: maxFolderNameLength,
        );
        if (name != null) await repo.renameFolder(folder.id, name);
      case 'move':
        final choice = await showFolderPicker(
          context,
          tree: tree,
          current: tree.parentOf(folder.id),
          noneLabel: '顶层',
          exclude: tree.subtree(folder.id),
        );
        if (choice != null) {
          await repo.moveFolder(
            folder.id,
            choice is SomeFolder ? choice.id : null,
          );
        }
      case 'delete':
        final ok = await showJkConfirm(
          context,
          title: '删除文件夹',
          message: '"${folder.name}"中的笔记和子文件夹会移到上一级，不会被删除。',
          confirmLabel: '删除',
          destructive: true,
        );
        if (!ok) return;
        if (ref.read(noteFilterProvider) == FolderNotes(folder.id)) {
          ref.read(noteFilterProvider.notifier).select(const AllNotes());
        }
        await repo.deleteFolder(folder.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    key: Key('folder-menu-${folder.id}'),
    tooltip: '文件夹操作',
    icon: const Icon(Icons.more_vert, size: 18),
    onSelected: (v) => _onSelected(context, ref, v),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'sub', child: Text('新建子文件夹')),
      PopupMenuItem(value: 'rename', child: Text('重命名')),
      PopupMenuItem(value: 'move', child: Text('移动到…')),
      PopupMenuItem(value: 'delete', child: Text('删除')),
    ],
  );
}

class _TagMenu extends ConsumerWidget {
  const _TagMenu({required this.tag});

  final String tag;

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repo = ref.read(noteRepositoryProvider);
    final filter = ref.read(noteFilterProvider.notifier);
    final selected = ref.read(noteFilterProvider) == TagNotes(tag);
    if (action == 'rename') {
      final name = await showTextInputDialog(
        context,
        title: '重命名标签',
        initial: tag,
        maxLength: maxTagLength,
      );
      if (name == null) return;
      await repo.renameTag(tag, name);
      if (selected) filter.select(TagNotes(name));
      return;
    }
    final ok = await showJkConfirm(
      context,
      title: '删除标签',
      message: '从所有笔记上移除标签"$tag"，笔记本身不会被删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;
    if (selected) filter.select(const AllNotes());
    await repo.deleteTag(tag);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    key: Key('tag-menu-$tag'),
    tooltip: '标签操作',
    icon: const Icon(Icons.more_vert, size: 18),
    onSelected: (v) => _onSelected(context, ref, v),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'rename', child: Text('重命名')),
      PopupMenuItem(value: 'delete', child: Text('删除')),
    ],
  );
}
