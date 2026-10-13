import '@testing-library/jest-dom/vitest';
import { cleanup, configure } from '@testing-library/react';
import { afterEach } from 'vitest';

// 未启用 vitest globals，需手动在每个用例后卸载渲染结果
afterEach(cleanup);

// CI 机器较慢，首次渲染 Ant Design 表格可能超过默认的 1 秒等待
configure({ asyncUtilTimeout: 5000 });

// jsdom 未实现 matchMedia，Ant Design 的响应式能力依赖它
if (!window.matchMedia) {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: (query: string): MediaQueryList => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }),
  });
}

// jsdom 未实现 ResizeObserver，Ant Design 的表格、菜单等组件依赖它
if (!('ResizeObserver' in window)) {
  class ResizeObserverStub {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  Object.defineProperty(window, 'ResizeObserver', { writable: true, value: ResizeObserverStub });
}
