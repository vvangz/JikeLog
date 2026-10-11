import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it } from 'vitest';
import App from './App';
import { adminProfile, defaultState, fakeApi, type FakeState } from './test/fakeApi';

/** Ant Design 会在两个汉字的按钮文字之间加空格。 */
const spaced = (label: string) => new RegExp(`^${label.split('').join(' ?')}$`);

function renderApp(path: string, over: Partial<FakeState> = {}) {
  const api = fakeApi({ ...defaultState(), session: true, ...over });
  render(<App initialPath={path} fetch={api.fetch} baseUrl="http://admin.test" />);
  return api;
}

describe('登录与会话', () => {
  beforeEach(() => {
    localStorage.clear();
    delete document.documentElement.dataset.theme;
  });

  it('没有有效会话时显示登录页；密码错误提示原因，正确后进入仪表盘', async () => {
    const api = renderApp('/dashboard', { session: false });
    expect(await screen.findByRole('button', { name: spaced('登录') })).toBeInTheDocument();
    const refresh = api.calls.find((c) => c.path === '/api/admin/v1/auth/refresh');
    expect(refresh?.headers.get('X-JikeLog-Admin')).toBe('1');

    await userEvent.type(screen.getByLabelText('用户名'), ' root ');
    await userEvent.type(screen.getByLabelText('密码'), 'wrong-password');
    await userEvent.click(screen.getByRole('button', { name: spaced('登录') }));
    expect(await screen.findByRole('alert')).toHaveTextContent('用户名或密码错误');
    expect(api.calls.find((c) => c.path === '/api/admin/v1/auth/login')?.body).toEqual({
      username: 'root',
      password: 'wrong-password',
    });

    await userEvent.clear(screen.getByLabelText('密码'));
    await userEvent.type(screen.getByLabelText('密码'), 'Admin12345');
    await userEvent.click(screen.getByRole('button', { name: spaced('登录') }));
    expect(await screen.findByRole('heading', { name: '仪表盘' })).toBeInTheDocument();
    expect(await screen.findByText('用户总数')).toBeInTheDocument();
  });

  it('打开页面时用 Cookie 恢复会话；Access Token 过期时自动刷新并重试', async () => {
    const api = renderApp('/dashboard');
    expect(await screen.findByText('近 30 天新增用户')).toBeInTheDocument();
    expect(screen.getByRole('listitem', { name: '2026-09-02：1 人' })).toBeInTheDocument();
    expect(screen.getByText('Android · 18 台')).toBeInTheDocument();
    expect(screen.getByText('5.0 MB')).toBeInTheDocument();
    expect(api.calls.filter((c) => c.path === '/api/admin/v1/auth/refresh')).toHaveLength(1);

    // 令牌过期：下一次请求 401，刷新一次后重试成功
    api.state.expired = true;
    await userEvent.click(screen.getByRole('button', { name: '导航' }));
    await userEvent.click(within(screen.getByRole('navigation', { name: '主导航' })).getByText('用户'));
    expect(await screen.findByText('user01')).toBeInTheDocument();
    expect(api.calls.filter((c) => c.path === '/api/admin/v1/auth/refresh')).toHaveLength(2);
  });

  it('连不上服务器时显示可重试的状态，而不是登录页', async () => {
    const api = renderApp('/dashboard', { offline: true });
    expect(await screen.findByText('无法连接服务器')).toBeInTheDocument();
    api.state.offline = false;
    await userEvent.click(screen.getByRole('button', { name: spaced('重试') }));
    expect(await screen.findByText('用户总数')).toBeInTheDocument();
  });

  it('退出请求失败时留在原页面并提示，服务器恢复后可以退出', async () => {
    const api = renderApp('/account', { failures: { '/api/admin/v1/auth/logout': [503, 'SERVICE_UNAVAILABLE', '服务暂不可用'] } });
    await userEvent.click(await screen.findByRole('button', { name: '退出登录' }));
    expect(await screen.findByText('退出失败，请重试')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: '账号' })).toBeInTheDocument();
    api.state.failures = {};
    // 加载图标的退场动画在测试环境中不会结束，按钮名前会多出 loading
    await userEvent.click(screen.getByRole('button', { name: /退出登录$/ }));
    expect(await screen.findByRole('button', { name: spaced('登录') })).toBeInTheDocument();
  });

  it('刷新也失败时回到登录页', async () => {
    const api = renderApp('/dashboard', { expired: true });
    api.state.session = false;
    expect(await screen.findByRole('button', { name: spaced('登录') })).toBeInTheDocument();
  });

  it('退出登录后回到登录页', async () => {
    const api = renderApp('/account');
    await userEvent.click(await screen.findByRole('button', { name: '退出登录' }));
    expect(await screen.findByRole('button', { name: spaced('登录') })).toBeInTheDocument();
    expect(api.calls.some((c) => c.path === '/api/admin/v1/auth/logout')).toBe(true);
  });

  it('必须修改初始密码时只能停留在账号页，改完后可以使用', async () => {
    const api = renderApp('/dashboard', { admin: adminProfile({ mustChangePassword: true, role: 'viewer' }) });
    expect(await screen.findByText(/请先修改密码再使用管理后台/)).toBeInTheDocument();
    await userEvent.type(screen.getByLabelText('当前密码'), 'wrong');
    await userEvent.type(screen.getByLabelText('新密码'), 'short');
    await userEvent.type(screen.getByLabelText('确认新密码'), 'other');
    await userEvent.click(screen.getByRole('button', { name: '修改密码' }));
    expect(await screen.findByText('密码至少 10 位')).toBeInTheDocument();
    expect(await screen.findByText('两次输入的密码不一致')).toBeInTheDocument();

    await userEvent.clear(screen.getByLabelText('新密码'));
    await userEvent.type(screen.getByLabelText('新密码'), 'NewPass2026');
    await userEvent.clear(screen.getByLabelText('确认新密码'));
    await userEvent.type(screen.getByLabelText('确认新密码'), 'NewPass2026');
    await userEvent.click(screen.getByRole('button', { name: '修改密码' }));
    expect(await screen.findByText('当前密码不正确')).toBeInTheDocument();

    await userEvent.clear(screen.getByLabelText('当前密码'));
    await userEvent.type(screen.getByLabelText('当前密码'), 'Admin12345');
    await userEvent.click(screen.getByRole('button', { name: '修改密码' }));
    await waitFor(() => expect(screen.queryByText(/请先修改密码再使用管理后台/)).not.toBeInTheDocument());
    expect(api.state.admin.mustChangePassword).toBe(false);
  }, 20_000);
});

describe('外壳与导航', () => {
  beforeEach(() => localStorage.clear());

  it('左上角入口图标展开或收起侧栏；只读管理员看不到管理员入口', async () => {
    renderApp('/dashboard', { admin: adminProfile({ role: 'viewer', username: 'viewer1' }) });
    const entry = await screen.findByRole('button', { name: '导航' });
    expect(screen.getByText('viewer1')).toBeInTheDocument();
    // 测试环境为窄屏：侧栏默认收起
    expect(entry).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(entry);
    const nav = screen.getByRole('navigation', { name: '主导航' });
    expect(within(nav).getByText('用户')).toBeInTheDocument();
    expect(within(nav).queryByText('管理员')).not.toBeInTheDocument();
    await userEvent.click(within(nav).getByText('审计日志'));
    expect(await screen.findByRole('heading', { name: '审计日志' })).toBeInTheDocument();
    // 选择后浮层自动收起
    expect(entry).toHaveAttribute('aria-expanded', 'false');
  });

  it('设置页切换深色主题并保存在本机', async () => {
    renderApp('/settings');
    await userEvent.click(await screen.findByText('深色'));
    expect(document.documentElement.dataset.theme).toBe('dark');
    expect(localStorage.getItem('jikelog.admin.theme')).toBe('dark');
  });

  it('未知路径显示 404', async () => {
    renderApp('/nowhere');
    expect(await screen.findByText('页面不存在')).toBeInTheDocument();
  });

  it('接口出错时显示原因并可重试', async () => {
    const api = renderApp('/dashboard', { failures: { '/api/admin/v1/dashboard': [500, 'INTERNAL', '服务器出错了'] } });
    expect(await screen.findByText('服务器出错了', {}, { timeout: 5000 })).toBeInTheDocument();
    api.state.failures = {};
    await userEvent.click(screen.getByRole('button', { name: spaced('重试') }));
    expect(await screen.findByText('用户总数')).toBeInTheDocument();
  });
});
