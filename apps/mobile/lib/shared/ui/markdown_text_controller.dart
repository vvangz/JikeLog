import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';

/// 支持 Markdown 实时语法高亮与排版层次的 [TextEditingController]。
///
/// 保持源码字符与光标偏移 1:1 对应（不隐藏字符），同时在编辑态呈现标题字号、
/// 列表序号/待办标记着色、引用与代码块样式、行内加粗/斜体/删除线/代码高亮，
/// 并在输入法组合（composing）期间保留系统下划线。
class MarkdownTextEditingController extends TextEditingController {
  MarkdownTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    final palette = _MarkdownPalette.of(context);
    final composing =
        withComposing && value.composing.isValid && !value.composing.isCollapsed
        ? value.composing
        : null;
    return _buildMarkdownTextSpan(
      text: text,
      baseStyle: baseStyle,
      palette: palette,
      composing: composing,
    );
  }
}

/// 供实时高亮使用的主题色板（优先读取 [JkColors]，缺失时回退到 [ColorScheme]）。
@immutable
class _MarkdownPalette {
  const _MarkdownPalette({
    required this.accent,
    required this.muted,
    required this.secondary,
    required this.success,
    required this.link,
    required this.codeBg,
  });

  factory _MarkdownPalette.of(BuildContext context) {
    final jk = Theme.of(context).extension<JkColors>()?.tokens;
    if (jk != null) {
      return _MarkdownPalette(
        accent: jk.primary,
        muted: jk.textDisabled,
        secondary: jk.textSecondary,
        success: jk.success,
        link: jk.info,
        codeBg: jk.surfaceVariant,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return _MarkdownPalette(
      accent: scheme.primary,
      muted: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      secondary: scheme.onSurfaceVariant,
      success: scheme.primary,
      link: scheme.tertiary,
      codeBg: scheme.surfaceContainerHighest,
    );
  }

  final Color accent;
  final Color muted;
  final Color secondary;
  final Color success;
  final Color link;
  final Color codeBg;
}

final _fenceRe = RegExp(r'^[ \t]*(`{3,}|~{3,})');
final _headingRe = RegExp(r'^([ \t]*)(#{1,6})([ \t]+)(.*)$');
final _hrRe = RegExp(r'^[ \t]*(?:---+|\*\*\*+|___+)[ \t]*$');
final _quoteRe = RegExp(r'^([ \t]*(?:>[ \t]?)+)(.*)$');
final _taskRe = RegExp(r'^([ \t]*[-+*][ \t]+)(\[([ xX])\])([ \t]+)(.*)$');
final _orderedRe = RegExp(r'^([ \t]*)(\d+\.)([ \t]+)(.*)$');
final _unorderedRe = RegExp(r'^([ \t]*)([-+*])([ \t]+)(.*)$');

// 行内格式：行内代码 > 链接/图片 > 加粗 > 删除线 > 斜体（避免跨行匹配）
final _inlineRe = RegExp(
  r'(`[^`\n]+`)'
  r'|(!?\[[^\]\n]+\]\([^)\n]+\))'
  r'|(\*\*[^*\n]+\*\*|__[^_\n]+__)'
  r'|(~~[^~\n]+~~)'
  r'|(\*(?!\s)[^*\n]+(?<!\s)\*)',
);

/// 将 Markdown 源码构造成与原文字符完全等长的富样式 [TextSpan]。
TextSpan _buildMarkdownTextSpan({
  required String text,
  required TextStyle baseStyle,
  required _MarkdownPalette palette,
  TextRange? composing,
}) {
  if (text.isEmpty) return TextSpan(style: baseStyle, text: '');

  final spans = <InlineSpan>[];
  String? openFenceChar;
  var openFenceLen = 0;

  var pos = 0;
  while (pos < text.length) {
    final nl = text.indexOf('\n', pos);
    final lineEnd = nl == -1 ? text.length : nl;
    final line = text.substring(pos, lineEnd);

    final fenceMatch = _fenceRe.firstMatch(line);
    if (fenceMatch != null) {
      final token = fenceMatch.group(1)!;
      final ch = token[0];
      if (openFenceChar == null) {
        openFenceChar = ch;
        openFenceLen = token.length;
      } else if (ch == openFenceChar &&
          token.length >= openFenceLen &&
          line.substring(fenceMatch.end).trim().isEmpty) {
        openFenceChar = null;
        openFenceLen = 0;
      }
      _pushSpan(
        spans,
        line,
        pos,
        baseStyle.copyWith(
          fontFamily: 'monospace',
          color: palette.muted,
          backgroundColor: palette.codeBg,
        ),
        composing,
      );
    } else if (openFenceChar != null) {
      _pushSpan(
        spans,
        line,
        pos,
        baseStyle.copyWith(
          fontFamily: 'monospace',
          color: palette.secondary,
          backgroundColor: palette.codeBg,
        ),
        composing,
      );
    } else {
      _buildNormalLine(spans, line, pos, baseStyle, palette, composing);
    }

    if (nl != -1) {
      _pushSpan(spans, '\n', lineEnd, baseStyle, composing);
      pos = nl + 1;
    } else {
      pos = lineEnd;
    }
  }

  return TextSpan(style: baseStyle, children: spans);
}

void _buildNormalLine(
  List<InlineSpan> spans,
  String line,
  int lineOffset,
  TextStyle baseStyle,
  _MarkdownPalette palette,
  TextRange? composing,
) {
  if (line.isEmpty) return;

  final heading = _headingRe.firstMatch(line);
  if (heading != null) {
    final indent = heading.group(1)!;
    final hashes = heading.group(2)!;
    final gap = heading.group(3)!;
    final body = heading.group(4)!;
    final scale = switch (hashes.length) {
      1 => 1.42,
      2 => 1.28,
      3 => 1.16,
      4 => 1.08,
      _ => 1.03,
    };
    final fontSize = (baseStyle.fontSize ?? JkTokens.fontSizeBodyLarge) * scale;
    final headingStyle = baseStyle.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
    );
    final markerStyle = headingStyle.copyWith(
      color: palette.muted,
      fontWeight: FontWeight.w500,
    );
    final prefixLen = indent.length + hashes.length + gap.length;
    _pushSpan(
      spans,
      line.substring(0, prefixLen),
      lineOffset,
      markerStyle,
      composing,
    );
    _pushInlineSpans(
      spans,
      body,
      lineOffset + prefixLen,
      headingStyle,
      palette,
      composing,
    );
    return;
  }

  if (_hrRe.hasMatch(line)) {
    _pushSpan(
      spans,
      line,
      lineOffset,
      baseStyle.copyWith(color: palette.muted, fontWeight: FontWeight.w600),
      composing,
    );
    return;
  }

  final quote = _quoteRe.firstMatch(line);
  if (quote != null) {
    final marker = quote.group(1)!;
    final body = quote.group(2)!;
    _pushSpan(
      spans,
      marker,
      lineOffset,
      baseStyle.copyWith(color: palette.accent, fontWeight: FontWeight.w700),
      composing,
    );
    _pushInlineSpans(
      spans,
      body,
      lineOffset + marker.length,
      baseStyle.copyWith(color: palette.secondary, fontStyle: FontStyle.italic),
      palette,
      composing,
    );
    return;
  }

  final task = _taskRe.firstMatch(line);
  if (task != null) {
    final bullet = task.group(1)!;
    final box = task.group(2)!;
    final checked = task.group(3)!.toLowerCase() == 'x';
    final gap = task.group(4)!;
    final body = task.group(5)!;
    var cursor = lineOffset;
    _pushSpan(
      spans,
      bullet,
      cursor,
      baseStyle.copyWith(color: palette.muted),
      composing,
    );
    cursor += bullet.length;
    _pushSpan(
      spans,
      box,
      cursor,
      baseStyle.copyWith(
        fontFamily: 'monospace',
        fontWeight: FontWeight.w700,
        color: checked ? palette.success : palette.accent,
      ),
      composing,
    );
    cursor += box.length;
    _pushSpan(spans, gap, cursor, baseStyle, composing);
    cursor += gap.length;
    final bodyStyle = checked
        ? baseStyle.copyWith(
            color: palette.secondary,
            decoration: TextDecoration.lineThrough,
          )
        : baseStyle;
    _pushInlineSpans(spans, body, cursor, bodyStyle, palette, composing);
    return;
  }

  final ordered = _orderedRe.firstMatch(line);
  if (ordered != null) {
    final indent = ordered.group(1)!;
    final numMark = ordered.group(2)!;
    final gap = ordered.group(3)!;
    final body = ordered.group(4)!;
    var cursor = lineOffset;
    if (indent.isNotEmpty) {
      _pushSpan(spans, indent, cursor, baseStyle, composing);
      cursor += indent.length;
    }
    _pushSpan(
      spans,
      numMark,
      cursor,
      baseStyle.copyWith(color: palette.accent, fontWeight: FontWeight.w600),
      composing,
    );
    cursor += numMark.length;
    _pushSpan(spans, gap, cursor, baseStyle, composing);
    cursor += gap.length;
    _pushInlineSpans(spans, body, cursor, baseStyle, palette, composing);
    return;
  }

  final unordered = _unorderedRe.firstMatch(line);
  if (unordered != null) {
    final indent = unordered.group(1)!;
    final bullet = unordered.group(2)!;
    final gap = unordered.group(3)!;
    final body = unordered.group(4)!;
    var cursor = lineOffset;
    if (indent.isNotEmpty) {
      _pushSpan(spans, indent, cursor, baseStyle, composing);
      cursor += indent.length;
    }
    _pushSpan(
      spans,
      bullet,
      cursor,
      baseStyle.copyWith(color: palette.accent, fontWeight: FontWeight.w700),
      composing,
    );
    cursor += bullet.length;
    _pushSpan(spans, gap, cursor, baseStyle, composing);
    cursor += gap.length;
    _pushInlineSpans(spans, body, cursor, baseStyle, palette, composing);
    return;
  }

  _pushInlineSpans(spans, line, lineOffset, baseStyle, palette, composing);
}

void _pushInlineSpans(
  List<InlineSpan> spans,
  String text,
  int baseOffset,
  TextStyle style,
  _MarkdownPalette palette,
  TextRange? composing,
) {
  if (text.isEmpty) return;
  var last = 0;
  final mutedMarker = style.copyWith(
    color: palette.muted,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.normal,
  );

  for (final m in _inlineRe.allMatches(text)) {
    if (m.start > last) {
      _pushSpan(
        spans,
        text.substring(last, m.start),
        baseOffset + last,
        style,
        composing,
      );
    }
    final token = m.group(0)!;
    final tokenOffset = baseOffset + m.start;

    if (m.group(1) != null) {
      // `inline code`
      final codeStyle = style.copyWith(
        fontFamily: 'monospace',
        color: palette.accent,
        backgroundColor: palette.codeBg,
      );
      final tickStyle = codeStyle.copyWith(color: palette.muted);
      _pushSpan(spans, '`', tokenOffset, tickStyle, composing);
      _pushSpan(
        spans,
        token.substring(1, token.length - 1),
        tokenOffset + 1,
        codeStyle,
        composing,
      );
      _pushSpan(
        spans,
        '`',
        tokenOffset + token.length - 1,
        tickStyle,
        composing,
      );
    } else if (m.group(2) != null) {
      // [label](url) 或 ![alt](url)
      final closeBracket = token.indexOf(']');
      final openBracket = token.startsWith('!') ? 2 : 1;
      _pushSpan(
        spans,
        token.substring(0, openBracket),
        tokenOffset,
        mutedMarker,
        composing,
      );
      _pushSpan(
        spans,
        token.substring(openBracket, closeBracket),
        tokenOffset + openBracket,
        style.copyWith(
          color: palette.link,
          decoration: TextDecoration.underline,
        ),
        composing,
      );
      _pushSpan(
        spans,
        token.substring(closeBracket),
        tokenOffset + closeBracket,
        mutedMarker,
        composing,
      );
    } else if (m.group(3) != null) {
      // **bold** 或 __bold__
      _pushSpan(
        spans,
        token.substring(0, 2),
        tokenOffset,
        mutedMarker,
        composing,
      );
      _pushSpan(
        spans,
        token.substring(2, token.length - 2),
        tokenOffset + 2,
        style.copyWith(fontWeight: FontWeight.w700),
        composing,
      );
      _pushSpan(
        spans,
        token.substring(token.length - 2),
        tokenOffset + token.length - 2,
        mutedMarker,
        composing,
      );
    } else if (m.group(4) != null) {
      // ~~strike~~
      _pushSpan(spans, '~~', tokenOffset, mutedMarker, composing);
      _pushSpan(
        spans,
        token.substring(2, token.length - 2),
        tokenOffset + 2,
        style.copyWith(
          color: palette.secondary,
          decoration: TextDecoration.lineThrough,
        ),
        composing,
      );
      _pushSpan(
        spans,
        '~~',
        tokenOffset + token.length - 2,
        mutedMarker,
        composing,
      );
    } else {
      // *italic*
      _pushSpan(spans, '*', tokenOffset, mutedMarker, composing);
      _pushSpan(
        spans,
        token.substring(1, token.length - 1),
        tokenOffset + 1,
        style.copyWith(fontStyle: FontStyle.italic),
        composing,
      );
      _pushSpan(
        spans,
        '*',
        tokenOffset + token.length - 1,
        mutedMarker,
        composing,
      );
    }
    last = m.end;
  }

  if (last < text.length) {
    _pushSpan(spans, text.substring(last), baseOffset + last, style, composing);
  }
}

/// 将一段带样式的片段写入 [spans]，若与输入法 [composing] 区间重叠则叠加下划线。
void _pushSpan(
  List<InlineSpan> spans,
  String segment,
  int start,
  TextStyle style,
  TextRange? composing,
) {
  if (segment.isEmpty) return;
  if (composing == null) {
    spans.add(TextSpan(text: segment, style: style));
    return;
  }
  final end = start + segment.length;
  if (composing.end <= start || composing.start >= end) {
    spans.add(TextSpan(text: segment, style: style));
    return;
  }
  final overlapStart = (composing.start - start).clamp(0, segment.length);
  final overlapEnd = (composing.end - start).clamp(0, segment.length);
  if (overlapStart > 0) {
    spans.add(TextSpan(text: segment.substring(0, overlapStart), style: style));
  }
  if (overlapEnd > overlapStart) {
    final deco = style.decoration;
    final composedDeco = deco == null || deco == TextDecoration.none
        ? TextDecoration.underline
        : TextDecoration.combine([deco, TextDecoration.underline]);
    spans.add(
      TextSpan(
        text: segment.substring(overlapStart, overlapEnd),
        style: style.copyWith(decoration: composedDeco),
      ),
    );
  }
  if (overlapEnd < segment.length) {
    spans.add(TextSpan(text: segment.substring(overlapEnd), style: style));
  }
}

/// 供单元测试构造固定色板（不依赖 Widget 树）。
@visibleForTesting
TextSpan buildMarkdownTextSpanForTest(
  String text, {
  TextStyle baseStyle = const TextStyle(fontSize: 16),
  TextRange? composing,
}) => _buildMarkdownTextSpan(
  text: text,
  baseStyle: baseStyle,
  palette: const _MarkdownPalette(
    accent: Color(0xFF334AC0),
    muted: Color(0xFF8E9BB0),
    secondary: Color(0xFF4F5B70),
    success: Color(0xFF1E7A4C),
    link: Color(0xFF1B6B8A),
    codeBg: Color(0xFFECF0F7),
  ),
  composing: composing,
);
