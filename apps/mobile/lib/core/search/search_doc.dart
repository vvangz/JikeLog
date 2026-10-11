/// 全局搜索的索引内容（ADR-010）：每条记录对应一行，随记录保存而更新。
library;

import 'package:flutter/foundation.dart';

import '../sync/schema.dart';

/// 一条记录在搜索索引中的内容。
@immutable
class SearchDoc {
  const SearchDoc({required this.title, required this.body, this.day = ''});

  final String title;
  final String body;

  /// 用于时间筛选的日期（`YYYY-MM-DD`）；账户、分类、借贷为空。
  final String day;

  @override
  bool operator ==(Object other) =>
      other is SearchDoc &&
      other.title == title &&
      other.body == body &&
      other.day == day;

  @override
  int get hashCode => Object.hash(title, body, day);
}

/// 一条记录的索引内容；不参与搜索的实体（附件、笔记文件夹）返回 null。
SearchDoc? searchDocOf(
  String entity,
  Map<String, Object?> fields,
  Map<String, String> clocks,
) {
  String str(String f) => switch (fields[f]) {
    final String s => s,
    _ => '',
  };
  return switch (entity) {
    Entities.worklog => SearchDoc(
      title: str('location'),
      body: markdownToPlain(str('content')),
      day: str('date'),
    ),
    Entities.note => SearchDoc(
      title: str('title'),
      body: [
        markdownToPlain(str('body')),
        str('tags'),
      ].where((s) => s.isNotEmpty).join('\n'),
      day: _clockDay(clocks),
    ),
    Entities.memo => SearchDoc(
      title: '',
      body: str('content'),
      day: switch (fields['at']) {
        final int ms => formatDay(DateTime.fromMillisecondsSinceEpoch(ms)),
        _ => '',
      },
    ),
    Entities.ledgerEntry => SearchDoc(
      title: '',
      body: str('note'),
      day: str('date'),
    ),
    Entities.ledgerAccount ||
    Entities.ledgerCategory => SearchDoc(title: str('name'), body: ''),
    Entities.ledgerLoan => SearchDoc(
      title: str('counterparty'),
      body: str('note'),
    ),
    _ => null,
  };
}

/// 本地日期 `YYYY-MM-DD`。
String formatDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 最后修改的日期：字段时钟（HLC）的前 13 位是毫秒时间戳。
String _clockDay(Map<String, String> clocks) {
  var latest = 0;
  for (final c in clocks.values) {
    final ms = c.length >= 13 ? int.tryParse(c.substring(0, 13)) : null;
    if (ms != null && ms > latest) latest = ms;
  }
  return latest == 0
      ? ''
      : formatDay(DateTime.fromMillisecondsSinceEpoch(latest));
}

final _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _blockPrefix = RegExp(
  r'^[ \t]*(?:>[ \t]?)*(?:#{1,6}[ \t]+|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d+[.)][ \t]+)?',
  multiLine: true,
);
final _fenceOrRule = RegExp(
  r'^[ \t]*(?:```.*|~~~.*|\|?[ \t]*:?-{3,}[-:| \t]*)$',
  multiLine: true,
);
final _inlineMarks = RegExp(r'\*\*|__|~~|`|\*');
final _escape = RegExp(r'\\([\\`*_{}\[\]()#+\-.!|>~])');
final _html = RegExp(r'<[^>\n]+>');
final _spaces = RegExp(r'[ \t]+');
final _blankLines = RegExp(r'\n{2,}');

/// Markdown 转为用于搜索和片段显示的纯文本：去掉标记，链接和图片只保留文字。
String markdownToPlain(String md) {
  if (md.isEmpty) return '';
  var s = md.replaceAll('\r\n', '\n');
  s = s.replaceAllMapped(_image, (m) => m[1]!);
  s = s.replaceAllMapped(_link, (m) => m[1]!);
  s = s.replaceAll(_fenceOrRule, '');
  s = s.replaceAll(_blockPrefix, '');
  s = s.replaceAll(_html, '');
  // 先处理转义：被转义的符号是正文，之后去标记时不应留下反斜杠
  s = s.replaceAllMapped(_escape, (m) => m[1]!);
  s = s.replaceAll(_inlineMarks, '');
  s = s.replaceAll('|', ' ');
  s = s.replaceAll(_spaces, ' ');
  s = s.split('\n').map((l) => l.trim()).join('\n');
  return s.replaceAll(_blankLines, '\n').trim();
}
