import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/shared/ui/jk_logo.dart';

void main() {
  testWidgets('JkLogo 按指定尺寸绘制并跟随颜色', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: JkLogo(size: 48, color: Colors.brown)),
      ),
    );
    expect(tester.getSize(find.byType(JkLogo)), const Size(48, 48));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(JkLogo),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.painter, isA<CustomPainter>());
    expect(paint.painter!.shouldRepaint(paint.painter!), isFalse);
  });

  testWidgets('JkLogo 未指定颜色时使用主题主色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        ),
        home: const JkLogo(),
      ),
    );
    expect(find.byType(JkLogo), findsOneWidget);
  });
}
