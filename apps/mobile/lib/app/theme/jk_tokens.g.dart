// GENERATED CODE - DO NOT MODIFY BY HAND
// 来源：packages/design-tokens/tokens，修改令牌后运行 `pnpm tokens` 重新生成。

import 'dart:ui';

/// 主题颜色令牌，浅色与深色两套字段完全一致。
final class JkColorTokens {
  const JkColorTokens({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.scrim,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.border,
    required this.divider,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color scrim;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color border;
  final Color divider;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  static const light = JkColorTokens(
    primary: Color(0xFF6F4E37),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEDE0D4),
    onPrimaryContainer: Color(0xFF2B1D14),
    background: Color(0xFFFAF7F2),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF2EDE6),
    scrim: Color(0x7A000000),
    textPrimary: Color(0xFF2A2420),
    textSecondary: Color(0xFF5E554D),
    textDisabled: Color(0xFFA89C8F),
    border: Color(0xFFD1C6B9),
    divider: Color(0xFFE6DED4),
    success: Color(0xFF2F7A4D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFE4F2E9),
    onSuccessContainer: Color(0xFF1E4D31),
    warning: Color(0xFF93590A),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFBF0DC),
    onWarningContainer: Color(0xFF5E3A08),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBE6E4),
    onErrorContainer: Color(0xFF6E1A15),
    info: Color(0xFF2F6596),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE3EEF8),
    onInfoContainer: Color(0xFF1D4062),
  );

  static const dark = JkColorTokens(
    primary: Color(0xFFC8A27C),
    onPrimary: Color(0xFF2B1D14),
    primaryContainer: Color(0xFF5A3E2B),
    onPrimaryContainer: Color(0xFFEDE0D4),
    background: Color(0xFF171311),
    surface: Color(0xFF221C19),
    surfaceVariant: Color(0xFF2A2420),
    scrim: Color(0xA3000000),
    textPrimary: Color(0xFFEDE6DF),
    textSecondary: Color(0xFFD1C6B9),
    textDisabled: Color(0xFF7D7267),
    border: Color(0xFF5E554D),
    divider: Color(0xFF3F3832),
    success: Color(0xFF7CC59A),
    onSuccess: Color(0xFF10301D),
    successContainer: Color(0xFF1E4D31),
    onSuccessContainer: Color(0xFFE4F2E9),
    warning: Color(0xFFE5B567),
    onWarning: Color(0xFF3A2404),
    warningContainer: Color(0xFF5E3A08),
    onWarningContainer: Color(0xFFFBF0DC),
    error: Color(0xFFF2A39C),
    onError: Color(0xFF410E0B),
    errorContainer: Color(0xFF6E1A15),
    onErrorContainer: Color(0xFFFBE6E4),
    info: Color(0xFF93BDE4),
    onInfo: Color(0xFF0F2438),
    infoContainer: Color(0xFF1D4062),
    onInfoContainer: Color(0xFFE3EEF8),
  );
}

/// 与主题无关的字体、间距、圆角、动效、断点令牌。
abstract final class JkTokens {
  static const String fontFamilyLatin = 'Space Grotesk';
  static const String fontFamilyCjk = 'MiSans';
  static const double fontSizeCaption = 12;
  static const double fontSizeBody = 14;
  static const double fontSizeBodyLarge = 16;
  static const double fontSizeTitle = 18;
  static const double fontSizeHeadline = 22;
  static const double fontSizeDisplay = 28;
  static const FontWeight fontWeightRegular = FontWeight.w400;
  static const FontWeight fontWeightMedium = FontWeight.w500;
  static const FontWeight fontWeightSemibold = FontWeight.w600;
  static const FontWeight fontWeightBold = FontWeight.w700;
  static const double fontLineHeightTight = 1.25;
  static const double fontLineHeightNormal = 1.5;
  static const double fontLineHeightRelaxed = 1.7;
  static const double spacingXxs = 2;
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 24;
  static const double spacingXxl = 32;
  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 16;
  static const double radiusFull = 999;
  static const Duration motionDurationFast = Duration(milliseconds: 120);
  static const Duration motionDurationNormal = Duration(milliseconds: 200);
  static const Duration motionDurationSlow = Duration(milliseconds: 320);
  static const double breakpointMedium = 600;
  static const double breakpointExpanded = 840;
  static const double breakpointLarge = 1200;
}
