import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/sync/text_patch.dart';

/// 与服务端 server/internal/textpatch 共用的用例（testdata/textpatch/cases.json）。
void main() {
  final file = File('../../testdata/textpatch/cases.json');
  final cases =
      (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['cases']
          as List<dynamic>;

  group('共享用例', () {
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final name = c['name'] as String;
      final base = c['base'] as String;
      final target = c['target'] as String;
      final current = c['current'] as String;
      final expected = c['expected'] as String?;
      final hunks = (c['hunks'] as List<dynamic>)
          .map((h) => Hunk.fromJson(h as Map<String, dynamic>))
          .toList();

      test('$name：应用给定补丁', () {
        final r = TextPatch.apply(current, hunks);
        if (expected == null) {
          expect(r.ok, isFalse);
          expect(r.text, current);
        } else {
          expect(r.ok, isTrue);
          expect(r.text, expected);
        }
      });

      if (c['makeCheck'] == true) {
        test('$name：生成的补丁结果一致', () {
          final made = TextPatch.make(base, target);
          expect(TextPatch.apply(base, made).text, target);
          final r = TextPatch.apply(current, made);
          expect(r.ok, expected != null);
          if (expected != null) expect(r.text, expected);
        });
      }
    }
  });

  test('相同文本不生成补丁', () {
    expect(TextPatch.make('不变', '不变'), isEmpty);
  });

  test('JSON 往返', () {
    final hunks = TextPatch.make('上午开会', '上午开周会');
    final decoded = TextPatch.decode(TextPatch.encode(hunks));
    expect(TextPatch.apply('上午开会', decoded).text, '上午开周会');
  });

  test('随机编辑：补丁应用到基准文本必定得到目标文本', () {
    final rnd = Random(20261009);
    const alphabet = ['a', 'b', '日', '志', '\n', ' ', '📅', '✅', '，'];
    String randomText(int n) =>
        List.generate(n, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
    for (var i = 0; i < 300; i++) {
      final base = randomText(rnd.nextInt(80));
      final runes = base.runes.toList();
      // 在随机位置做几处插入和删除
      for (var k = 0; k < 1 + rnd.nextInt(4); k++) {
        final pos = runes.isEmpty ? 0 : rnd.nextInt(runes.length + 1);
        if (rnd.nextBool() && pos < runes.length) {
          runes.removeRange(pos, min(runes.length, pos + 1 + rnd.nextInt(5)));
        } else {
          runes.insertAll(pos, randomText(1 + rnd.nextInt(6)).runes);
        }
      }
      final target = String.fromCharCodes(runes);
      final made = TextPatch.make(base, target);
      final r = TextPatch.apply(base, made);
      expect(r.ok, isTrue, reason: 'base=$base target=$target');
      expect(r.text, target, reason: 'base=$base target=$target');
    }
  });

  test('两台设备修改不同段落时可以合并', () {
    final paragraphs = List.generate(20, (i) => '第$i段：今天的工作内容。');
    final base = paragraphs.join('\n');
    final mine = [...paragraphs]..[3] = '第3段：今天的工作内容，补充说明。';
    final theirs = [...paragraphs]..[15] = '第15段：已删除部分内容。';
    final hunks = TextPatch.make(base, mine.join('\n'));
    final r = TextPatch.apply(theirs.join('\n'), hunks);
    expect(r.ok, isTrue);
    expect(r.text, ([...theirs]..[3] = mine[3]).join('\n'));
  });
}
