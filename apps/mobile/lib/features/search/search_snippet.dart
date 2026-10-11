import 'package:flutter/material.dart';

/// 结果中显示的一段文字及其中关键词的位置。
@immutable
class Snippet {
  const Snippet(this.text, this.ranges);

  final String text;

  /// 命中位置 [start, end)，按起点排序、互不重叠。
  final List<(int, int)> ranges;
}

/// 只把 ASCII 字母转为小写：与 SQLite 的 LIKE 和 trigram 一致，并且不改变字符串长度，位置可以直接对应。
String _fold(String s) => String.fromCharCodes(
  s.codeUnits.map((c) => c >= 0x41 && c <= 0x5a ? c + 32 : c),
);

/// 文字中全部关键词的位置（合并重叠部分）。
List<(int, int)> matchRanges(String text, List<String> terms) {
  final hay = _fold(text);
  final found = <(int, int)>[];
  for (final t in terms) {
    if (t.isEmpty) continue;
    final needle = _fold(t);
    var i = hay.indexOf(needle);
    while (i >= 0) {
      found.add((i, i + needle.length));
      i = hay.indexOf(needle, i + needle.length);
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in found) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// 截取第一个命中位置附近的一段文字（单行）。没有命中时取开头。
Snippet snippetOf(
  String text,
  List<String> terms, {
  int before = 12,
  int length = 80,
}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final all = matchRanges(flat, terms);
  // 放得下时显示全文；否则从第一个命中位置前面一点开始
  var start = flat.length <= length || all.isEmpty || all.first.$1 <= before
      ? 0
      : all.first.$1 - before;
  var end = start + length >= flat.length ? flat.length : start + length;
  // 不从代理对中间截断
  if (start > 0 && _isLowSurrogate(flat.codeUnitAt(start))) start--;
  if (end < flat.length && _isLowSurrogate(flat.codeUnitAt(end))) end++;
  final prefix = start > 0 ? '…' : '';
  final suffix = end < flat.length ? '…' : '';
  final shift = prefix.length - start;
  return Snippet('$prefix${flat.substring(start, end)}$suffix', [
    for (final (s, e) in all)
      if (s < end && e > start)
        ((s < start ? start : s) + shift, (e > end ? end : e) + shift),
  ]);
}

bool _isLowSurrogate(int c) => c >= 0xdc00 && c <= 0xdfff;

/// 带关键词高亮的文字。
class HighlightText extends StatelessWidget {
  const HighlightText(
    this.snippet, {
    super.key,
    this.style,
    this.highlight,
    this.maxLines = 1,
  });

  final Snippet snippet;
  final TextStyle? style;
  final TextStyle? highlight;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final s = snippet;
    final spans = <TextSpan>[];
    var pos = 0;
    for (final (start, end) in s.ranges) {
      if (start > pos) spans.add(TextSpan(text: s.text.substring(pos, start)));
      spans.add(TextSpan(text: s.text.substring(start, end), style: highlight));
      pos = end;
    }
    if (pos < s.text.length) spans.add(TextSpan(text: s.text.substring(pos)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
