import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/jk_tokens.g.dart';
import '../../../shared/ui/jk_feedback.dart';
import 'rich_editor_controller.dart';

/// 富文本编辑器的工具栏：按钮随光标处的格式高亮；在表格中显示表格操作。
class RichToolbar extends StatelessWidget {
  const RichToolbar({
    super.key,
    required this.controller,
    required this.onInsertImage,
    required this.onOpenLink,
  });

  final RichEditorController controller;
  final VoidCallback onInsertImage;

  /// 用系统浏览器打开光标所在的链接。
  final void Function(String href) onOpenLink;

  Future<void> _editLink(BuildContext context, FormatState s) async {
    final href = await showDialog<String>(
      context: context,
      builder: (_) => _LinkDialog(initial: s.link ?? 'https://'),
    );
    if (href == null) return;
    if (href.trim().isEmpty) {
      await controller.run(RichCommand.unsetLink);
      return;
    }
    if (!await controller.setLink(href) && context.mounted) {
      showJkToast(context, '只支持 http、https、mailto、tel 链接');
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.format,
    builder: (context, s, _) {
      Widget tool(
        IconData icon,
        String label,
        RichCommand? command, {
        bool active = false,
        bool enabled = true,
        VoidCallback? onPressed,
      }) => IconButton(
        tooltip: label,
        isSelected: active,
        icon: Icon(icon, size: 20),
        selectedIcon: Icon(icon, size: 20, color: context.jkColors.primary),
        onPressed: !enabled
            ? null
            : onPressed ?? () => controller.run(command!),
      );
      return Material(
        key: const Key('rich-toolbar'),
        color: context.jkColors.surfaceVariant,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                tool(Icons.undo, '撤销', RichCommand.undo, enabled: s.canUndo),
                tool(Icons.redo, '重做', RichCommand.redo, enabled: s.canRedo),
                _HeadingMenu(controller: controller, level: s.heading),
                tool(Icons.format_bold, '加粗', RichCommand.bold, active: s.bold),
                tool(
                  Icons.format_italic,
                  '斜体',
                  RichCommand.italic,
                  active: s.italic,
                ),
                tool(
                  Icons.format_strikethrough,
                  '删除线',
                  RichCommand.strike,
                  active: s.strike,
                ),
                tool(Icons.code, '行内代码', RichCommand.code, active: s.code),
                tool(
                  Icons.check_box_outlined,
                  '待办',
                  RichCommand.taskList,
                  active: s.taskList,
                ),
                tool(
                  Icons.format_list_bulleted,
                  '无序列表',
                  RichCommand.bulletList,
                  active: s.bulletList,
                ),
                tool(
                  Icons.format_list_numbered,
                  '有序列表',
                  RichCommand.orderedList,
                  active: s.orderedList,
                ),
                tool(
                  Icons.format_quote,
                  '引用',
                  RichCommand.blockquote,
                  active: s.blockquote,
                ),
                tool(
                  Icons.data_object,
                  '代码块',
                  RichCommand.codeBlock,
                  active: s.codeBlock,
                ),
                if (s.inTable)
                  _TableMenu(controller: controller)
                else
                  tool(
                    Icons.table_chart_outlined,
                    '插入表格',
                    RichCommand.insertTable,
                  ),
                tool(
                  Icons.image_outlined,
                  '插入图片',
                  null,
                  onPressed: onInsertImage,
                ),
                tool(
                  Icons.link,
                  s.link == null ? '链接' : '编辑链接',
                  null,
                  active: s.link != null,
                  onPressed: () => _editLink(context, s),
                ),
                if (s.link != null)
                  tool(
                    Icons.open_in_new,
                    '打开链接',
                    null,
                    onPressed: () => onOpenLink(s.link!),
                  ),
                tool(Icons.horizontal_rule, '分隔线', RichCommand.horizontalRule),
                const SizedBox(width: JkTokens.spacingSm),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _HeadingMenu extends StatelessWidget {
  const _HeadingMenu({required this.controller, required this.level});

  final RichEditorController controller;
  final int level;

  @override
  Widget build(BuildContext context) => PopupMenuButton<RichCommand>(
    tooltip: '标题',
    icon: Icon(
      Icons.title,
      size: 20,
      color: level > 0 ? context.jkColors.primary : null,
    ),
    onSelected: controller.run,
    itemBuilder: (_) => [
      for (final (cmd, label, l) in const [
        (RichCommand.heading1, '一级标题', 1),
        (RichCommand.heading2, '二级标题', 2),
        (RichCommand.heading3, '三级标题', 3),
        (RichCommand.paragraph, '正文', 0),
      ])
        CheckedPopupMenuItem(
          value: cmd,
          checked: level == l,
          child: Text(label),
        ),
    ],
  );
}

class _TableMenu extends StatelessWidget {
  const _TableMenu({required this.controller});

  final RichEditorController controller;

  @override
  Widget build(BuildContext context) => PopupMenuButton<RichCommand>(
    key: const Key('rich-table-menu'),
    tooltip: '表格操作',
    icon: Icon(Icons.table_chart, size: 20, color: context.jkColors.primary),
    onSelected: controller.run,
    itemBuilder: (_) => const [
      PopupMenuItem(value: RichCommand.addRowAfter, child: Text('在下方插入行')),
      PopupMenuItem(value: RichCommand.addColumnAfter, child: Text('在右侧插入列')),
      PopupMenuItem(value: RichCommand.deleteRow, child: Text('删除当前行')),
      PopupMenuItem(value: RichCommand.deleteColumn, child: Text('删除当前列')),
      PopupMenuItem(value: RichCommand.deleteTable, child: Text('删除表格')),
    ],
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initial});

  final String initial;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('链接'),
    content: TextField(
      key: const Key('rich-link-input'),
      controller: _c,
      autofocus: true,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        hintText: 'https://',
        helperText: '清空后确定即可移除链接',
      ),
      onSubmitted: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      TextButton(
        key: const Key('rich-link-ok'),
        onPressed: () => Navigator.of(context).pop(_c.text),
        child: const Text('确定'),
      ),
    ],
  );
}
