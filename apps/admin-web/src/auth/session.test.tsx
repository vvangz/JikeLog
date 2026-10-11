import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { StrictMode, useState } from 'react';
import { describe, expect, it } from 'vitest';
import { errorMessage } from '../api/errors';
import { defaultState, fakeApi, type FakeState } from '../test/fakeApi';
import { AuthProvider } from './session';
import { useAuth } from './useAuth';

function Probe() {
  const { status, client, call, logout } = useAuth();
  const [result, setResult] = useState('');
  const two = async () => {
    try {
      await Promise.all([
        call(() => client.GET('/api/admin/v1/dashboard')),
        call(() => client.GET('/api/admin/v1/me')),
      ]);
      setResult('两个请求都成功');
    } catch (e) {
      setResult(errorMessage(e));
    }
  };
  return (
    <div>
      <p>状态：{status}</p>
      <p>{result}</p>
      <button onClick={() => void two()}>并发请求</button>
      <button onClick={() => void logout().catch(() => undefined)}>退出</button>
    </div>
  );
}

function renderProbe(over: Partial<FakeState> = {}) {
  const api = fakeApi({ ...defaultState(), session: true, ...over });
  render(
    <StrictMode>
      <QueryClientProvider client={new QueryClient()}>
        <AuthProvider fetch={api.fetch} baseUrl="http://admin.test">
          <Probe />
        </AuthProvider>
      </QueryClientProvider>
    </StrictMode>,
  );
  return api;
}

const refreshes = (api: ReturnType<typeof fakeApi>) =>
  api.calls.filter((c) => c.path === '/api/admin/v1/auth/refresh').length;

describe('会话', () => {
  it('StrictMode 下打开页面只刷新一次；同时过期的多个请求只再刷新一次', async () => {
    const api = renderProbe();
    expect(await screen.findByText('状态：signedIn')).toBeInTheDocument();
    expect(refreshes(api)).toBe(1);

    api.state.expired = true;
    await userEvent.click(screen.getByRole('button', { name: '并发请求' }));
    expect(await screen.findByText('两个请求都成功')).toBeInTheDocument();
    expect(refreshes(api)).toBe(2);
  });

  it('请求时网络中断：提示连接失败，不当作已退出', async () => {
    const api = renderProbe();
    expect(await screen.findByText('状态：signedIn')).toBeInTheDocument();
    api.state.offline = true;
    await userEvent.click(screen.getByRole('button', { name: '并发请求' }));
    expect(await screen.findByText('无法连接服务器，请检查网络')).toBeInTheDocument();
    expect(screen.getByText('状态：signedIn')).toBeInTheDocument();
  });

  it('退出后，退出前发出的刷新即使晚到也不会恢复登录', async () => {
    let release: () => void = () => undefined;
    const gate = new Promise<void>((r) => {
      release = r;
    });
    const api = fakeApi({ ...defaultState(), session: true });
    const slow = async (req: Request) => {
      if (new URL(req.url).pathname === '/api/admin/v1/auth/refresh') await gate;
      return api.fetch(req);
    };
    render(
      <QueryClientProvider client={new QueryClient()}>
        <AuthProvider fetch={slow} baseUrl="http://admin.test">
          <Probe />
        </AuthProvider>
      </QueryClientProvider>,
    );
    await userEvent.click(screen.getByRole('button', { name: '退出' }));
    expect(await screen.findByText('状态：signedOut')).toBeInTheDocument();
    release();
    await waitFor(() => expect(refreshes(api)).toBe(1));
    await new Promise((r) => setTimeout(r, 20));
    expect(screen.getByText('状态：signedOut')).toBeInTheDocument();
  });
});
