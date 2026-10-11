import { createApiClient, type ApiClient, type ApiClientOptions } from '../api/client';

/** 带管理员令牌的接口客户端：Access Token 只保存在内存中（ADR-011）。 */
export interface SessionClient {
  client: ApiClient;
  setToken: (token: string | null) => void;
  /** 当前令牌：调用方据此判断 401 之后令牌是否已被别的请求刷新过。 */
  getToken: () => string | null;
}

export function createSessionClient(options: ApiClientOptions = {}): SessionClient {
  let token: string | null = null;
  const client = createApiClient(options);
  client.use({
    onRequest({ request }) {
      if (token) request.headers.set('Authorization', `Bearer ${token}`);
      return request;
    },
  });
  return {
    client,
    setToken: (t) => {
      token = t;
    },
    getToken: () => token,
  };
}
