/// 记录之间的引用（标签、关联的工作日志、所属文件夹），存入本地派生表 record_refs
/// 用于筛选和反向查找（ADR-007）。
library;

import 'schema.dart';

/// 引用类型。
abstract final class RefKind {
  static const tag = 'tag';
  static const worklog = 'worklog';
  static const folder = 'folder';
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

bool isUuid(String s) => _uuid.hasMatch(s);

/// 标签名的上限（字符）。
const maxTagLength = 30;

/// 多行文本字段（标签、关联）的规范形式：去掉首尾空白、空行与重复行，保持原有顺序。
List<String> parseLines(Object? raw) {
  if (raw is! String) return const [];
  final seen = <String>{};
  return [
    for (final line in raw.split('\n'))
      if (line.trim() case final t when t.isNotEmpty && seen.add(t)) t,
  ];
}

/// 标签：非空、不含换行、不超过 [maxTagLength] 个字符。
List<String> parseTags(Object? raw) => [
  for (final t in parseLines(raw))
    if (t.runes.length <= maxTagLength) t,
];

/// 关联的工作日志 ID（忽略不合法的行）。
List<String> parseIds(Object? raw) => [
  for (final t in parseLines(raw))
    if (isUuid(t)) t,
];

/// 一条记录的全部引用：(类型, 值)。
List<(String, String)> refsOf(String entity, Map<String, Object?> fields) {
  if (entity != Entities.note) return const [];
  final folder = fields['folderId'];
  return [
    for (final t in parseTags(fields['tags'])) (RefKind.tag, t),
    for (final id in parseIds(fields['worklogs'])) (RefKind.worklog, id),
    if (folder is String && isUuid(folder)) (RefKind.folder, folder),
  ];
}
