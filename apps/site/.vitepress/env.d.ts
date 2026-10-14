/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue';
  const component: DefineComponent;
  export default component;
}

/** ICP 备案号，构建时由 SITE_ICP 注入；未备案时为空串 */
declare const __SITE_ICP__: string;
