import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/refs.dart';
import 'package:jikelog/features/notes/note_models.dart';
import 'package:jikelog/shared/text/markdown_text.dart';

const _a = '0192a000-0000-7000-8000-0000000000a1';
const _b = '0192a000-0000-7000-8000-0000000000b2';
const _c = '0192a000-0000-7000-8000-0000000000c3';
const _d = '0192a000-0000-7000-8000-0000000000d4';

LocalRecord _record(
  Map<String, Object?> fields, {
  Map<String, String> clocks = const {},
  bool dirty = false,
}) => LocalRecord(
  id: _a,
  entity: 'note',
  fields: fields,
  clocks: clocks,
  baseFields: const {},
  baseClocks: const {},
  version: 1,
  serverSeq: 1,
  deleted: false,
  dirty: dirty,
  hasConflict: false,
  updatedAt: DateTime(2026, 10, 10),
);

NoteFolder _folder(String id, String name, [String? parent]) =>
    NoteFolder(id: id, name: name, parentId: parent);

void main() {
  group('多行文本字段', () {
    test('去掉空白、空行与重复行，保持顺序', () {
      expect(parseLines(' a \n\nb\na\n  '), ['a', 'b']);
      expect(parseLines(null), isEmpty);
      expect(parseLines(1), isEmpty);
    });

    test('标签超长的行被忽略；关联只保留合法 UUID', () {
      expect(parseTags('短\n${'长' * 31}'), ['短']);
      expect(parseIds('$_a\nabc\n$_a'), [_a]);
    });
  });

  group('Note.fromRecord', () {
    test('解析全部字段', () {
      final n = Note.fromRecord(
        _record(
          {
            'title': '接口设计',
            'body': '正文',
            'format': 'rich',
            'folderId': _b,
            'favorite': 1,
            'pinned': 0,
            'tags': '后端\n草稿',
            'worklogs': _c,
          },
          clocks: {'title': '1791553544000-0000-aaaaaaaaaaaaaaaa'},
          dirty: true,
        ),
      );
      expect(n.title, '接口设计');
      expect(n.format, NoteFormat.rich);
      expect(n.folderId, _b);
      expect(n.favorite, isTrue);
      expect(n.pinned, isFalse);
      expect(n.tags, ['后端', '草稿']);
      expect(n.worklogIds, [_c]);
      expect(n.pending, isTrue);
      expect(n.updatedAt, DateTime.fromMillisecondsSinceEpoch(1791553544000));
    });

    test('缺失或非法的字段取默认值', () {
      final n = Note.fromRecord(_record({'format': 'html', 'folderId': 'x'}));
      expect(n.format, NoteFormat.markdown);
      expect(n.folderId, isNull);
      expect(n.title, '');
      expect(n.updatedAt, DateTime(2026, 10, 10)); // 没有时钟时用本地时间
    });

    test('显示标题：没有标题时取正文第一个非空行', () {
      Note note(String title, String body) =>
          Note.fromRecord(_record({'title': title, 'body': body}));
      expect(note(' 标题 ', '').displayTitle, '标题');
      expect(note('', '\n## 第一行\n第二行').displayTitle, '第一行');
      expect(note('', '').displayTitle, '无标题笔记');
      expect(note('', '正文 **重点**').excerpt, '正文 重点');
    });
  });

  test('预览中图片显示为 [图片]，链接只保留文字', () {
    expect(
      plainPreview('见![截图](attachment:$_a)与[文档](https://a.b)'),
      '见[图片]与文档',
    );
  });

  group('FolderTree', () {
    test('按名称排序的树与路径', () {
      final t = FolderTree([
        _folder(_a, '工作'),
        _folder(_b, '项目 B', _a),
        _folder(_c, '项目 A', _a),
        _folder(_d, '生活'),
      ]);
      expect(t.roots.map((n) => n.folder.name), ['工作', '生活']);
      expect(t.roots.first.children.map((n) => n.folder.name), [
        '项目 A',
        '项目 B',
      ]);
      expect(t.flatten().map((n) => '${n.depth}${n.folder.name}'), [
        '0工作',
        '1项目 A',
        '1项目 B',
        '0生活',
      ]);
      expect(t.path(_b), '工作 / 项目 B');
      expect(t.subtree(_a), {_a, _b, _c});
      expect(t.subtree('missing'), isEmpty);
    });

    test('上级不存在时按顶层显示', () {
      final t = FolderTree([_folder(_a, '孤儿', _d)]);
      expect(t.roots.single.folder.id, _a);
      expect(t.parentOf(_a), isNull);
      expect(t.path(_a), '孤儿');
    });

    test('循环引用：环上的文件夹按顶层显示，不会死循环', () {
      final t = FolderTree([
        _folder(_a, 'A', _b),
        _folder(_b, 'B', _a),
        _folder(_c, 'C', _c),
      ]);
      expect(t.roots.map((n) => n.folder.id).toSet(), {_a, _b, _c});
      expect(t.flatten(), hasLength(3));
      expect(t.path(_a), 'A');
    });

    test('远处祖先不存在时，下级的层级保持不变；按原始上级链禁止写出循环', () {
      const x = '0192a000-0000-7000-8000-0000000000ee'; // 已在其他设备上删除
      final t = FolderTree([
        _folder(_a, 'P', x),
        _folder(_b, 'Q', _a),
        _folder(_c, 'R', _b),
      ]);
      expect(t.roots.single.folder.id, _a);
      expect(t.path(_c), 'P / Q / R');
      expect(t.subtree(_a), {_a, _b, _c});
      expect(t.canMove(_a, _c), isFalse);
    });

    test('循环的下级挂在环上的文件夹下面', () {
      final t = FolderTree([
        _folder(_a, 'A', _b),
        _folder(_b, 'B', _a),
        _folder(_c, 'C', _a),
      ]);
      expect(t.parentOf(_c), _a);
      expect(t.subtree(_a), {_a, _c});
      expect(t.canMove(_a, _b), isFalse, reason: '原始上级链上 B 已在 A 之下');
    });

    test('不能把文件夹移到自己或自己的下级中', () {
      final t = FolderTree([_folder(_a, '工作'), _folder(_b, '项目', _a)]);
      expect(t.canMove(_a, _b), isFalse);
      expect(t.canMove(_a, _a), isFalse);
      expect(t.canMove(_b, null), isTrue);
      expect(t.canMove(_b, _a), isTrue);
    });
  });
}
