import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import 'markdown_input_formatter.dart';

export 'markdown_input_formatter.dart';
export 'markdown_text_controller.dart';

enum _LineFormat { unordered, ordered, task, quote }

/// Markdown 编辑器：工具栏 + 正文输入 + 快捷键 + 交互式预览。
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.hint = '记录今天的工作内容，支持 Markdown',
    this.fieldKey = const Key('worklog-content'),
    this.imageBuilder,
    this.onTapLink,
    this.extraTools = const [],
    this.expand = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final Key fieldKey;

  /// 预览中图片的显示方式（例如把 attachment: 引用显示为附件图片）。
  final MarkdownImageBuilder? imageBuilder;

  /// 预览中点击链接的回调。
  final MarkdownTapLinkCallback? onTapLink;

  /// 固定在工具栏右侧、预览按钮旁的扩展按钮（预览时隐藏）。
  final List<Widget> extraTools;

  /// 占满父组件的高度（放在 Expanded 中使用），否则随内容增高。
  final bool expand;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  static const _table = '| 事项 | 进度 |\n| --- | --- |\n|  |  |';
  static final _headingPrefixRe = RegExp(r'^([ \t]*)(#{1,6})[ \t]+');
  static final _taskPrefixRe = RegExp(r'^([ \t]*)[-+*][ \t]+\[[ xX]\][ \t]+');
  static final _orderedPrefixRe = RegExp(r'^([ \t]*)\d+\.[ \t]+');
  static final _unorderedPrefixRe = RegExp(r'^([ \t]*)[-+*][ \t]+');
  static final _quotePrefixRe = RegExp(r'^([ \t]*)>[ \t]?');

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

  /// 用 [left]/[right] 包裹选中文本；已被相同标记包裹时取消包裹；没有选中时插入占位文字并选中。
  void _wrap(String left, String right, String placeholder) {
    final sel = _c.selection;
    final text = _c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;

    // 选区外侧已被相同标记包裹：取消包裹
    if (start != end &&
        start >= left.length &&
        end + right.length <= text.length &&
        text.substring(start - left.length, start) == left &&
        text.substring(end, end + right.length) == right) {
      final inner = text.substring(start, end);
      _c.value = TextEditingValue(
        text: text.replaceRange(start - left.length, end + right.length, inner),
        selection: TextSelection(
          baseOffset: start - left.length,
          extentOffset: start - left.length + inner.length,
        ),
      );
      return;
    }

    // 选区自身包含首尾相同标记：取消包裹
    if (start != end) {
      final selected = text.substring(start, end);
      if (selected.length > left.length + right.length &&
          selected.startsWith(left) &&
          selected.endsWith(right)) {
        final inner = selected.substring(
          left.length,
          selected.length - right.length,
        );
        _c.value = TextEditingValue(
          text: text.replaceRange(start, end, inner),
          selection: TextSelection(
            baseOffset: start,
            extentOffset: start + inner.length,
          ),
        );
        return;
      }
    }

    final inner = start == end ? placeholder : text.substring(start, end);
    _c.value = TextEditingValue(
      text: text.replaceRange(start, end, '$left$inner$right'),
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: start + left.length + inner.length,
      ),
    );
  }

  /// 插入链接：选中 URL 时自动填入地址栏，选中文字时高亮地址占位符便于直接粘贴。
  void _insertLink() {
    final sel = _c.selection;
    final text = _c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final selected = start == end ? '' : text.substring(start, end);

    if (selected.startsWith('http://') || selected.startsWith('https://')) {
      const label = '链接文字';
      final inserted = '[$label]($selected)';
      _c.value = TextEditingValue(
        text: text.replaceRange(start, end, inserted),
        selection: TextSelection(
          baseOffset: start + 1,
          extentOffset: start + 1 + label.length,
        ),
      );
      return;
    }

    if (selected.isNotEmpty) {
      const url = 'https://';
      final inserted = '[$selected]($url)';
      final urlStart = start + selected.length + 3;
      _c.value = TextEditingValue(
        text: text.replaceRange(start, end, inserted),
        selection: TextSelection(
          baseOffset: urlStart,
          extentOffset: urlStart + url.length,
        ),
      );
      return;
    }

    const label = '链接文字';
    const inserted = '[$label](https://)';
    _c.value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection(
        baseOffset: start + 1,
        extentOffset: start + 1 + label.length,
      ),
    );
  }

  /// 切换当前行（或多行选区）的标题级别；[level] 为 0 时清除标题，与当前级别相同时取消标题。
  void _setHeading(int level) {
    _transformSelectedLines((lines) {
      final hashes = level > 0 ? '${List.filled(level, '#').join()} ' : '';
      final allSameLevel =
          level > 0 &&
          lines.any((l) => l.trim().isNotEmpty) &&
          lines.every((l) {
            if (l.trim().isEmpty) return true;
            final m = _headingPrefixRe.firstMatch(l);
            return m != null && m.group(2)!.length == level;
          });

      return [
        for (final line in lines)
          () {
            if (line.trim().isEmpty && lines.length > 1) return line;
            final m = _headingPrefixRe.firstMatch(line);
            final indent = m?.group(1) ?? '';
            final body = m != null ? line.substring(m.end) : line;
            if (level == 0 || allSameLevel) return '$indent$body';
            return '$indent$hashes$body';
          }(),
      ];
    });
  }

  /// 切换当前行（或多行选区）的列表 / 引用前缀；在有序、无序、待办之间切换时直接替换原前缀。
  void _toggleLineFormat(_LineFormat format) {
    _transformSelectedLines((lines) {
      final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
      final targets = nonEmpty.isEmpty ? lines : nonEmpty;

      if (format == _LineFormat.quote) {
        final allQuoted = targets.every(_quotePrefixRe.hasMatch);
        return [
          for (final line in lines)
            if (line.trim().isEmpty && lines.length > 1)
              line
            else if (allQuoted)
              line.replaceFirstMapped(_quotePrefixRe, (m) => m.group(1)!)
            else
              '> $line',
        ];
      }

      bool matchesTarget(String line) => switch (format) {
        _LineFormat.task => _taskPrefixRe.hasMatch(line),
        _LineFormat.ordered => _orderedPrefixRe.hasMatch(line),
        _LineFormat.unordered =>
          _unorderedPrefixRe.hasMatch(line) && !_taskPrefixRe.hasMatch(line),
        _LineFormat.quote => false,
      };

      final allMatch = targets.every(matchesTarget);
      var order = 1;
      return [
        for (final line in lines)
          () {
            if (line.trim().isEmpty && lines.length > 1) return line;
            final existing =
                _taskPrefixRe.firstMatch(line) ??
                _orderedPrefixRe.firstMatch(line) ??
                _unorderedPrefixRe.firstMatch(line);
            final indent =
                existing?.group(1) ??
                RegExp(r'^([ \t]*)').firstMatch(line)!.group(1)!;
            final body = existing != null
                ? line.substring(existing.end)
                : line.substring(indent.length);
            if (allMatch) return '$indent$body';
            final prefix = switch (format) {
              _LineFormat.unordered => '- ',
              _LineFormat.ordered => '${order++}. ',
              _LineFormat.task => '- [ ] ',
              _LineFormat.quote => '> ',
            };
            return '$indent$prefix$body';
          }(),
      ];
    });
  }

  /// 对选区覆盖的所有整行执行变换，保持光标或选区与内容同步。
  void _transformSelectedLines(List<String> Function(List<String>) transform) {
    final text = _c.text;
    final sel = _c.selection;
    final rawStart = sel.isValid ? sel.start : text.length;
    final rawEnd = sel.isValid ? sel.end : text.length;
    final collapsed = rawStart == rawEnd;

    final blockStart =
        text.lastIndexOf('\n', rawStart == 0 ? 0 : rawStart - 1) + 1;
    // 若选区终点刚好停在下一行行首（且非折叠选区），不含那一行
    final effectiveEnd =
        !collapsed && rawEnd > rawStart && text[rawEnd - 1] == '\n'
        ? rawEnd - 1
        : rawEnd;
    final nextNl = text.indexOf('\n', effectiveEnd);
    final blockEnd = nextNl == -1 ? text.length : nextNl;

    final block = text.substring(blockStart, blockEnd);
    final oldLines = block.split('\n');
    final newLines = transform(oldLines);
    final replacement = newLines.join('\n');
    if (replacement == block) return;

    final nextText = text.replaceRange(blockStart, blockEnd, replacement);
    final TextSelection nextSelection;
    if (collapsed) {
      final delta = replacement.length - block.length;
      nextSelection = TextSelection.collapsed(
        offset: (rawStart + delta).clamp(
          blockStart,
          blockStart + replacement.length,
        ),
      );
    } else {
      nextSelection = TextSelection(
        baseOffset: blockStart,
        extentOffset: blockStart + replacement.length,
      );
    }
    _c.value = TextEditingValue(text: nextText, selection: nextSelection);
  }

  void _insertBlock(String block, int cursorOffset) =>
      insertMarkdownBlock(_c, block, cursorOffset: cursorOffset);

  void _togglePreview() => setState(() => _preview = !_preview);

  void _toggleTaskInPreview(int index) {
    final next = toggleMarkdownTaskAt(_c.text, index);
    if (next == _c.text) return;
    _c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: _c.selection.isValid
            ? _c.selection.baseOffset.clamp(0, next.length)
            : next.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Focus(
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: c.surfaceVariant,
            borderRadius: BorderRadius.circular(JkTokens.radiusMd),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _tool(
                          Icons.title,
                          '标题',
                          () => _setHeading(2),
                          edit: true,
                        ),
                        _tool(
                          Icons.format_bold,
                          '加粗',
                          () => _wrap('**', '**', '加粗文字'),
                          edit: true,
                        ),
                        _tool(
                          Icons.format_italic,
                          '斜体',
                          () => _wrap('*', '*', '斜体文字'),
                          edit: true,
                        ),
                        _tool(
                          Icons.format_strikethrough,
                          '删除线',
                          () => _wrap('~~', '~~', '删除线文字'),
                          edit: true,
                        ),
                        _tool(
                          Icons.data_object,
                          '行内代码',
                          () => _wrap('`', '`', '代码'),
                          edit: true,
                        ),
                        _tool(Icons.link, '链接', _insertLink, edit: true),
                        _tool(
                          Icons.format_list_bulleted,
                          '列表',
                          () => _toggleLineFormat(_LineFormat.unordered),
                          edit: true,
                        ),
                        _tool(
                          Icons.format_list_numbered,
                          '有序列表',
                          () => _toggleLineFormat(_LineFormat.ordered),
                          edit: true,
                        ),
                        _tool(
                          Icons.check_box_outlined,
                          '待办',
                          () => _toggleLineFormat(_LineFormat.task),
                          edit: true,
                        ),
                        _tool(
                          Icons.format_quote,
                          '引用',
                          () => _toggleLineFormat(_LineFormat.quote),
                          edit: true,
                        ),
                        _tool(
                          Icons.code,
                          '代码块',
                          () => _insertBlock('```\n\n```', 4),
                          edit: true,
                        ),
                        _tool(
                          Icons.horizontal_rule,
                          '分隔线',
                          () => _insertBlock('---', 3),
                          edit: true,
                        ),
                        _tool(
                          Icons.table_chart_outlined,
                          '表格',
                          () => _insertBlock(
                            _table,
                            _table.lastIndexOf('|  |') + 2,
                          ),
                          edit: true,
                        ),
                        _tool(
                          Icons.format_indent_increase,
                          '增加缩进',
                          () => _indent(outdent: false),
                          edit: true,
                        ),
                        _tool(
                          Icons.format_indent_decrease,
                          '减少缩进',
                          () => _indent(outdent: true),
                          edit: true,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_preview) ...widget.extraTools,
                Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(
                    horizontal: JkTokens.spacingXxs,
                  ),
                  color: c.divider,
                ),
                _tool(
                  _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                  _preview ? '编辑' : '预览',
                  _togglePreview,
                  key: const Key('markdown-preview-toggle'),
                ),
              ],
            ),
          ),
          const SizedBox(height: JkTokens.spacingSm),
          if (widget.expand) Expanded(child: _body(c)) else _body(c),
        ],
      ),
    );
  }

  Widget _body(JkColorTokens c) {
    if (_preview) {
      final totalTasks = countMarkdownTasks(_c.text);
      var checkboxCursor = 0;
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
                softLineBreak: true,
                imageBuilder: widget.imageBuilder,
                onTapLink: widget.onTapLink,
                styleSheet: _previewStyleSheet(context, c),
                checkboxBuilder: (checked) {
                  if (totalTasks == 0) {
                    return Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: checked ? c.primary : c.textSecondary,
                    );
                  }
                  final idx = checkboxCursor++ % totalTasks;
                  return InkWell(
                    key: Key('markdown-preview-checkbox-$idx'),
                    borderRadius: BorderRadius.circular(JkTokens.radiusSm),
                    onTap: () => _toggleTaskInPreview(idx),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        checked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: checked ? c.primary : c.textSecondary,
                      ),
                    ),
                  );
                },
              ),
      );
      final content = widget.expand
          ? SingleChildScrollView(child: preview)
          : preview;
      return Focus(autofocus: true, child: content);
    }
    return TextField(
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
    );
  }

  MarkdownStyleSheet _previewStyleSheet(BuildContext context, JkColorTokens c) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      code: TextStyle(
        fontFamily: 'monospace',
        color: c.primary,
        backgroundColor: c.surfaceVariant,
      ),
      codeblockDecoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(JkTokens.radiusSm),
        border: Border.all(color: c.divider),
      ),
      blockquote: TextStyle(color: c.textSecondary),
      blockquoteDecoration: BoxDecoration(
        color: c.surfaceVariant.withValues(alpha: 0.45),
        border: Border(left: BorderSide(color: c.primary, width: 3)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: 1)),
      ),
      tableBorder: TableBorder.all(color: c.border, width: 1),
      h1: base.h1?.copyWith(fontWeight: JkTokens.fontWeightBold),
      h2: base.h2?.copyWith(fontWeight: JkTokens.fontWeightSemibold),
      h3: base.h3?.copyWith(fontWeight: JkTokens.fontWeightSemibold),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isAltPressed) return KeyEventResult.ignored;

    final command = keys.isControlPressed || keys.isMetaPressed;
    if (command &&
        !keys.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.slash) {
      _togglePreview();
      return KeyEventResult.handled;
    }

    if (_preview) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _indent(outdent: keys.isShiftPressed);
      return KeyEventResult.handled;
    }

    if (!command) return KeyEventResult.ignored;

    if (!keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.digit0) {
      _setHeading(0);
      return KeyEventResult.handled;
    }

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
      _setHeading(heading);
      return KeyEventResult.handled;
    }
    if (!keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyB) {
      _wrap('**', '**', '加粗文字');
      return KeyEventResult.handled;
    }
    if (!keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyI) {
      _wrap('*', '*', '斜体文字');
      return KeyEventResult.handled;
    }
    if (!keys.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.backquote) {
      _wrap('`', '`', '代码');
      return KeyEventResult.handled;
    }
    if (!keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyK) {
      _insertLink();
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyX) {
      _wrap('~~', '~~', '删除线文字');
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
      _insertBlock('```\n\n```', 4);
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyQ) {
      _toggleLineFormat(_LineFormat.quote);
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.digit7) {
      _toggleLineFormat(_LineFormat.ordered);
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.digit8) {
      _toggleLineFormat(_LineFormat.unordered);
      return KeyEventResult.handled;
    }
    if (keys.isShiftPressed && event.logicalKey == LogicalKeyboardKey.digit9) {
      _toggleLineFormat(_LineFormat.task);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _indent({required bool outdent}) {
    if (!_c.selection.isValid) return;
    _transformSelectedLines((lines) {
      if (outdent) {
        return [
          for (final line in lines)
            if (line.startsWith('\t'))
              line.substring(1)
            else if (line.startsWith('  '))
              line.substring(2)
            else if (line.startsWith(' '))
              line.substring(1)
            else
              line,
        ];
      }
      return [for (final line in lines) '  $line'];
    });
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
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 19),
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
