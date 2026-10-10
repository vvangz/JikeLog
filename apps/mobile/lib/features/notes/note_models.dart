import 'package:flutter/foundation.dart';

import '../../core/sync/record_store.dart';
import '../../core/sync/refs.dart';
import '../../shared/text/markdown_text.dart';

/// 笔记格式：两种格式的正文都是 Markdown，只决定默认的编辑方式（ADR-007）。
enum NoteFormat {
  markdown,
  rich;

  static NoteFormat parse(Object? v) => v == 'rich' ? rich : markdown;
}

/// 一篇笔记。
@immutable
class Note {
  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.format,
    required this.updatedAt,
    this.folderId,
    this.favorite = false,
    this.pinned = false,
    this.tags = const [],
    this.worklogIds = const [],
    this.pending = false,
    this.hasConflict = false,
    this.syncError,
  });

  factory Note.fromRecord(LocalRecord r) {
    final f = r.fields;
    final folder = f['folderId'];
    return Note(
      id: r.id,
      title: f['title'] as String? ?? '',
      body: f['body'] as String? ?? '',
      format: NoteFormat.parse(f['format']),
      folderId: folder is String && isUuid(folder) ? folder : null,
      favorite: f['favorite'] == 1,
      pinned: f['pinned'] == 1,
      tags: parseTags(f['tags']),
      worklogIds: parseIds(f['worklogs']),
      updatedAt: _lastEdited(r),
      pending: r.dirty,
      hasConflict: r.hasConflict,
      syncError: r.syncError,
    );
  }

  final String id;
  final String title;

  /// Markdown 正文。
  final String body;
  final NoteFormat format;
  final String? folderId;
  final bool favorite;
  final bool pinned;
  final List<String> tags;
  final List<String> worklogIds;

  /// 最后修改时间（任一设备）。
  final DateTime updatedAt;
  final bool pending;
  final bool hasConflict;
  final String? syncError;

  /// 预览只看正文开头：列表每次刷新都会重新生成全部笔记，不能对长正文整篇处理。
  static const _previewChars = 2000;

  late final String _head = body.length <= _previewChars
      ? body
      : body.substring(0, _previewChars);

  /// 列表与标题栏中显示的标题：没有标题时用正文的第一行。
  late final String displayTitle = _titleOrFirstLine();

  /// 列表中的正文摘要（纯文本）。
  late final String excerpt = plainPreview(_head);

  String _titleOrFirstLine() {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final first = plainPreview(
      _head
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
    );
    return first.isEmpty ? '无标题笔记' : first;
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.format == format &&
      other.folderId == folderId &&
      other.favorite == favorite &&
      other.pinned == pinned &&
      listEquals(other.tags, tags) &&
      listEquals(other.worklogIds, worklogIds) &&
      other.updatedAt == updatedAt &&
      other.pending == pending &&
      other.hasConflict == hasConflict &&
      other.syncError == syncError;

  @override
  int get hashCode => Object.hash(id, title, body.length, updatedAt, pending);

  /// 最后修改时间取各字段 HLC 的最大值（HLC 前 13 位为毫秒时间戳），
  /// 而不是本机写入时间：拉取到旧笔记时不应让它排到最前面。
  static DateTime _lastEdited(LocalRecord r) {
    var ms = 0;
    for (final c in r.clocks.values) {
      final t = int.tryParse(c.split('-').first) ?? 0;
      if (t > ms) ms = t;
    }
    return ms == 0 ? r.updatedAt : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

/// 笔记文件夹。
@immutable
class NoteFolder {
  const NoteFolder({required this.id, required this.name, this.parentId});

  factory NoteFolder.fromRecord(LocalRecord r) {
    final parent = r.fields['parentId'];
    return NoteFolder(
      id: r.id,
      name: (r.fields['name'] as String? ?? '').trim(),
      parentId: parent is String && isUuid(parent) ? parent : null,
    );
  }

  final String id;
  final String name;
  final String? parentId;
}

/// 文件夹名的上限（与服务端一致）。
const maxFolderNameLength = 50;

/// 笔记正文的上限（字符，与服务端一致）。
const maxNoteBodyLength = 100000;

/// 笔记标题的上限（与服务端一致）。
const maxNoteTitleLength = 200;

/// 文件夹树中的一个节点。
@immutable
class FolderNode {
  const FolderNode(this.folder, this.depth, this.children);

  final NoteFolder folder;
  final int depth;
  final List<FolderNode> children;
}

/// 文件夹树：容错处理多设备同时修改造成的异常（ADR-007）。
///
/// - 上级文件夹不存在（已在其他设备删除）：按顶层文件夹显示
/// - 两台设备同时移动形成循环：环上的文件夹按顶层文件夹显示
class FolderTree {
  FolderTree(Iterable<NoteFolder> folders)
    : byId = {for (final f in folders) f.id: f} {
    final parentOf = <String, String?>{};
    for (final f in byId.values) {
      parentOf[f.id] = _effectiveParent(f);
    }
    final kids = <String?, List<NoteFolder>>{};
    for (final f in byId.values) {
      kids.putIfAbsent(parentOf[f.id], () => []).add(f);
    }
    for (final list in kids.values) {
      list.sort(_byName);
    }
    _parentOf = parentOf;
    _children = {
      for (final e in kids.entries)
        if (e.key != null) e.key!: [for (final f in e.value) f.id],
    };
    roots = _build(kids, null, 0);
  }

  final Map<String, NoteFolder> byId;
  late final Map<String, String?> _parentOf;
  late final Map<String, List<String>> _children;
  late final List<FolderNode> roots;

  static int _byName(NoteFolder a, NoteFolder b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// 显示用的上级：直接上级不存在，或自己在循环上时视为顶层；其余保留原来的上级
  /// （祖先链上更远处的异常不影响自己，否则整条链都会被拍平）。
  String? _effectiveParent(NoteFolder f) {
    final parent = f.parentId;
    if (parent == null || !byId.containsKey(parent)) return null;
    return _onCycle(f.id) ? null : parent;
  }

  /// 沿原始上级链向上走能否回到自己。
  bool _onCycle(String id) {
    final seen = <String>{};
    String? cur = byId[id]?.parentId;
    while (cur != null && byId.containsKey(cur) && seen.add(cur)) {
      if (cur == id) return true;
      cur = byId[cur]!.parentId;
    }
    return false;
  }

  List<FolderNode> _build(
    Map<String?, List<NoteFolder>> kids,
    String? parent,
    int depth,
  ) => [
    for (final f in kids[parent] ?? const <NoteFolder>[])
      FolderNode(f, depth, _build(kids, f.id, depth + 1)),
  ];

  /// 深度优先展开（用于列表显示和选择器）。
  List<FolderNode> flatten() {
    final out = <FolderNode>[];
    void walk(List<FolderNode> nodes) {
      for (final n in nodes) {
        out.add(n);
        walk(n.children);
      }
    }

    walk(roots);
    return out;
  }

  /// 显示用的上级（容错后的）。
  String? parentOf(String id) => _parentOf[id];

  /// [id] 及其全部下级文件夹（按显示的树）。
  Set<String> subtree(String id) {
    final out = <String>{};
    void walk(String cur) {
      if (!out.add(cur)) return;
      for (final c in _children[cur] ?? const <String>[]) {
        walk(c);
      }
    }

    if (byId.containsKey(id)) walk(id);
    return out;
  }

  /// 从顶层到 [id] 的路径名，如"工作 / 项目 A"。
  String path(String id) {
    final names = <String>[];
    String? cur = id;
    while (cur != null &&
        byId.containsKey(cur) &&
        names.length <= byId.length) {
      names.insert(0, byId[cur]!.name);
      cur = _parentOf[cur];
    }
    return names.join(' / ');
  }

  /// 把 [id] 移到 [target] 下是否合法：不能移到自己或自己的下级中。
  /// 按原始的上级链判断（而不是容错后显示的树），否则可能写出真正的循环。
  bool canMove(String id, String? target) {
    if (target == null) return true;
    if (subtree(id).contains(target)) return false;
    final seen = <String>{};
    String? cur = target;
    while (cur != null && seen.add(cur)) {
      if (cur == id) return false;
      cur = byId[cur]?.parentId;
    }
    return true;
  }
}
