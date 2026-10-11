import { createContext, useContext } from 'react';
import type { ApiClient } from '../api/client';
import type { components } from '../api/schema.gen';

export type AdminProfile = components['schemas']['AdminProfile'];
export type AdminSession = components['schemas']['AdminSession'];

/** loading 恢复会话中 / signedOut 未登录 / signedIn 已登录 / offline 连不上服务器（会话可能仍有效）。 */
export type AuthStatus = 'loading' | 'signedOut' | 'signedIn' | 'offline';

/** 一次接口调用的结果（openapi-fetch 的返回值）。 */
export interface FetchResult<T> {
  data?: T;
  error?: unknown;
  response: Response;
}

export interface Auth {
  status: AuthStatus;
  admin: AdminProfile | null;
  /** 带管理员令牌的接口客户端。 */
  client: ApiClient;
  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  /**
   * 调用接口并取出 data：Access Token 过期（401）时先刷新再重试一次；刷新失败则回到登录页。
   * 必须修改初始密码（403 PASSWORD_CHANGE_REQUIRED）时标记管理员状态，界面随之跳到改密码页。
   */
  call: <T>(fn: () => Promise<FetchResult<T>>) => Promise<T>;
  /** 修改密码成功后更新管理员状态（不再要求改密码）。 */
  passwordChanged: () => void;
  /** 连不上服务器时重新尝试恢复会话。 */
  retry: () => void;
}

export const AuthContext = createContext<Auth | null>(null);

/** 当前管理员会话。 */
export function useAuth(): Auth {
  const auth = useContext(AuthContext);
  if (!auth) throw new Error('useAuth 需要在 AuthProvider 内使用');
  return auth;
}
