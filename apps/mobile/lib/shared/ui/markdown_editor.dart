import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return Focus(
      onKeyEvent: _onKeyEvent,
      child: TextField(
        key: widget.fieldKey,
        controller: _c,
        focusNode: widget.focusNode,
        inputFormatters: const [MarkdownInputFormatter()],
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
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isAltPressed) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _indent(outdent: keys.isShiftPressed);
      return KeyEventResult.handled;
    }

    final command = keys.isControlPressed || keys.isMetaPressed;
    if (!command) return KeyEventResult.ignored;
    final heading = switch (event.logicalKey) {
      LogicalKeyboardKey.digit1 => 1,
      LogicalKeyboardKey.digit2 => 2,
      LogicalKeyboardKey.digit3 => 3,
      LogicalKeyboardKey.digit4 => 4,
      LogicalKeyboardKey.digit5 => 5,
      LogicalKeyboardKey.digit6 => 6,
      _ => 0,
    };
    if (heading > 0 && !keys.isShiftPressed) {
      _linePrefix('${List.filled(heading, '#').join()} ');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyB) {
      _wrap('**', '**', '加粗文字');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyI) {
      _wrap('*', '*', '斜体文字');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyX && keys.isShiftPressed) {
      _wrap('~~', '~~', '删除线文字');
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.digit7) {
      _linePrefix('1. ');
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.digit8) {
      _linePrefix('- ');
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.digit9) {
      _linePrefix('- [ ] ');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _indent({required bool outdent}) {
    final selection = _c.selection;
    if (!selection.isValid) return;
    final text = _c.text;
    final pos = selection.start;
    final lineStart = text.lastIndexOf('\n', pos == 0 ? 0 : pos - 1) + 1;
    if (outdent) {
      final remove = text.startsWith('\t', lineStart)
          ? 1
          : text.startsWith('  ', lineStart)
          ? 2
          : text.startsWith(' ', lineStart)
          ? 1
          : 0;
      if (remove == 0) return;
      _c.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineStart + remove, ''),
        selection: TextSelection.collapsed(
          offset: (pos - remove).clamp(lineStart, text.length - remove),
        ),
      );
      return;
    }
    _c.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart, '  '),
      selection: TextSelection.collapsed(offset: pos + 2),
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

/// Markdown 输入规则：回车续接列表，空列表项回车退出列表。
///
/// 只处理单字符的用户输入，不改写粘贴内容或正在进行的输入法组合文本。
class MarkdownInputFormatter extends TextInputFormatter {
  const MarkdownInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final insertion = _singleCharacterInsertion(oldValue, newValue);
    if (insertion == null || newValue.composing.isValid) return newValue;
    if (insertion.character != '\n') return newValue;

    final lineStart =
        oldValue.text.lastIndexOf(
          '\n',
          insertion.offset == 0 ? 0 : insertion.offset - 1,
        ) +
        1;
    final line = oldValue.text.substring(lineStart, insertion.offset);
    final ordered = RegExp(r'^([ \t]*)(\d+)\.\s+(.*)$').firstMatch(line);
    final task = RegExp(r'^([ \t]*)-[ \t]+\[[ xX]\][ \t]+(.*)$')
        .firstMatch(line);
    final unordered = RegExp(r'^([ \t]*)([-+*])[ \t]+(.*)$').firstMatch(line);
    final match = ordered ?? task ?? unordered;
    if (match == null) return newValue;

    final indent = match.group(1)!;
    final body = ordered != null
        ? ordered.group(3)!
        : task != null
        ? task.group(2)!
        : unordered!.group(3)!;
    final marker = ordered != null
        ? '${int.parse(ordered.group(2)!) + 1}. '
        : task != null
        ? '- [ ] '
        : '${unordered!.group(2)!} ';

    if (body.trim().isEmpty) {
      final text = newValue.text.replaceRange(
        lineStart,
        insertion.offset + 1,
        '',
      );
      return newValue.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: lineStart),
        composing: TextRange.empty,
      );
    }

    final continuation = '$indent$marker';
    final text = newValue.text.replaceRange(
      insertion.offset + 1,
      insertion.offset + 1,
      continuation,
    );
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(
        offset: insertion.offset + 1 + continuation.length,
      ),
      composing: TextRange.empty,
    );
  }
}

class _MarkdownInsertion {
  const _MarkdownInsertion(this.offset, this.character);

  final int offset;
  final String character;
}

_MarkdownInsertion? _singleCharacterInsertion(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  if (!oldValue.selection.isValid ||
      !oldValue.selection.isCollapsed ||
      !newValue.selection.isValid ||
      !newValue.selection.isCollapsed ||
      newValue.text.length != oldValue.text.length + 1) {
    return null;
  }
  final offset = newValue.selection.baseOffset - 1;
  if (offset < 0 || offset >= newValue.text.length) return null;
  if (newValue.text.substring(0, offset) !=
          oldValue.text.substring(0, offset) ||
      newValue.text.substring(offset + 1) != oldValue.text.substring(offset)) {
    return null;
  }
  return _MarkdownInsertion(offset, newValue.text[offset]);
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
