import { act, renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { useThemeMode } from './useThemeMode';

type Listener = (e: MediaQueryListEvent) => void;

function mockMatchMedia(initialDark: boolean) {
  const listeners = new Set<Listener>();
  const mq = {
    matches: initialDark,
    addEventListener: (_: string, l: Listener) => listeners.add(l),
    removeEventListener: (_: string, l: Listener) => listeners.delete(l),
  };
  vi.spyOn(window, 'matchMedia').mockReturnValue(mq as unknown as MediaQueryList);
  return {
    listeners,
    emit: (matches: boolean) => listeners.forEach((l) => l({ matches } as MediaQueryListEvent)),
  };
}

describe('useThemeMode', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    localStorage.clear();
  });

  it('跟随系统时响应系统深浅色变化，并在卸载时移除监听', () => {
    const media = mockMatchMedia(false);
    const { result, unmount } = renderHook(() => useThemeMode());
    expect(result.current.resolved).toBe('light');

    act(() => media.emit(true));
    expect(result.current.resolved).toBe('dark');
    expect(document.documentElement.dataset.theme).toBe('dark');

    unmount();
    expect(media.listeners.size).toBe(0);
  });

  it('localStorage 访问抛错时仍可工作', () => {
    mockMatchMedia(false);
    vi.spyOn(window, 'localStorage', 'get').mockImplementation(() => {
      throw new Error('SecurityError');
    });
    const { result } = renderHook(() => useThemeMode());
    expect(result.current.mode).toBe('system');
    act(() => result.current.setMode('dark'));
    expect(result.current.resolved).toBe('dark');
  });
});
