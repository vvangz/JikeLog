import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { ApiError, toApiError } from '../api/errors';
import { createSessionClient } from './sessionClient';
import { AuthContext, type AdminProfile, type AdminSession, type Auth, type AuthStatus, type FetchResult } from './useAuth';

/** 刷新与退出接口要求的防跨站请求头。 */
const CSRF = { 'X-JikeLog-Admin': '1' as const };

interface AuthProviderProps {
  children: ReactNode;
  /** 接口基地址（测试可注入 fetch）。 */
  baseUrl?: string;
  fetch?: (input: Request) => Promise<Response>;
}

/**
 * 管理员会话（ADR-011）：Access Token 只放在内存中，Refresh Token 在 HttpOnly Cookie 里。
 * 打开页面时先用 Cookie 刷新一次，恢复登录状态。
 */
export function AuthProvider({ children, baseUrl, fetch }: AuthProviderProps) {
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [admin, setAdmin] = useState<AdminProfile | null>(null);
  const refreshing = useRef<Promise<boolean> | null>(null);

  const { client, setToken } = useMemo(() => createSessionClient({ baseUrl, fetch }), [baseUrl, fetch]);

  const apply = useCallback((s: AdminSession) => {
    setToken(s.accessToken);
    setAdmin(s.admin);
    setStatus('signedIn');
  }, [setToken]);

  const signOutLocally = useCallback(() => {
    setToken(null);
    setAdmin(null);
    setStatus('signedOut');
  }, [setToken]);

  // 同时发起的多次刷新合并为一次：Refresh Token 每次刷新都会轮换
  const refresh = useCallback((): Promise<boolean> => {
    refreshing.current ??= (async () => {
      try {
        const { data } = await client.POST('/api/admin/v1/auth/refresh', { params: { header: CSRF } });
        if (data) {
          apply(data.data);
          return true;
        }
      } catch {
        // 网络错误：按未登录处理
      }
      signOutLocally();
      return false;
    })().finally(() => {
      refreshing.current = null;
    });
    return refreshing.current;
  }, [client, apply, signOutLocally]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const login = useCallback(
    async (username: string, password: string) => {
      const { data, error, response } = await client.POST('/api/admin/v1/auth/login', {
        body: { username, password },
      });
      if (!data) throw toApiError(error, response.status);
      apply(data.data);
    },
    [client, apply],
  );

  const logout = useCallback(async () => {
    try {
      await client.POST('/api/admin/v1/auth/logout', { params: { header: CSRF } });
    } finally {
      signOutLocally();
    }
  }, [client, signOutLocally]);

  const call = useCallback(
    async <T,>(fn: () => Promise<FetchResult<T>>): Promise<T> => {
      let r = await fn();
      if (r.response.status === 401) {
        if (!(await refresh())) throw new ApiError('UNAUTHORIZED', '登录已失效，请重新登录', 401);
        r = await fn();
      }
      if (r.data === undefined) {
        const err = toApiError(r.error, r.response.status);
        if (err.code === 'PASSWORD_CHANGE_REQUIRED') {
          setAdmin((a) => (a ? { ...a, mustChangePassword: true } : a));
        }
        if (err.status === 401) signOutLocally();
        throw err;
      }
      return r.data;
    },
    [refresh, signOutLocally],
  );

  const passwordChanged = useCallback(() => {
    setAdmin((a) => (a ? { ...a, mustChangePassword: false } : a));
  }, []);

  const value = useMemo<Auth>(
    () => ({ status, admin, client, login, logout, call, passwordChanged }),
    [status, admin, client, login, logout, call, passwordChanged],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
