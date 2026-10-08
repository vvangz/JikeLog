import { theme, type ThemeConfig } from 'antd';
import { colors, tokens, type ThemeName } from './tokens.gen';

const FONT_FAMILY = `'${tokens.font.family.latin}', '${tokens.font.family.cjk}', -apple-system, 'Segoe UI', sans-serif`;

/** 把设计令牌映射为 Ant Design 主题配置。 */
export function buildAntdTheme(mode: ThemeName): ThemeConfig {
  const c = colors[mode];
  return {
    algorithm: mode === 'dark' ? theme.darkAlgorithm : theme.defaultAlgorithm,
    token: {
      colorPrimary: c.primary,
      colorSuccess: c.success,
      colorWarning: c.warning,
      colorError: c.error,
      colorInfo: c.info,
      colorBgLayout: c.background,
      colorBgContainer: c.surface,
      colorBgElevated: c.surface,
      colorText: c.textPrimary,
      colorTextSecondary: c.textSecondary,
      colorTextDisabled: c.textDisabled,
      colorBorder: c.border,
      colorSplit: c.divider,
      colorBgMask: c.scrim,
      fontFamily: FONT_FAMILY,
      fontSize: tokens.font.size.body,
      borderRadius: tokens.radius.md,
      borderRadiusSM: tokens.radius.sm,
      borderRadiusLG: tokens.radius.lg,
      motionDurationMid: `${tokens.motion.duration.normal / 1000}s`,
      motionDurationSlow: `${tokens.motion.duration.slow / 1000}s`,
    },
  };
}
