import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/search/search_snippet.dart';

void main() {
  test('关键词位置不区分 ASCII 大小写，重叠的合并', () {
    expect(matchRanges('Flutter flutter', ['FLU']), [(0, 3), (8, 11)]);
    expect(matchRanges('abcdef', ['abc', 'bcd']), [(0, 4)]);
    expect(matchRanges('abc', ['']), isEmpty);
  });

  test('放得下时显示全文；否则从第一个命中前面一点开始，两端加省略号', () {
    expect(snippetOf('短文本 关键词', ['关键']).text, '短文本 关键词');
    final long = '${'甲' * 50}关键词${'乙' * 50}';
    final s = snippetOf(long, ['关键词'], before: 4, length: 20);
    expect(s.text, '…甲甲甲甲关键词乙乙乙乙乙乙乙乙乙乙乙乙乙…');
    expect(s.ranges, [(5, 8)]);
  });

  test('没有命中时取开头；换行合并为空格', () {
    final s = snippetOf('第一行\n\n第二行${'丙' * 100}', ['不存在'], length: 7);
    expect(s.text, '第一行 第二行…');
    expect(s.ranges, isEmpty);
  });

  test('不在代理对中间截断', () {
    final text = '${'a' * 10}😀关键词${'b' * 20}';
    final s = snippetOf(text, ['关键词'], before: 1, length: 6);
    expect(s.text.startsWith('…😀'), isTrue);
    expect(s.ranges, [(3, 6)]);
  });
}
