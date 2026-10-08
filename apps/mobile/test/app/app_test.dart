import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/app.dart';
import 'package:jikelog/app/theme/app_theme.dart';
import 'package:jikelog/app/theme/jk_tokens.g.dart';
import 'package:jikelog/app/version.dart';
import 'package:jikelog/shared/ui/jk_logo.dart';

void main() {
  testWidgets('启动后显示应用名、版本与标志', (tester) async {
    await tester.pumpWidget(const JikeLogApp());

    expect(find.text('即刻日志'), findsOneWidget);
    expect(find.textContaining(appVersion), findsOneWidget);
    expect(find.byType(JkLogo), findsWidgets);
  });

  testWidgets('themeMode 为深色时使用深色主题', (tester) async {
    await tester.pumpWidget(const JikeLogApp(themeMode: ThemeMode.dark));
    final context = tester.element(find.text('即刻日志'));

    expect(Theme.of(context).brightness, Brightness.dark);
    expect(context.jkColors.primary, JkColorTokens.dark.primary);
  });
}
