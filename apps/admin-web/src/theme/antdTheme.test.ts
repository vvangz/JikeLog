import { theme } from 'antd';
import { describe, expect, it } from 'vitest';
import { buildAntdTheme } from './antdTheme';
import { colors, tokens } from './tokens.gen';

describe('buildAntdTheme', () => {
  it('浅色主题使用设计令牌中的咖色主色与默认算法', () => {
    const cfg = buildAntdTheme('light');
    expect(cfg.token?.colorPrimary).toBe(colors.light.primary);
    expect(cfg.token?.colorBgLayout).toBe(colors.light.background);
    expect(cfg.algorithm).toBe(theme.defaultAlgorithm);
  });

  it('深色主题使用深色令牌与暗色算法', () => {
    const cfg = buildAntdTheme('dark');
    expect(cfg.token?.colorPrimary).toBe(colors.dark.primary);
    expect(cfg.token?.colorBgContainer).toBe(colors.dark.surface);
    expect(cfg.algorithm).toBe(theme.darkAlgorithm);
  });

  it('字体为 Space Grotesk + MiSans，圆角与字号取自令牌', () => {
    const cfg = buildAntdTheme('light');
    expect(cfg.token?.fontFamily).toMatch(/^'Space Grotesk', 'MiSans'/);
    expect(cfg.token?.borderRadius).toBe(tokens.radius.md);
    expect(cfg.token?.fontSize).toBe(tokens.font.size.body);
  });

  it('状态色全部映射', () => {
    const t = buildAntdTheme('light').token;
    expect([t?.colorSuccess, t?.colorWarning, t?.colorError, t?.colorInfo]).toEqual([
      colors.light.success,
      colors.light.warning,
      colors.light.error,
      colors.light.info,
    ]);
  });
});
