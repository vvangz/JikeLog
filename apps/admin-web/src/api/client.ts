import createClient from 'openapi-fetch';
import type { paths } from './schema.gen';

export interface ApiClientOptions {
  /** 接口基地址，默认取 VITE_API_BASE_URL，留空为同源。 */
  baseUrl?: string;
  /** 便于测试注入的 fetch 实现。 */
  fetch?: (input: Request) => Promise<Response>;
}

/** 创建与 server/api/openapi.yaml 类型一致的接口客户端。 */
export function createApiClient(options: ApiClientOptions = {}) {
  return createClient<paths>({
    baseUrl: options.baseUrl ?? import.meta.env.VITE_API_BASE_URL ?? '',
    ...(options.fetch ? { fetch: options.fetch } : {}),
  });
}

export type ApiClient = ReturnType<typeof createApiClient>;
