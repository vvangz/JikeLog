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
    primary: Color(0xFF334AC0),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE0E7FF),
    onPrimaryContainer: Color(0xFF131E54),
    background: Color(0xFFF6F8FC),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFECF0F7),
    scrim: Color(0x7A000000),
    textPrimary: Color(0xFF1E2636),
    textSecondary: Color(0xFF4F5B70),
    textDisabled: Color(0xFF8E9BB0),
    border: Color(0xFFC5D0E0),
    divider: Color(0xFFDFE6F0),
    success: Color(0xFF1E7A4C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFE3F5EC),
    onSuccessContainer: Color(0xFF145032),
    warning: Color(0xFF9A5B08),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFDF3DF),
    onWarningContainer: Color(0xFF613A05),
    error: Color(0xFFBE2B25),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFCE8E7),
    onErrorContainer: Color(0xFF751916),
    info: Color(0xFF1B6B8A),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE2F2F7),
    onInfoContainer: Color(0xFF114459),
  );

  static const dark = JkColorTokens(
    primary: Color(0xFF8FA8FF),
    onPrimary: Color(0xFF131E54),
    primaryContainer: Color(0xFF263999),
    onPrimaryContainer: Color(0xFFE0E7FF),
    background: Color(0xFF0F141F),
    surface: Color(0xFF161D2B),
    surfaceVariant: Color(0xFF1E2636),
    scrim: Color(0xA3000000),
    textPrimary: Color(0xFFE8EEF7),
    textSecondary: Color(0xFFC5D0E0),
    textDisabled: Color(0xFF6B788E),
    border: Color(0xFF4F5B70),
    divider: Color(0xFF2D3648),
    success: Color(0xFF6FD0A0),
    onSuccess: Color(0xFF0B2D1C),
    successContainer: Color(0xFF145032),
    onSuccessContainer: Color(0xFFE3F5EC),
    warning: Color(0xFFECC06B),
    onWarning: Color(0xFF382103),
    warningContainer: Color(0xFF613A05),
    onWarningContainer: Color(0xFFFDF3DF),
    error: Color(0xFFF49E97),
    onError: Color(0xFF450D0B),
    errorContainer: Color(0xFF751916),
    onErrorContainer: Color(0xFFFCE8E7),
    info: Color(0xFF7CC6DF),
    onInfo: Color(0xFF092633),
    infoContainer: Color(0xFF114459),
    onInfoContainer: Color(0xFFE2F2F7),
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
