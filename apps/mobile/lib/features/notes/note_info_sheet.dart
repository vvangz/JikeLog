import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/refs.dart';
import '../attachments/attachment_section.dart';
import '../worklog/worklog_repository.dart';
import 'note_dialogs.dart';
import 'note_filters.dart';
import 'note_models.dart';
import 'note_repository.dart';

/// 打开笔记信息：文件夹、标签、关联的工作日志、附件。
Future<void> showNoteInfo(BuildContext context, String noteId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => NoteInfoPanel(noteId: noteId, scroll: scroll),
      ),
    );

class NoteInfoPanel extends ConsumerWidget {
  const NoteInfoPanel({super.key, required this.noteId, this.scroll});

  final String noteId;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteProvider(noteId)).value;
    if (note == null) return const SizedBox.shrink();
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        0,
        JkTokens.spacingLg,
        JkTokens.spacingXl,
      ),
      children: [
        _FolderRow(note: note),
        const Divider(height: JkTokens.spacingXl),
        _TagsRow(note: note),
        const Divider(height: JkTokens.spacingXl),
        _LinkedWorklogs(note: note),
        const Divider(height: JkTokens.spacingXl),
        AttachmentSection(ownerEntity: 'note', ownerId: note.id),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(text, style: Theme.of(context).textTheme.titleSmall),
      const Spacer(),
      ?action,
    ],
  );
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(noteFoldersProvider).value ?? FolderTree(const []);
    final folder = note.folderId;
    final exists = folder != null && tree.byId.containsKey(folder);
    return ListTile(
      key: const Key('note-info-folder'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(exists ? Icons.folder_outlined : Icons.inbox_outlined),
      title: const Text('文件夹'),
      subtitle: Text(exists ? tree.path(folder) : '未分类'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final choice = await showFolderPicker(
          context,
          tree: tree,
          current: exists ? folder : null,
        );
        final repo = ref.read(noteRepositoryProvider);
        switch (choice) {
          case NoFolder():
            await repo.moveTo(note.id, null);
          case SomeFolder(:final id):
            await repo.moveTo(note.id, id);
          case null:
            break;
        }
      },
    );
  }
}

class _TagsRow extends ConsumerWidget {
  const _TagsRow({required this.note});

  final Note note;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // 笔记列表可能尚未被监听（Riverpod 暂停未监听的 provider），直接从本机库读取
    final notes = await ref.read(noteRepositoryProvider).watchNotes().first;
    if (!context.mounted) return;
    final all = [
      for (final (t, _) in tagCounts(notes))
        if (!note.tags.contains(t)) t,
    ];
    final tag = await showTextInputDialog(
      context,
      title: '添加标签',
      hint: '如：周报、学习',
      maxLength: maxTagLength,
      confirmLabel: '添加',
      suggestions: all,
    );
    if (tag != null) {
      await ref.read(noteRepositoryProvider).addTag(note.id, tag);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Heading(
        '标签',
        action: TextButton.icon(
          key: const Key('note-tag-add'),
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加'),
        ),
      ),
      if (note.tags.isEmpty)
        Text('还没有标签', style: TextStyle(color: context.jkColors.textSecondary))
      else
        Wrap(
          spacing: JkTokens.spacingXs,
          runSpacing: JkTokens.spacingXs,
          children: [
            for (final t in note.tags)
              InputChip(
                label: Text('#$t'),
                onDeleted: () =>
                    ref.read(noteRepositoryProvider).removeTag(note.id, t),
                deleteButtonTooltipMessage: '移除标签',
              ),
          ],
        ),
    ],
  );
}

class _LinkedWorklogs extends ConsumerWidget {
  const _LinkedWorklogs({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(worklogListProvider).value ?? const <Worklog>[];
    final byId = {for (final w in all) w.id: w};
    // 已在其他设备上删除的日志不显示
    final linked = [for (final id in note.worklogIds) ?byId[id]];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          '关联的工作日志',
          action: TextButton.icon(
            key: const Key('note-link-worklog'),
            onPressed: () async {
              final id = await showWorklogPicker(
                context,
                worklogs: all,
                exclude: note.worklogIds.toSet(),
              );
              if (id != null) {
                await ref.read(noteRepositoryProvider).link(note.id, id);
              }
            },
            icon: const Icon(Icons.add_link, size: 18),
            label: const Text('关联'),
          ),
        ),
        if (linked.isEmpty)
          Text(
            '可以把笔记关联到工作日志，在日志中也能看到这篇笔记',
            style: TextStyle(color: context.jkColors.textSecondary),
          ),
        for (final w in linked)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_note_outlined),
            title: Text(worklogTitle(w)),
            onTap: () => context.push('/worklog/${w.id}'),
            trailing: IconButton(
              tooltip: '取消关联',
              icon: const Icon(Icons.link_off),
              onPressed: () =>
                  ref.read(noteRepositoryProvider).unlink(note.id, w.id),
            ),
          ),
      ],
    );
  }
}
