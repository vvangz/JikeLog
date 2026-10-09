import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/theme/app_theme.dart';
import 'package:jikelog/shared/ui/jk_button.dart';
import 'package:jikelog/shared/ui/jk_form.dart';
import 'package:jikelog/shared/ui/jk_icon.dart';
import 'package:jikelog/shared/ui/jk_states.dart';

Widget _wrap(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('所有自绘图标都能绘制，并支持语义标签', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Wrap(
          children: [
            for (final i in JkIcons.values) JkIcon(i, size: 32),
            const JkIcon(JkIcons.notes, semanticLabel: '笔记'),
          ],
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.bySemanticsLabel('笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按钮：四种样式、加载中禁用', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            for (final v in JkButtonVariant.values)
              JkButton(label: v.name, variant: v, onPressed: () => taps++),
            JkButton(label: 'loading', loading: true, onPressed: () => taps++),
          ],
        ),
      ),
    );
    for (final v in JkButtonVariant.values) {
      await tester.tap(find.text(v.name));
    }
    expect(taps, 4);
    expect(find.text('loading'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(CircularProgressIndicator));
    expect(taps, 4);
    final danger = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'danger'),
    );
    expect(
      danger.style?.backgroundColor?.resolve({}),
      AppTheme.light().colorScheme.error,
    );
  });

  testWidgets('空状态、错误状态与骨架屏', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(JkErrorState(message: '网络不可用', onRetry: () => retried = true)),
    );
    expect(find.text('加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);

    await tester.pumpWidget(_wrap(const JkSkeleton(lines: 4)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);

    await tester.pumpWidget(_wrap(const JkSkeleton(), reduceMotion: true));
    final fade = tester.widget<FadeTransition>(
      find.byType(FadeTransition).last,
    );
    expect(fade.opacity.value, 0.7);
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('本地校验规则与服务端一致', () {
    expect(JkValidators.username('zhang_san'), isNull);
    expect(JkValidators.username('1abc'), isNotNull);
    expect(JkValidators.password('secret123'), isNull);
    expect(JkValidators.password('secretsecret'), isNotNull);
    expect(JkValidators.password('short1'), isNotNull);
    expect(JkValidators.password('密码abc1234'), isNull);
    expect(JkValidators.phone('+86 138-0013-8000'), isNull);
    expect(JkValidators.phone('12800138000'), isNotNull);
    expect(JkValidators.normalizePhone('+86 138-0013-8000'), '13800138000');
    expect(JkValidators.smsCode('12345'), isNotNull);
    expect(JkValidators.smsCode('123456'), isNull);
    expect(JkValidators.nickname('长' * 21), isNotNull);
    expect(JkValidators.required(' ', '用户名'), '请输入用户名');
  });
}
