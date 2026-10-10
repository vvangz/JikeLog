import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';

/// Markdown 编辑器：工具栏 + 正文输入，可切换到预览。
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.hint = '记录今天的工作内容，支持 Markdown',
    this.fieldKey = const Key('worklog-content'),
    this.imageBuilder,
    this.extraTools = const [],
    this.expand = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final Key fieldKey;

  /// 预览中图片的显示方式（例如把 attachment: 引用显示为附件图片）。
  final MarkdownImageBuilder? imageBuilder;

  /// 追加在工具栏末尾的按钮（预览时禁用）。
  final List<Widget> extraTools;

  /// 占满父组件的高度（放在 Expanded 中使用），否则随内容增高。
  final bool expand;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  static const _table = '| 事项 | 进度 |\n| --- | --- |\n|  |  |';
  bool _preview = false;

  TextEditingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(MarkdownEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  /// 预览时内容被替换（例如合并了其他设备的修改）也要刷新预览。
  void _onText() {
    if (_preview && mounted) setState(() {});
  }

  /// 用 [left]/[right] 包裹选中文本；没有选中时插入占位文字并选中。
  void _wrap(String left, String right, String placeholder) {
    final sel = _c.selection;
    final text = _c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final inner = start == end ? placeholder : text.substring(start, end);
    _c.value = TextEditingValue(
      text: text.replaceRange(start, end, '$left$inner$right'),
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: start + left.length + inner.length,
      ),
    );
  }

  /// 在光标所在行行首加上 [prefix]（已存在则去掉，便于切换）。
  void _linePrefix(String prefix) {
    final text = _c.text;
    final pos = _c.selection.isValid ? _c.selection.start : text.length;
    final lineStart = text.lastIndexOf('\n', pos == 0 ? 0 : pos - 1) + 1;
    final has = text.startsWith(prefix, lineStart);
    final next = has
        ? text.replaceRange(lineStart, lineStart + prefix.length, '')
        : text.replaceRange(lineStart, lineStart, prefix);
    final delta = has ? -prefix.length : prefix.length;
    _c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: (pos + delta).clamp(0, next.length),
      ),
    );
  }

  void _insertBlock(String block, int cursorOffset) =>
      insertMarkdownBlock(_c, block, cursorOffset: cursorOffset);

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(JkTokens.radiusMd),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tool(Icons.title, '标题', () => _linePrefix('## '), edit: true),
                _tool(
                  Icons.format_bold,
                  '加粗',
                  () => _wrap('**', '**', '加粗文字'),
                  edit: true,
                ),
                _tool(
                  Icons.format_list_bulleted,
                  '列表',
                  () => _linePrefix('- '),
                  edit: true,
                ),
                _tool(
                  Icons.check_box_outlined,
                  '待办',
                  () => _linePrefix('- [ ] '),
                  edit: true,
                ),
                _tool(
                  Icons.code,
                  '代码块',
                  () => _insertBlock('```\n\n```', 4),
                  edit: true,
                ),
                _tool(
                  Icons.table_chart_outlined,
                  '表格',
                  () => _insertBlock(_table, _table.lastIndexOf('|  |') + 2),
                  edit: true,
                ),
                if (!_preview) ...widget.extraTools,
                const SizedBox(width: JkTokens.spacingSm),
                _tool(
                  _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                  _preview ? '编辑' : '预览',
                  () => setState(() => _preview = !_preview),
                  key: const Key('markdown-preview-toggle'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: JkTokens.spacingSm),
        if (widget.expand) Expanded(child: _body(c)) else _body(c),
      ],
    );
  }

  Widget _body(JkColorTokens c) {
    if (_preview) {
      final preview = Container(
        key: const Key('markdown-preview'),
        constraints: const BoxConstraints(minHeight: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(JkTokens.spacingMd),
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        ),
        child: _c.text.trim().isEmpty
            ? Text('（暂无内容）', style: TextStyle(color: c.textDisabled))
            : MarkdownBody(
                data: _c.text,
                selectable: true,
                imageBuilder: widget.imageBuilder,
              ),
      );
      return widget.expand ? SingleChildScrollView(child: preview) : preview;
    }
    return TextField(
      key: widget.fieldKey,
      controller: _c,
      focusNode: widget.focusNode,
      minLines: widget.expand ? null : 10,
      maxLines: null,
      expands: widget.expand,
      textAlignVertical: TextAlignVertical.top,
      maxLength: 100000,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        hintText: widget.hint,
        counterText: '',
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _tool(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool edit = false,
    Key? key,
  }) => IconButton(
    key: key,
    tooltip: label,
    icon: Icon(icon, size: 20),
    // 预览时禁用编辑类按钮
    onPressed: edit && _preview ? null : onPressed,
  );
}

/// 在光标处插入一段独立的块（前后补空行）。光标移到块内 [cursorOffset] 处，默认在块之后。
void insertMarkdownBlock(
  TextEditingController c,
  String block, {
  int? cursorOffset,
}) {
  final text = c.text;
  final pos = c.selection.isValid ? c.selection.start : text.length;
  final before = pos > 0 && text[pos - 1] != '\n' ? '\n\n' : '';
  final insert = '$before$block\n';
  c.value = TextEditingValue(
    text: text.replaceRange(pos, pos, insert),
    selection: TextSelection.collapsed(
      offset:
          pos + before.length + (cursorOffset ?? insert.length - before.length),
    ),
  );
}
