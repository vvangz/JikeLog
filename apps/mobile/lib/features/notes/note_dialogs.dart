import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../worklog/worklog_repository.dart';
import 'note_models.dart';

/// 输入一行文字（新建文件夹、重命名、添加标签）。取消时返回 null。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  required int maxLength,
  String confirmLabel = '确定',
  List<String> suggestions = const [],
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextInputDialog(
    title: title,
    initial: initial,
    hint: hint,
    maxLength: maxLength,
    confirmLabel: confirmLabel,
    suggestions: suggestions,
  ),
);

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.maxLength,
    required this.confirmLabel,
    required this.suggestions,
  });

  final String title;
  final String initial;
  final String hint;
  final int maxLength;
  final String confirmLabel;
  final List<String> suggestions;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _c = TextEditingController(text: widget.initial)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final v = (value ?? _c.text).trim();
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final q = _c.text.trim();
    final matches = widget.suggestions
        .where((s) => s != q && (q.isEmpty || s.contains(q)))
        .take(8)
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('text-input'),
            controller: _c,
            autofocus: true,
            maxLength: widget.maxLength,
            inputFormatters: [FilteringTextInputFormatter.deny('\n')],
            decoration: InputDecoration(hintText: widget.hint),
            onSubmitted: _submit,
          ),
          if (matches.isNotEmpty)
            Wrap(
              spacing: JkTokens.spacingXs,
              children: [
                for (final m in matches)
                  ActionChip(label: Text(m), onPressed: () => _submit(m)),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('text-input-ok'),
          onPressed: q.isEmpty ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 文件夹选择的结果：选中某个文件夹或"未分类"。
sealed class FolderChoice {
  const FolderChoice();
}

final class NoFolder extends FolderChoice {
  const NoFolder();
}

final class SomeFolder extends FolderChoice {
  const SomeFolder(this.id);

  final String id;
}

/// 选择文件夹。[exclude] 中的文件夹不可选（移动文件夹时不能移到自己的下级）。
Future<FolderChoice?> showFolderPicker(
  BuildContext context, {
  required FolderTree tree,
  required String? current,
  String title = '移动到',
  String noneLabel = '未分类',
  Set<String> exclude = const {},
}) => showDialog<FolderChoice>(
  context: context,
  builder: (context) {
    final c = context.jkColors;
    return SimpleDialog(
      title: Text(title),
      children: [
        SimpleDialogOption(
          key: const Key('folder-pick-none'),
          onPressed: () => Navigator.of(context).pop(const NoFolder()),
          child: Row(
            children: [
              const Icon(Icons.inbox_outlined, size: 20),
              const SizedBox(width: JkTokens.spacingSm),
              Expanded(child: Text(noneLabel)),
              if (current == null)
                Icon(Icons.check, size: 18, color: c.primary),
            ],
          ),
        ),
        for (final n in tree.flatten())
          SimpleDialogOption(
            key: Key('folder-pick-${n.folder.id}'),
            onPressed: exclude.contains(n.folder.id)
                ? null
                : () => Navigator.of(context).pop(SomeFolder(n.folder.id)),
            child: Padding(
              padding: EdgeInsets.only(left: n.depth * JkTokens.spacingLg),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 20,
                    color: exclude.contains(n.folder.id)
                        ? c.textDisabled
                        : null,
                  ),
                  const SizedBox(width: JkTokens.spacingSm),
                  Expanded(
                    child: Text(
                      n.folder.name,
                      style: TextStyle(
                        color: exclude.contains(n.folder.id)
                            ? c.textDisabled
                            : null,
                      ),
                    ),
                  ),
                  if (current == n.folder.id)
                    Icon(Icons.check, size: 18, color: c.primary),
                ],
              ),
            ),
          ),
      ],
    );
  },
);

/// 选择要关联的工作日志（最近的在前），可按地点或内容筛选。
Future<String?> showWorklogPicker(
  BuildContext context, {
  required List<Worklog> worklogs,
  required Set<String> exclude,
}) => showDialog<String>(
  context: context,
  builder: (_) => _WorklogPicker(worklogs: worklogs, exclude: exclude),
);

class _WorklogPicker extends StatefulWidget {
  const _WorklogPicker({required this.worklogs, required this.exclude});

  final List<Worklog> worklogs;
  final Set<String> exclude;

  @override
  State<_WorklogPicker> createState() => _WorklogPickerState();
}

class _WorklogPickerState extends State<_WorklogPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final items = widget.worklogs
        .where(
          (w) =>
              !widget.exclude.contains(w.id) &&
              (_q.isEmpty ||
                  w.location.contains(_q) ||
                  w.content.contains(_q) ||
                  formatDate(w.date).contains(_q)),
        )
        .take(100)
        .toList();
    return AlertDialog(
      title: const Text('关联工作日志'),
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
                key: const Key('worklog-picker-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '按日期、地点或内容筛选',
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('没有可关联的工作日志'))
                  : ListView(
                      children: [
                        for (final w in items)
                          ListTile(
                            key: Key('worklog-pick-${w.id}'),
                            leading: const Icon(Icons.event_note_outlined),
                            title: Text(worklogTitle(w)),
                            subtitle: Text(
                              w.content.replaceAll('\n', ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.of(context).pop(w.id),
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

/// 工作日志的一行标题：日期与地点。
String worklogTitle(Worklog w) {
  final d = w.date;
  return '${d.year} 年 ${d.month} 月 ${d.day} 日'
      '${w.location.isEmpty ? '' : ' · ${w.location}'}';
}
