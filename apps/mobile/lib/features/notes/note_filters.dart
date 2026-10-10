import 'package:flutter/foundation.dart';

import 'note_models.dart';

/// 笔记列表的筛选条件。
@immutable
sealed class NoteFilter {
  const NoteFilter();

  /// 列表上方显示的名称。
  String label(FolderTree tree);
}

final class AllNotes extends NoteFilter {
  const AllNotes();

  @override
  String label(FolderTree tree) => '全部笔记';

  @override
  bool operator ==(Object other) => other is AllNotes;

  @override
  int get hashCode => 0;
}

final class FavoriteNotes extends NoteFilter {
  const FavoriteNotes();

  @override
  String label(FolderTree tree) => '收藏';

  @override
  bool operator ==(Object other) => other is FavoriteNotes;

  @override
  int get hashCode => 1;
}

/// 未分类：没有文件夹，或文件夹已不存在（例如在其他设备上被删除）。
final class UnfiledNotes extends NoteFilter {
  const UnfiledNotes();

  @override
  String label(FolderTree tree) => '未分类';

  @override
  bool operator ==(Object other) => other is UnfiledNotes;

  @override
  int get hashCode => 2;
}

/// 文件夹中的笔记，包括其下级文件夹。
final class FolderNotes extends NoteFilter {
  const FolderNotes(this.folderId);

  final String folderId;

  @override
  String label(FolderTree tree) =>
      tree.byId.containsKey(folderId) ? tree.path(folderId) : '文件夹';

  @override
  bool operator ==(Object other) =>
      other is FolderNotes && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;
}

final class TagNotes extends NoteFilter {
  const TagNotes(this.tag);

  final String tag;

  @override
  String label(FolderTree tree) => '#$tag';

  @override
  bool operator ==(Object other) => other is TagNotes && other.tag == tag;

  @override
  int get hashCode => tag.hashCode;
}

/// 按条件筛选（保持原有顺序：置顶在前，再按最后修改时间）。
List<Note> applyFilter(List<Note> notes, NoteFilter filter, FolderTree tree) {
  switch (filter) {
    case AllNotes():
      return notes;
    case FavoriteNotes():
      return [
        for (final n in notes)
          if (n.favorite) n,
      ];
    case UnfiledNotes():
      return [
        for (final n in notes)
          if (n.folderId == null || !tree.byId.containsKey(n.folderId)) n,
      ];
    case FolderNotes(:final folderId):
      final ids = tree.subtree(folderId);
      return [
        for (final n in notes)
          if (ids.contains(n.folderId)) n,
      ];
    case TagNotes(:final tag):
      return [
        for (final n in notes)
          if (n.tags.contains(tag)) n,
      ];
  }
}

/// 全部标签及使用次数，按次数降序、名称升序。
List<(String, int)> tagCounts(List<Note> notes) {
  final counts = <String, int>{};
  for (final n in notes) {
    for (final t in n.tags) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  final out = [for (final e in counts.entries) (e.key, e.value)];
  out.sort((a, b) => a.$2 != b.$2 ? b.$2 - a.$2 : a.$1.compareTo(b.$1));
  return out;
}

/// 每个文件夹（含下级）中的笔记数。
Map<String, int> folderCounts(List<Note> notes, FolderTree tree) => {
  for (final id in tree.byId.keys)
    id: applyFilter(notes, FolderNotes(id), tree).length,
};
