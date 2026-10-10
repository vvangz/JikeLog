import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_feedback.dart';
import 'note_models.dart';
import 'note_repository.dart';

/// 工作日志中的"关联的笔记"：笔记上记录了关联，这里通过本地索引反查（ADR-007）。
class LinkedNotesSection extends ConsumerWidget {
  const LinkedNotesSection({super.key, required this.worklogId});

  final String worklogId;

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final linked = {
      for (final n
          in ref.read(linkedNotesProvider(worklogId)).value ?? <Note>[])
        n.id,
    };
    // 笔记列表可能尚未被监听（Riverpod 暂停未监听的 provider），直接从本机库读取
    final all = await ref.read(noteRepositoryProvider).watchNotes().first;
    if (!context.mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _NotePicker(
        notes: [
          for (final n in all)
            if (!linked.contains(n.id)) n,
        ],
      ),
    );
    if (id == null) return;
    final ok = await ref.read(noteRepositoryProvider).link(id, worklogId);
    if (!ok && context.mounted) {
      showJkToast(context, '这篇笔记关联的工作日志数量已达上限', kind: JkToastKind.error);
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final id = await ref
        .read(noteRepositoryProvider)
        .create(format: NoteFormat.rich, worklogId: worklogId);
    if (context.mounted) await context.push('/notes/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(linkedNotesProvider(worklogId)).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('关联的笔记', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              key: const Key('worklog-note-create'),
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('新建'),
            ),
            TextButton.icon(
              key: const Key('worklog-note-link'),
              onPressed: () => _link(context, ref),
              icon: const Icon(Icons.add_link, size: 18),
              label: const Text('关联'),
            ),
          ],
        ),
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingSm),
            child: Text(
              '可以关联会议纪要、方案等笔记',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.jkColors.textSecondary),
            ),
          ),
        for (final n in notes)
          ListTile(
            key: Key('linked-note-${n.id}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.description_outlined,
              color: context.jkColors.primary,
            ),
            title: Text(
              n.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push('/notes/${n.id}'),
            trailing: IconButton(
              tooltip: '取消关联',
              icon: const Icon(Icons.link_off),
              onPressed: () =>
                  ref.read(noteRepositoryProvider).unlink(n.id, worklogId),
            ),
          ),
      ],
    );
  }
}

class _NotePicker extends StatefulWidget {
  const _NotePicker({required this.notes});

  final List<Note> notes;

  @override
  State<_NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends State<_NotePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final items = widget.notes
        .where(
          (n) =>
              _q.isEmpty ||
              n.displayTitle.contains(_q) ||
              n.body.contains(_q) ||
              n.tags.any((t) => t.contains(_q)),
        )
        .take(100)
        .toList();
    return AlertDialog(
      title: const Text('关联笔记'),
      contentPadding: const EdgeInsets.symmetric(vertical: JkTokens.spacingSm),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JkTokens.spacingLg,
              ),
              child: TextField(
                key: const Key('note-picker-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '按标题、内容或标签筛选',
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('没有可关联的笔记'))
                  : ListView(
                      children: [
                        for (final n in items)
                          ListTile(
                            key: Key('note-pick-${n.id}'),
                            leading: const Icon(Icons.description_outlined),
                            title: Text(
                              n.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: n.tags.isEmpty
                                ? null
                                : Text(n.tags.map((t) => '#$t').join(' ')),
                            onTap: () => Navigator.of(context).pop(n.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
