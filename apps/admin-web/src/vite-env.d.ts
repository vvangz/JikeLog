/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** 接口基地址，留空时走同源（开发环境由 Vite 代理到 Go 服务）。 */
  readonly VITE_API_BASE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
