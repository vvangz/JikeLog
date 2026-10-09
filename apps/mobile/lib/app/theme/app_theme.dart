import 'package:flutter/material.dart';

import 'jk_tokens.g.dart';

/// 通过 ThemeExtension 暴露 Material ColorScheme 之外的令牌（成功/警告/信息色等）。
@immutable
class JkColors extends ThemeExtension<JkColors> {
  const JkColors(this.tokens);

  final JkColorTokens tokens;

  @override
  JkColors copyWith({JkColorTokens? tokens}) => JkColors(tokens ?? this.tokens);

  /// 主题切换时在中点整体切换，不做逐色插值。
  @override
  JkColors lerp(JkColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension JkThemeContext on BuildContext {
  /// 当前主题的完整颜色令牌。
  JkColorTokens get jkColors {
    final ext = Theme.of(this).extension<JkColors>();
    assert(ext != null, '当前主题缺少 JkColors 扩展，请使用 AppTheme.light()/dark()');
    return ext!.tokens;
  }
}

/// 即刻日志浅色/深色主题，全部取值来自设计令牌。
abstract final class AppTheme {
  // 主题只构建一次，避免每次重建 MaterialApp 都生成不相等的 ThemeData 引发全量重建
  static final ThemeData _light = _build(JkColorTokens.light, Brightness.light);
  static final ThemeData _dark = _build(JkColorTokens.dark, Brightness.dark);

  static ThemeData light() => _light;

  static ThemeData dark() => _dark;

  static ThemeData _build(JkColorTokens c, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: _scheme(c, brightness),
      scaffoldBackgroundColor: c.background,
      dividerColor: c.divider,
      fontFamily: JkTokens.fontFamilyLatin,
      fontFamilyFallback: const [JkTokens.fontFamilyCjk],
      extensions: [JkColors(c)],
    );
    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      // 顶栏与页面同色（奶油白 / 深咖黑），滚动时不叠加主色色调
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ColorScheme _scheme(JkColorTokens c, Brightness brightness) =>
      ColorScheme(
        brightness: brightness,
        primary: c.primary,
        onPrimary: c.onPrimary,
        primaryContainer: c.primaryContainer,
        onPrimaryContainer: c.onPrimaryContainer,
        secondary: c.primary,
        onSecondary: c.onPrimary,
        // 选中指示器、Chip、Tonal 按钮等使用浅色容器，而不是实心主色
        secondaryContainer: c.primaryContainer,
        onSecondaryContainer: c.onPrimaryContainer,
        tertiary: c.info,
        onTertiary: c.onInfo,
        tertiaryContainer: c.infoContainer,
        onTertiaryContainer: c.onInfoContainer,
        error: c.error,
        onError: c.onError,
        errorContainer: c.errorContainer,
        onErrorContainer: c.onErrorContainer,
        surface: c.surface,
        onSurface: c.textPrimary,
        onSurfaceVariant: c.textSecondary,
        surfaceContainerHighest: c.surfaceVariant,
        outline: c.border,
        outlineVariant: c.divider,
        scrim: c.scrim,
      );

  static TextTheme _textTheme(TextTheme t) => t.copyWith(
    displaySmall: t.displaySmall?.copyWith(
      fontSize: JkTokens.fontSizeDisplay,
      fontWeight: JkTokens.fontWeightSemibold,
    ),
    headlineSmall: t.headlineSmall?.copyWith(
      fontSize: JkTokens.fontSizeHeadline,
      fontWeight: JkTokens.fontWeightSemibold,
    ),
    titleLarge: t.titleLarge?.copyWith(
      fontSize: JkTokens.fontSizeTitle,
      fontWeight: JkTokens.fontWeightSemibold,
    ),
    titleMedium: t.titleMedium?.copyWith(
      fontSize: JkTokens.fontSizeBodyLarge,
      fontWeight: JkTokens.fontWeightMedium,
    ),
    bodyLarge: t.bodyLarge?.copyWith(fontSize: JkTokens.fontSizeBodyLarge),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: JkTokens.fontSizeBody),
    bodySmall: t.bodySmall?.copyWith(fontSize: JkTokens.fontSizeCaption),
    labelSmall: t.labelSmall?.copyWith(fontSize: JkTokens.fontSizeCaption),
  );
}
