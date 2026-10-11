import { useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { ApiError, toApiError } from '../api/errors';
import { createSessionClient } from './sessionClient';
import { AuthContext, type AdminProfile, type AdminSession, type Auth, type AuthStatus, type FetchResult } from './useAuth';

/** 刷新与退出接口要求的防跨站请求头。 */
const CSRF = { 'X-JikeLog-Admin': '1' as const };

/** 刷新的结果：成功、会话已失效（需要重新登录）、暂时失败（网络或服务端错误，会话可能仍有效）。 */
type RefreshResult = 'ok' | 'unauthorized' | 'error';

const networkError = () => new ApiError('NETWORK', '无法连接服务器，请检查网络', 0);

interface AuthProviderProps {
  children: ReactNode;
  /** 接口基地址（测试可注入 fetch）。 */
  baseUrl?: string;
  fetch?: (input: Request) => Promise<Response>;
}

/**
 * 管理员会话（ADR-011）：Access Token 只放在内存中，Refresh Token 在 HttpOnly Cookie 里。
 * 打开页面时先用 Cookie 刷新一次，恢复登录状态。须在 QueryClientProvider 之内使用：退出时清空缓存的数据。
 */
export function AuthProvider({ children, baseUrl, fetch }: AuthProviderProps) {
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [admin, setAdmin] = useState<AdminProfile | null>(null);
  const refreshing = useRef<Promise<RefreshResult> | null>(null);
  // 会话代次：登录或退出后加一，丢弃此前发出、此后才返回的刷新结果（避免退出后又被"刷新"回来）
  const epoch = useRef(0);

  const { client, setToken, getToken } = useMemo(() => createSessionClient({ baseUrl, fetch }), [baseUrl, fetch]);

  const apply = useCallback(
    (s: AdminSession) => {
      setToken(s.accessToken);
      setAdmin(s.admin);
      setStatus('signedIn');
    },
    [setToken],
  );

  // 退出或会话失效：清空令牌与缓存的数据，下一位登录的管理员看不到上一位的数据
  const signOutLocally = useCallback(() => {
    epoch.current++;
    setToken(null);
    setAdmin(null);
    setStatus('signedOut');
    queryClient.clear();
  }, [setToken, queryClient]);

  // 同时发起的多次刷新合并为一次：Refresh Token 每次刷新都会轮换
  const refresh = useCallback((): Promise<RefreshResult> => {
    refreshing.current ??= (async (): Promise<RefreshResult> => {
      const started = epoch.current;
      try {
        const { data, response } = await client.POST('/api/admin/v1/auth/refresh', { params: { header: CSRF } });
        if (started !== epoch.current) return 'error';
        if (data) {
          apply(data.data);
          return 'ok';
        }
        if (response.status === 401 || response.status === 403) {
          signOutLocally();
          return 'unauthorized';
        }
      } catch {
        // 网络错误：会话可能仍然有效，不当作已退出
      }
      return 'error';
    })().finally(() => {
      refreshing.current = null;
    });
    return refreshing.current;
  }, [client, apply, signOutLocally]);

  // 打开页面时恢复会话；连不上服务器时显示可重试的状态，而不是登录页
  const restore = useCallback(() => {
    setStatus('loading');
    void refresh().then((r) => {
      if (r === 'error') setStatus((s) => (s === 'loading' ? 'offline' : s));
    });
  }, [refresh]);

  useEffect(() => {
    void refresh().then((r) => {
      if (r === 'error') setStatus((s) => (s === 'loading' ? 'offline' : s));
    });
  }, [refresh]);

  const login = useCallback(
    async (username: string, password: string) => {
      const { data, error, response } = await client.POST('/api/admin/v1/auth/login', {
        body: { username, password },
      });
      if (!data) throw toApiError(error, response.status);
      epoch.current++;
      queryClient.clear();
      apply(data.data);
    },
    [client, apply, queryClient],
  );

  // 退出：服务端确认（或会话本已失效）后才回到登录页；请求失败时 Cookie 仍有效，提示重试
  const logout = useCallback(async () => {
    let status: number;
    try {
      status = (await client.POST('/api/admin/v1/auth/logout', { params: { header: CSRF } })).response.status;
    } catch {
      throw networkError();
    }
    if (status >= 500) throw new ApiError('UNEXPECTED', '退出失败，请重试', status);
    signOutLocally();
  }, [client, signOutLocally]);

  const send = useCallback(async <T,>(fn: () => Promise<FetchResult<T>>): Promise<FetchResult<T>> => {
    try {
      return await fn();
    } catch {
      throw networkError();
    }
  }, []);

  const call = useCallback(
    async <T,>(fn: () => Promise<FetchResult<T>>): Promise<T> => {
      const used = getToken();
      let r = await send(fn);
      if (r.response.status === 401) {
        // 别的请求已经刷新过令牌：直接重试，不再轮换一次
        if (getToken() === used) {
          const result = await refresh();
          if (result === 'unauthorized') throw new ApiError('UNAUTHORIZED', '登录已失效，请重新登录', 401);
          if (result === 'error') throw networkError();
        }
        r = await send(fn);
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
    [getToken, send, refresh, signOutLocally],
  );

  const passwordChanged = useCallback(() => {
    setAdmin((a) => (a ? { ...a, mustChangePassword: false } : a));
  }, []);

  const value = useMemo<Auth>(
    () => ({ status, admin, client, login, logout, call, passwordChanged, retry: restore }),
    [status, admin, client, login, logout, call, passwordChanged, restore],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
