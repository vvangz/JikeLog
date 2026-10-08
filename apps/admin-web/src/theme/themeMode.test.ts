import { describe, expect, it, vi } from 'vitest';
import { loadThemeMode, resolveTheme, saveThemeMode, THEME_STORAGE_KEY } from './themeMode';

const memoryStorage = (initial: Record<string, string> = {}) => {
  const data = new Map(Object.entries(initial));
  return {
    getItem: (k: string) => data.get(k) ?? null,
    setItem: (k: string, v: string) => void data.set(k, v),
  };
};

describe('resolveTheme', () => {
  it('跟随系统时按系统偏好解析', () => {
    expect(resolveTheme('system', true)).toBe('dark');
    expect(resolveTheme('system', false)).toBe('light');
  });

  it('显式选择时忽略系统偏好', () => {
    expect(resolveTheme('light', true)).toBe('light');
    expect(resolveTheme('dark', false)).toBe('dark');
  });
});

describe('loadThemeMode / saveThemeMode', () => {
  it('读写合法值', () => {
    const storage = memoryStorage();
    expect(saveThemeMode('dark', storage)).toBe(true);
    expect(loadThemeMode(storage)).toBe('dark');
  });

  it('缺失或非法值回退为跟随系统', () => {
    expect(loadThemeMode(memoryStorage())).toBe('system');
    expect(loadThemeMode(memoryStorage({ [THEME_STORAGE_KEY]: 'purple' }))).toBe('system');
  });

  it('存储不可用（隐私模式等）时不抛错', () => {
    const broken = {
      getItem: vi.fn(() => {
        throw new Error('denied');
      }),
      setItem: vi.fn(() => {
        throw new Error('denied');
      }),
    };
    expect(loadThemeMode(broken)).toBe('system');
    expect(saveThemeMode('light', broken)).toBe(false);
    expect(loadThemeMode(undefined)).toBe('system');
  });
});
