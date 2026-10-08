import { useCallback, useEffect, useState } from 'react';
import type { ThemeName } from './tokens.gen';
import { loadThemeMode, resolveTheme, saveThemeMode, type ThemeMode } from './themeMode';

const DARK_QUERY = '(prefers-color-scheme: dark)';

function safeLocalStorage(): Storage | undefined {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

/** 管理主题模式：持久化用户选择、监听系统深浅色变化，并同步到 <html data-theme>。 */
export function useThemeMode(): { mode: ThemeMode; resolved: ThemeName; setMode: (m: ThemeMode) => void } {
  const [mode, setModeState] = useState<ThemeMode>(() => loadThemeMode(safeLocalStorage()));
  const [prefersDark, setPrefersDark] = useState(() => window.matchMedia(DARK_QUERY).matches);

  useEffect(() => {
    const mq = window.matchMedia(DARK_QUERY);
    const onChange = (e: MediaQueryListEvent) => setPrefersDark(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  const resolved = resolveTheme(mode, prefersDark);

  useEffect(() => {
    document.documentElement.dataset.theme = resolved;
  }, [resolved]);

  const setMode = useCallback((m: ThemeMode) => {
    setModeState(m);
    saveThemeMode(m, safeLocalStorage());
  }, []);

  return { mode, resolved, setMode };
}
