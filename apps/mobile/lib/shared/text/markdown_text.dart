/// Markdown 正文的纯文本形式（列表预览、无标题笔记的标题）。
library;

final _linePrefix = RegExp(
  r'^\s*(#{1,6}\s|[-*+]\s(\[[ xX]\]\s)?|\d+\.\s|>\s?)',
);
final _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _marks = RegExp(r'[*_`~]');

/// 把 Markdown 正文转为预览用的纯文本：去掉标记、表格与代码块围栏，图片显示为"[图片]"。
String plainPreview(String markdown) => markdown
    .split('\n')
    .map(
      (l) => l
          .replaceFirst(_linePrefix, '')
          .replaceAllMapped(_image, (_) => '[图片]')
          .replaceAllMapped(_link, (m) => m[1]!)
          .replaceAll(_marks, '')
          .trim(),
    )
    .where((l) => l.isNotEmpty && !l.startsWith('|') && !l.startsWith('```'))
    .join(' ');
