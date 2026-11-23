import 'package:flutter/services.dart';

final _codeFenceLineRe = RegExp(r'^([ \t]*)(`{3,}|~{3,})([^\n]*)$');
final _taskShorthandRe = RegExp(r'^([ \t]*)(?:-[ \t]*)?\[([ xX]?)\]$');
final _taskLineRe = RegExp(r'^([ \t]*)([-+*])[ \t]+\[([ xX])\][ \t]+(.*)$');
final _orderedLineRe = RegExp(r'^([ \t]*)(\d+)\.[ \t]+(.*)$');
final _unorderedLineRe = RegExp(r'^([ \t]*)([-+*])[ \t]+(.*)$');
final _quoteLineRe = RegExp(r'^([ \t]*(?:>[ \t]?)+)(.*)$');

/// 判断 [offset] 所在位置是否处于未闭合的围栏代码块（`` ``` `` / `~~~`）内部。
bool isInsideMarkdownCodeFence(String text, int offset) {
  String? openChar;
  var openLen = 0;
  var pos = 0;
  final limit = offset.clamp(0, text.length);
  while (pos < limit) {
    final nl = text.indexOf('\n', pos);
    if (nl == -1 || nl >= limit) break;
    final line = text.substring(pos, nl);
    final m = _codeFenceLineRe.firstMatch(line);
    if (m != null) {
      final token = m.group(2)!;
      final rest = m.group(3)!;
      if (openChar == null) {
        openChar = token[0];
        openLen = token.length;
      } else if (token[0] == openChar &&
          token.length >= openLen &&
          rest.trim().isEmpty) {
        openChar = null;
        openLen = 0;
      }
    }
    pos = nl + 1;
  }
  return openChar != null;
}

/// 统计正文（跳过围栏代码块）中的任务列表项总数。
int countMarkdownTasks(String text) {
  var count = 0;
  _forEachNonFenceLine(text, (line, _, _) {
    if (_taskLineRe.hasMatch(line)) count++;
  });
  return count;
}

/// 切换正文中第 [taskIndex] 个任务列表项的勾选状态（跳过围栏代码块）。
/// 若索引越界则返回原文本。
String toggleMarkdownTaskAt(String text, int taskIndex) {
  if (taskIndex < 0) return text;
  var current = 0;
  String? updated;
  _forEachNonFenceLine(text, (line, start, _) {
    if (updated != null) return;
    final m = _taskLineRe.firstMatch(line);
    if (m == null) return;
    if (current == taskIndex) {
      final boxIndex = line.indexOf('[', m.group(1)!.length + 1);
      if (boxIndex != -1 && boxIndex + 1 < line.length) {
        final checked = m.group(3)!.toLowerCase() == 'x';
        final nextChar = checked ? ' ' : 'x';
        updated = text.replaceRange(
          start + boxIndex + 1,
          start + boxIndex + 2,
          nextChar,
        );
      }
    }
    current++;
  });
  return updated ?? text;
}

void _forEachNonFenceLine(
  String text,
  void Function(String line, int start, int end) visit,
) {
  String? openChar;
  var openLen = 0;
  var pos = 0;
  while (pos <= text.length) {
    final nl = text.indexOf('\n', pos);
    final end = nl == -1 ? text.length : nl;
    final line = text.substring(pos, end);
    final fence = _codeFenceLineRe.firstMatch(line);
    if (fence != null) {
      final token = fence.group(2)!;
      final rest = fence.group(3)!;
      if (openChar == null) {
        openChar = token[0];
        openLen = token.length;
      } else if (token[0] == openChar &&
          token.length >= openLen &&
          rest.trim().isEmpty) {
        openChar = null;
        openLen = 0;
      }
    } else if (openChar == null) {
      visit(line, pos, end);
    }
    if (nl == -1) break;
    pos = nl + 1;
  }
}

/// Markdown 输入规则（参考 Typora）：
/// - 快捷输入：`[] ` / `[ ] ` → `- [ ] `，`[x] ` → `- [x] `
/// - 列表回车自动续接：有序列表递增编号（并自动顺延后续同级编号）、无序列表、待办清单、引用块
/// - 空列表/空引用项回车退出列表/引用
/// - 围栏代码块（`` ``` `` / `~~~`）回车自动补全闭合标记；代码块内部不触发列表续接
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
    if (insertion == null ||
        (newValue.composing.isValid && !newValue.composing.isCollapsed)) {
      return newValue;
    }

    final lineStart =
        oldValue.text.lastIndexOf(
          '\n',
          insertion.offset == 0 ? 0 : insertion.offset - 1,
        ) +
        1;
    if (isInsideMarkdownCodeFence(oldValue.text, lineStart)) {
      return newValue;
    }

    final line = oldValue.text.substring(lineStart, insertion.offset);

    // 空格快捷语法：行首输入 [] / [ ] / [x] / -[] 后按空格生成标准待办标记
    if (insertion.character == ' ') {
      final shorthand = _taskShorthandRe.firstMatch(line);
      if (shorthand != null) {
        final indent = shorthand.group(1)!;
        final mark = shorthand.group(2)!.toLowerCase() == 'x' ? 'x' : ' ';
        final replacement = '$indent- [$mark] ';
        final text = newValue.text.replaceRange(
          lineStart,
          insertion.offset + 1,
          replacement,
        );
        return newValue.copyWith(
          text: text,
          selection: TextSelection.collapsed(
            offset: lineStart + replacement.length,
          ),
          composing: TextRange.empty,
        );
      }
      return newValue;
    }

    if (insertion.character != '\n') return newValue;

    // 围栏代码块自动闭合：在行尾输入 ``` 或 ```dart 后按回车
    final atLineEnd =
        insertion.offset == oldValue.text.length ||
        oldValue.text[insertion.offset] == '\n';
    if (atLineEnd) {
      final fence = _codeFenceLineRe.firstMatch(line);
      if (fence != null) {
        final indent = fence.group(1)!;
        final token = fence.group(2)!;
        final tail = oldValue.text.substring(insertion.offset);
        if (!_hasUnmatchedClosingFence(tail, token[0], token.length)) {
          final closing = '\n$indent$token';
          final insertAt = insertion.offset + 1;
          final text = newValue.text.replaceRange(insertAt, insertAt, closing);
          return newValue.copyWith(
            text: text,
            selection: TextSelection.collapsed(offset: insertAt),
            composing: TextRange.empty,
          );
        }
      }
    }

    final task = _taskLineRe.firstMatch(line);
    final ordered = task == null ? _orderedLineRe.firstMatch(line) : null;
    final unordered = (task == null && ordered == null)
        ? _unorderedLineRe.firstMatch(line)
        : null;
    final quote = (task == null && ordered == null && unordered == null)
        ? _quoteLineRe.firstMatch(line)
        : null;

    if (task == null && ordered == null && unordered == null && quote == null) {
      return newValue;
    }

    final String indent;
    final String body;
    final String continuation;
    var orderedNextNumber = 0;

    if (task != null) {
      indent = task.group(1)!;
      body = task.group(4)!;
      continuation = '$indent${task.group(2)!} [ ] ';
    } else if (ordered != null) {
      indent = ordered.group(1)!;
      body = ordered.group(3)!;
      orderedNextNumber = int.parse(ordered.group(2)!) + 1;
      continuation = '$indent$orderedNextNumber. ';
    } else if (unordered != null) {
      indent = unordered.group(1)!;
      body = unordered.group(3)!;
      continuation = '$indent${unordered.group(2)!} ';
    } else {
      indent = '';
      body = quote!.group(2)!;
      final rawPrefix = quote.group(1)!;
      continuation = rawPrefix.endsWith(' ') || rawPrefix.endsWith('\t')
          ? rawPrefix
          : '$rawPrefix ';
    }

    // 空列表项 / 空引用项回车退出
    if (body.trim().isEmpty) {
      final following = insertion.offset + 1 < newValue.text.length;
      final alreadyBreak =
          following && newValue.text[insertion.offset + 1] == '\n';
      final replacement = following && !alreadyBreak ? '\n' : '';
      final text = newValue.text.replaceRange(
        lineStart,
        insertion.offset + 1,
        replacement,
      );
      return newValue.copyWith(
        text: text,
        selection: TextSelection.collapsed(
          offset: lineStart + replacement.length,
        ),
        composing: TextRange.empty,
      );
    }

    final insertAt = insertion.offset + 1;
    var text = newValue.text.replaceRange(insertAt, insertAt, continuation);
    final cursorOffset = insertAt + continuation.length;

    // 有序列表在中间回车时，自动顺延后续同级列表项的编号
    if (ordered != null) {
      text = _renumberFollowingOrderedItems(
        text,
        afterOffset: cursorOffset,
        indent: indent,
        startNumber: orderedNextNumber + 1,
      );
    }

    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }
}

bool _hasUnmatchedClosingFence(String tail, String ch, int minLen) {
  var inside = true;
  var pos = 0;
  while (pos < tail.length) {
    final nl = tail.indexOf('\n', pos);
    final end = nl == -1 ? tail.length : nl;
    final line = tail.substring(pos, end);
    final m = _codeFenceLineRe.firstMatch(line);
    if (m != null) {
      final token = m.group(2)!;
      final rest = m.group(3)!;
      if (inside &&
          token[0] == ch &&
          token.length >= minLen &&
          rest.trim().isEmpty) {
        inside = false;
      } else if (!inside && token[0] == ch && token.length >= minLen) {
        inside = true;
      }
    }
    if (nl == -1) break;
    pos = nl + 1;
  }
  return !inside;
}

/// 从 [afterOffset] 所在行的下一行开始，将连续的同级有序列表项依次重新编号。
String _renumberFollowingOrderedItems(
  String text, {
  required int afterOffset,
  required String indent,
  required int startNumber,
}) {
  final firstNl = text.indexOf('\n', afterOffset);
  if (firstNl == -1 || firstNl + 1 >= text.length) return text;

  final buf = StringBuffer(text.substring(0, firstNl + 1));
  var pos = firstNl + 1;
  var nextNum = startNumber;
  var changed = false;

  while (pos < text.length) {
    final nl = text.indexOf('\n', pos);
    final end = nl == -1 ? text.length : nl;
    final line = text.substring(pos, end);

    if (line.trim().isEmpty) {
      buf.write(text.substring(pos));
      break;
    }

    final m = _orderedLineRe.firstMatch(line);
    if (m != null && m.group(1) == indent) {
      final oldNum = m.group(2)!;
      final newNum = '$nextNum';
      if (oldNum != newNum) {
        changed = true;
        final rest = line.substring(indent.length + oldNum.length);
        buf.write('$indent$newNum$rest');
      } else {
        buf.write(line);
      }
      nextNum++;
    } else if (_indentWidth(line) > _indentWidth(indent)) {
      // 更深缩进的子列表项或续行：保持不动并继续向后检查同级项
      buf.write(line);
    } else {
      buf.write(text.substring(pos));
      break;
    }

    if (nl == -1) break;
    buf.write('\n');
    pos = nl + 1;
  }

  return changed ? buf.toString() : text;
}

int _indentWidth(String line) {
  var width = 0;
  for (var i = 0; i < line.length; i++) {
    final code = line.codeUnitAt(i);
    if (code == 0x20) {
      width += 1;
    } else if (code == 0x09) {
      width += 2;
    } else {
      break;
    }
  }
  return width;
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
