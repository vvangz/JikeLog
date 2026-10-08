import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/theme/app_theme.dart';
import 'package:jikelog/app/theme/jk_tokens.g.dart';

void main() {
  group('AppTheme', () {
    test('浅色主题使用咖色主色与奶油白背景', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, JkColorTokens.light.primary);
      expect(theme.colorScheme.onPrimary, JkColorTokens.light.onPrimary);
      expect(theme.scaffoldBackgroundColor, JkColorTokens.light.background);
      expect(theme.colorScheme.surface, JkColorTokens.light.surface);
      expect(theme.colorScheme.error, JkColorTokens.light.error);
    });

    test('深色主题使用深色令牌', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, JkColorTokens.dark.primary);
      expect(theme.scaffoldBackgroundColor, JkColorTokens.dark.background);
      expect(theme.colorScheme.onSurface, JkColorTokens.dark.textPrimary);
    });

    test('字体为 Space Grotesk，中文回退到 MiSans', () {
      final body = AppTheme.light().textTheme.bodyMedium!;
      expect(body.fontFamily, JkTokens.fontFamilyLatin);
      expect(body.fontFamilyFallback, contains(JkTokens.fontFamilyCjk));
      expect(body.fontSize, JkTokens.fontSizeBody);
    });

    test('主题实例被缓存，重复调用返回同一对象', () {
      expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
      expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
    });

    test('选中指示器等使用浅色容器而非实心主色', () {
      final scheme = AppTheme.light().colorScheme;
      expect(scheme.secondaryContainer, JkColorTokens.light.primaryContainer);
      expect(scheme.tertiary, JkColorTokens.light.info);
    });

    test('通过 ThemeExtension 暴露完整颜色令牌', () {
      final ext = AppTheme.dark().extension<JkColors>();
      expect(ext, isNotNull);
      expect(ext!.tokens.success, JkColorTokens.dark.success);
    });
  });

  group('JkColors', () {
    const light = JkColors(JkColorTokens.light);
    const dark = JkColors(JkColorTokens.dark);

    test('copyWith 返回新实例且不修改原对象', () {
      final copy = light.copyWith(tokens: JkColorTokens.dark);
      expect(copy.tokens, same(JkColorTokens.dark));
      expect(light.tokens, same(JkColorTokens.light));
      expect(light.copyWith().tokens, same(JkColorTokens.light));
    });

    test('相等性基于令牌实例', () {
      expect(light, const JkColors(JkColorTokens.light));
      expect(light, isNot(dark));
      expect(light.hashCode, const JkColors(JkColorTokens.light).hashCode);
    });

    test('lerp 在中点切换', () {
      expect(light.lerp(dark, 0.4).tokens, same(JkColorTokens.light));
      expect(light.lerp(dark, 0.6).tokens, same(JkColorTokens.dark));
      expect(light.lerp(null, 0.9).tokens, same(JkColorTokens.light));
    });
  });
}
