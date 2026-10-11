import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/search/search_doc.dart';
import 'package:jikelog/core/sync/schema.dart';

void main() {
  group('markdownToPlain', () {
    test('去掉标记，链接与图片只保留文字', () {
      const md = '''# 标题
> 引用 **加粗** 与 `代码`
- [x] 已完成的待办
1. 第一项
![截图](attachment:0192a000-0000-7000-8000-000000000001)
[官网](https://example.com) 结尾

```dart
var a = 1;
```
| 列一 | 列二 |
| --- | --- |
| 甲 | 乙 |
<br>转义 \\* 星号 snake_case''';
      expect(
        markdownToPlain(md),
        '标题\n引用 加粗 与 代码\n已完成的待办\n第一项\n截图\n官网 结尾\n'
        'var a = 1;\n列一 列二\n甲 乙\n转义 星号 snake_case',
      );
    });

    test('空文本', () => expect(markdownToPlain(''), ''));
  });

  group('searchDocOf', () {
    test('工作日志：地点为标题，内容转纯文本，按日志日期', () {
      expect(
        searchDocOf(Entities.worklog, {
          'date': '2026-10-11',
          'location': '北京',
          'content': '**评审**会议',
        }, const {}),
        const SearchDoc(title: '北京', body: '评审会议', day: '2026-10-11'),
      );
    });

    test('笔记：正文加标签，日期取最后修改的字段时钟', () {
      final ms = DateTime(2026, 10, 9, 12).millisecondsSinceEpoch;
      final doc = searchDocOf(
        Entities.note,
        {'title': '周报', 'body': '## 本周\n完成', 'tags': '工作\n总结'},
        {
          'title': '0000000000001-0000-a',
          'body': '${ms.toString().padLeft(13, '0')}-0001-a',
        },
      )!;
      expect(doc.title, '周报');
      expect(doc.body, '本周\n完成\n工作\n总结');
      expect(doc.day, '2026-10-09');
    });

    test('备忘录按提醒时间的本地日期；流水按记账日期', () {
      final at = DateTime(2026, 10, 12, 23, 30).millisecondsSinceEpoch;
      expect(
        searchDocOf(Entities.memo, {'content': '交房租', 'at': at}, const {}),
        const SearchDoc(title: '', body: '交房租', day: '2026-10-12'),
      );
      expect(
        searchDocOf(Entities.ledgerEntry, {
          'note': '午饭',
          'date': '2026-10-11',
        }, const {})!.day,
        '2026-10-11',
      );
    });

    test('账户、分类、借贷只用名称与对方；附件和文件夹不参与搜索', () {
      expect(
        searchDocOf(Entities.ledgerCategory, {'name': '餐饮'}, const {}),
        const SearchDoc(title: '餐饮', body: ''),
      );
      expect(
        searchDocOf(Entities.ledgerLoan, {
          'counterparty': '李四',
          'note': '装修',
        }, const {}),
        const SearchDoc(title: '李四', body: '装修'),
      );
      expect(
        searchDocOf(Entities.attachment, {'fileName': 'a'}, const {}),
        isNull,
      );
      expect(searchDocOf(Entities.noteFolder, {'name': 'a'}, const {}), isNull);
    });

    test('字段类型异常时按空处理', () {
      expect(
        searchDocOf(Entities.memo, {'content': 1, 'at': 'x'}, const {}),
        const SearchDoc(title: '', body: '', day: ''),
      );
    });
  });
}
