import type { ThemeName } from './tokens.gen';

/** 用户选择的主题模式：浅色、深色或跟随系统。 */
export type ThemeMode = ThemeName | 'system';

export const THEME_MODES: readonly ThemeMode[] = ['light', 'dark', 'system'];
export const THEME_STORAGE_KEY = 'jikelog.admin.theme';

type ReadableStorage = Pick<Storage, 'getItem'>;
type WritableStorage = Pick<Storage, 'setItem'>;

const isThemeMode = (v: unknown): v is ThemeMode => THEME_MODES.includes(v as ThemeMode);

export function resolveTheme(mode: ThemeMode, prefersDark: boolean): ThemeName {
  if (mode === 'system') return prefersDark ? 'dark' : 'light';
  return mode;
}

/** 读取已保存的主题；存储不可用（隐私模式、被禁用）时回退为跟随系统。 */
export function loadThemeMode(storage: ReadableStorage | undefined): ThemeMode {
  try {
    const v = storage?.getItem(THEME_STORAGE_KEY);
    return isThemeMode(v) ? v : 'system';
  } catch {
    return 'system';
  }
}

/** 保存主题选择，返回是否成功；失败只影响下次打开时的默认值。 */
export function saveThemeMode(mode: ThemeMode, storage: WritableStorage | undefined): boolean {
  try {
    storage?.setItem(THEME_STORAGE_KEY, mode);
    return storage !== undefined;
  } catch {
    return false;
  }
}
