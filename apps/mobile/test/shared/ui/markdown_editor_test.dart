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

Future<void> _sendShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = true,
  bool shift = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<MarkdownTextEditingController> _mountEditor(
  WidgetTester tester, {
  String text = '',
  void Function(String, String?, String)? onTapLink,
}) async {
  final controller = MarkdownTextEditingController(text: text);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MarkdownEditor(controller: controller, onTapLink: onTapLink),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('worklog-content')));
  await tester.pump();
  return controller;
}

void main() {
  group('MarkdownInputFormatter', () {
    test('有序列表回车自动递增编号', () {
      final value = _format('1. 第一项', 6, '\n');
      expect(value.text, '1. 第一项\n2. ');
      expect(value.selection.baseOffset, value.text.length);
    });

    test('有序列表中间回车自动顺延后续同级编号并保留子项', () {
      const src = '1. 第一项\n  - 子项\n2. 第二项\n3. 第三项\n\n1. 另一段';
      final value = _format(src, 6, '\n');
      expect(value.text, '1. 第一项\n2. \n  - 子项\n3. 第二项\n4. 第三项\n\n1. 另一段');
      expect(value.selection.baseOffset, '1. 第一项\n2. '.length);
    });

    test('缩进的无序列表保留缩进和列表符号', () {
      final value = _format('  * 子项', 6, '\n');
      expect(value.text, '  * 子项\n  * ');
    });

    test('任务列表回车生成未完成任务', () {
      final value = _format('- [x] 已完成', 9, '\n');
      expect(value.text, '- [x] 已完成\n- [ ] ');
    });

    test('引用块回车自动续接，空引用行回车退出', () {
      final cont = _format('> 引用内容', 6, '\n');
      expect(cont.text, '> 引用内容\n> ');
      expect(cont.selection.baseOffset, cont.text.length);

      final nested = _format('> > 嵌套引用', 8, '\n');
      expect(nested.text, '> > 嵌套引用\n> > ');

      expect(_format('> ', 2, '\n').text, '');
    });

    test('空列表项回车退出列表', () {
      expect(_format('1. ', 3, '\n').text, '');
      expect(_format('- [ ] ', 6, '\n').text, '');
      expect(_format('- ', 2, '\n').text, '');
    });

    test('正文中间的空列表项回车保留空白行', () {
      final value = _format('前文\n- \n后文', 5, '\n');
      expect(value.text, '前文\n\n后文');
      expect(value.selection.baseOffset, 3);
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

    test('输入 [] / [ ] / [x] / -[] 后空格自动生成待办列表标记', () {
      expect(_format('[]', 2, ' ').text, '- [ ] ');
      expect(_format('[ ]', 3, ' ').text, '- [ ] ');
      expect(_format('[x]', 3, ' ').text, '- [x] ');
      expect(_format('  [X]', 5, ' ').text, '  - [x] ');
      expect(_format('-[]', 3, ' ').text, '- [ ] ');
    });

    test('围栏代码块回车自动补全闭合标记，且已有闭合时不重复补全', () {
      final opened = _format('```dart', 7, '\n');
      expect(opened.text, '```dart\n\n```');
      expect(opened.selection.baseOffset, '```dart\n'.length);

      final tilde = _format('~~~', 3, '\n');
      expect(tilde.text, '~~~\n\n~~~');

      const alreadyClosed = '```dart\nprint(1);\n```';
      final noDup = _format(alreadyClosed, 7, '\n');
      expect(noDup.text, '```dart\n\nprint(1);\n```');
    });

    test('代码块内部回车不触发列表续接或待办快捷语法', () {
      const src = '```\n- code item';
      final enter = _format(src, src.length, '\n');
      expect(enter.text, '```\n- code item\n');

      const srcBox = '```\n[]';
      final space = _format(srcBox, srcBox.length, ' ');
      expect(space.text, '```\n[] ');
    });

    test('粘贴多字符内容或输入法组合中不触发自动续列', () {
      const old = TextEditingValue(
        text: '1. 第一项',
        selection: TextSelection.collapsed(offset: 6),
      );
      const pasted = TextEditingValue(
        text: '1. 第一项\n2. 第二项',
        selection: TextSelection.collapsed(offset: 12),
      );
      expect(
        const MarkdownInputFormatter().formatEditUpdate(old, pasted),
        pasted,
      );

      const composing = TextEditingValue(
        text: '1. 第一项\n',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 3, end: 6),
      );
      expect(
        const MarkdownInputFormatter().formatEditUpdate(old, composing),
        composing,
      );
    });
  });

  group('toggleMarkdownTaskAt & countMarkdownTasks', () {
    test('按索引切换待办状态并跳过代码块中的伪待办', () {
      const doc = '- [ ] 一\n```\n- [ ] 代码内\n```\n- [x] 二';
      expect(countMarkdownTasks(doc), 2);
      final first = toggleMarkdownTaskAt(doc, 0);
      expect(first, '- [x] 一\n```\n- [ ] 代码内\n```\n- [x] 二');
      final second = toggleMarkdownTaskAt(first, 1);
      expect(second, '- [x] 一\n```\n- [ ] 代码内\n```\n- [ ] 二');
      expect(toggleMarkdownTaskAt(doc, 5), doc);
    });
  });

  group('MarkdownTextEditingController 实时语法高亮', () {
    test('构造的 TextSpan 保持与原文完全一致的文本长度与顺序', () {
      const sample =
          '# 一级标题\n'
          '## 二级 **加粗** *斜体* ~~删除~~ `code` [链接](https://a.test)\n'
          '> 引用内容\n'
          '1. 有序一\n'
          '- 无序一\n'
          '- [ ] 待办\n'
          '- [x] 已完成\n'
          '---\n'
          '```dart\n'
          'final x = 1;\n'
          '```\n'
          '正文 ![图](attachment:1)';
      final span = buildMarkdownTextSpanForTest(
        sample,
        composing: const TextRange(start: 2, end: 6),
      );
      expect(span.toPlainText(), sample);

      // 标题字号大于正文
      final firstChildren = span.children!.cast<TextSpan>();
      expect(firstChildren.first.style!.fontSize, greaterThan(16));
      // 组合区间叠加了系统下划线
      expect(
        firstChildren.any(
          (s) =>
              s.text == '一级标题' &&
              s.style?.decoration == TextDecoration.underline,
        ),
        isTrue,
      );
      // 已完成待办内容带删除线
      expect(
        firstChildren.any(
          (s) =>
              s.text == '已完成' &&
              s.style?.decoration == TextDecoration.lineThrough,
        ),
        isTrue,
      );
      // 行内代码使用等宽字体
      expect(
        firstChildren.any(
          (s) => s.text == 'code' && s.style?.fontFamily == 'monospace',
        ),
        isTrue,
      );
    });
  });

  group('MarkdownEditor 快捷键、工具栏与预览交互', () {
    testWidgets('Control+B 插入加粗，再次按 Control+B 取消加粗', (tester) async {
      final controller = await _mountEditor(tester, text: '文字');
      controller.selection = const TextSelection.collapsed(offset: 2);

      await _sendShortcut(tester, LogicalKeyboardKey.keyB);
      expect(controller.text, '文字**加粗文字**');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 4, extentOffset: 8),
      );

      // 再次按下取消包裹
      await _sendShortcut(tester, LogicalKeyboardKey.keyB);
      expect(controller.text, '文字加粗文字');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
    });

    testWidgets('Control+I、Control+反引号、Control+Shift+X 行内格式快捷键', (
      tester,
    ) async {
      final controller = await _mountEditor(tester, text: '示例');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      await _sendShortcut(tester, LogicalKeyboardKey.keyI);
      expect(controller.text, '*示例*');

      controller.selection = const TextSelection.collapsed(offset: 4);
      await _sendShortcut(tester, LogicalKeyboardKey.backquote);
      expect(controller.text, '*示例*`代码`');

      controller.text = '删除';
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      await _sendShortcut(tester, LogicalKeyboardKey.keyX, shift: true);
      expect(controller.text, '~~删除~~');
    });

    testWidgets('Control+K 智能插入链接（空选区、选中文字、选中 URL）', (tester) async {
      final controller = await _mountEditor(tester, text: '官网');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      await _sendShortcut(tester, LogicalKeyboardKey.keyK);
      expect(controller.text, '[官网](https://)');
      expect(
        controller.text.substring(
          controller.selection.start,
          controller.selection.end,
        ),
        'https://',
      );

      controller.text = 'https://www.pingvv.top';
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await _sendShortcut(tester, LogicalKeyboardKey.keyK);
      expect(controller.text, '[链接文字](https://www.pingvv.top)');
      expect(
        controller.text.substring(
          controller.selection.start,
          controller.selection.end,
        ),
        '链接文字',
      );
    });

    testWidgets('Control+1..6 切换标题级别不叠加，Control+0 清除标题', (tester) async {
      final controller = await _mountEditor(tester, text: '标题');
      controller.selection = const TextSelection.collapsed(offset: 2);

      await _sendShortcut(tester, LogicalKeyboardKey.digit1);
      expect(controller.text, '# 标题');

      await _sendShortcut(tester, LogicalKeyboardKey.digit3);
      expect(controller.text, '### 标题');

      await _sendShortcut(tester, LogicalKeyboardKey.digit0);
      expect(controller.text, '标题');
    });

    testWidgets('列表快捷键支持互斥切换及多行连续编号，Tab/Shift+Tab 支持多行缩进', (tester) async {
      final controller = await _mountEditor(tester, text: '第一行\n第二行');
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );

      await _sendShortcut(tester, LogicalKeyboardKey.digit7, shift: true);
      expect(controller.text, '1. 第一行\n2. 第二行');

      // 切换为无序列表直接替换，不叠成 - 1.
      await _sendShortcut(tester, LogicalKeyboardKey.digit8, shift: true);
      expect(controller.text, '- 第一行\n- 第二行');

      // 切换为待办清单
      await _sendShortcut(tester, LogicalKeyboardKey.digit9, shift: true);
      expect(controller.text, '- [ ] 第一行\n- [ ] 第二行');

      // 多行缩进与取消缩进
      await _sendShortcut(tester, LogicalKeyboardKey.tab, ctrl: false);
      expect(controller.text, '  - [ ] 第一行\n  - [ ] 第二行');

      await _sendShortcut(
        tester,
        LogicalKeyboardKey.tab,
        ctrl: false,
        shift: true,
      );
      expect(controller.text, '- [ ] 第一行\n- [ ] 第二行');
    });

    testWidgets('Control+Shift+Q 引用、Control+Shift+C 代码块、Control+/ 切换预览', (
      tester,
    ) async {
      final controller = await _mountEditor(tester, text: '正文');
      controller.selection = const TextSelection.collapsed(offset: 2);

      await _sendShortcut(tester, LogicalKeyboardKey.keyQ, shift: true);
      expect(controller.text, '> 正文');

      await _sendShortcut(tester, LogicalKeyboardKey.keyC, shift: true);
      expect(controller.text, contains('```\n\n```'));

      await _sendShortcut(tester, LogicalKeyboardKey.slash);
      expect(find.byKey(const Key('markdown-preview')), findsOneWidget);

      await _sendShortcut(tester, LogicalKeyboardKey.slash);
      expect(find.byKey(const Key('worklog-content')), findsOneWidget);
    });

    testWidgets('预览模式可直接勾选待办项并回写 Markdown 源码', (tester) async {
      String? tappedHref;
      final controller = await _mountEditor(
        tester,
        text: '- [ ] 买菜\n- [x] 写日志\n\n[官网](https://www.pingvv.top)',
        onTapLink: (_, href, _) => tappedHref = href,
      );

      await tester.tap(find.byKey(const Key('markdown-preview-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
      await tester.tap(find.byKey(const Key('markdown-preview-checkbox-0')));
      await tester.pumpAndSettle();

      expect(controller.text, contains('- [x] 买菜'));
      expect(controller.text, contains('- [x] 写日志'));

      await tester.tap(find.byKey(const Key('markdown-preview-checkbox-1')));
      await tester.pumpAndSettle();
      expect(controller.text, contains('- [ ] 写日志'));
      expect(tappedHref, isNull);
    });
  });
}
