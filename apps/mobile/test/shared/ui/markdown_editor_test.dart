import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/theme/app_theme.dart';
import 'package:jikelog/shared/ui/markdown_editor.dart';

TextEditingValue _insert(String text, int offset, String character) {
  final next = text.replaceRange(offset, offset, character);
  return TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: offset + character.length),
  );
}

TextEditingValue _format(String text, int offset, String character) {
  final old = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset),
  );
  return const MarkdownInputFormatter().formatEditUpdate(
    old,
    _insert(text, offset, character),
  );
}

void main() {
  test('有序列表回车自动递增编号', () {
    final value = _format('1. 第一项', 6, '\n');
    expect(value.text, '1. 第一项\n2. ');
    expect(value.selection.baseOffset, value.text.length);
  });

  test('缩进的无序列表保留缩进和列表符号', () {
    final value = _format('  * 子项', 6, '\n');
    expect(value.text, '  * 子项\n  * ');
  });

  test('任务列表回车生成未完成任务', () {
    final value = _format('- [x] 已完成', 9, '\n');
    expect(value.text, '- [x] 已完成\n- [ ] ');
  });

  test('空列表项回车退出列表', () {
    expect(_format('1. ', 3, '\n').text, '');
    expect(_format('- [ ] ', 6, '\n').text, '');
    expect(_format('- ', 2, '\n').text, '');
  });

  test('普通段落回车不注入列表标记', () {
    final value = _format('普通段落', 4, '\n');
    expect(value.text, '普通段落\n');
  });

  test('输入有序列表标记后的空格保持 Markdown 标记', () {
    final value = _format('1.', 2, ' ');
    expect(value.text, '1. ');
    expect(value.selection.baseOffset, 3);
  });

  test('粘贴多字符内容不触发自动续列', () {
    const old = TextEditingValue(
      text: '1. 第一项',
      selection: TextSelection.collapsed(offset: 6),
    );
    const next = TextEditingValue(
      text: '1. 第一项\n2. 第二项',
      selection: TextSelection.collapsed(offset: 12),
    );
    final value = const MarkdownInputFormatter().formatEditUpdate(old, next);
    expect(value, next);
  });

  testWidgets('Control+B 插入 Markdown 加粗标记', (tester) async {
    final controller = TextEditingController(text: '文字');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: MarkdownEditor(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const Key('worklog-content')));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.text, '文字**加粗文字**');
  });

  testWidgets('Control+1 将当前行切换为一级标题', (tester) async {
    final controller = TextEditingController(text: '标题');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: MarkdownEditor(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const Key('worklog-content')));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.text, '# 标题');
  });
}
