import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it } from 'vitest';
import App from '../App';
import { defaultState, fakeApi, type FakeState } from '../test/fakeApi';

const spaced = (label: string) => new RegExp(`^${label.split('').join(' ?')}$`);

function renderApp(path: string, over: Partial<FakeState> = {}) {
  const api = fakeApi({ ...defaultState(), session: true, ...over });
  render(<App initialPath={path} fetch={api.fetch} baseUrl="http://admin.test" />);
  return api;
}

beforeEach(() => localStorage.clear());

describe('用户', () => {
  it('列表分页、按手机号末尾搜索，点击用户名打开详情', async () => {
    const api = renderApp('/users');
    expect(await screen.findByText('user01')).toBeInTheDocument();
    expect(screen.getByText('+86 138****5678')).toBeInTheDocument();
    expect(screen.getByText('共 25 位用户')).toBeInTheDocument();

    await userEvent.click(screen.getByTitle('2'));
    expect(await screen.findByText('user21')).toBeInTheDocument();
    expect(api.calls.at(-1)?.query.get('page')).toBe('2');

    await userEvent.type(screen.getByLabelText('搜索用户'), '5678{Enter}');
    await waitFor(() => expect(screen.queryByText('user21')).not.toBeInTheDocument());
    expect(api.calls.at(-1)?.query.get('q')).toBe('5678');
    expect(api.calls.at(-1)?.query.get('page')).toBe('1');

    await userEvent.click(screen.getByRole('link', { name: 'user01' }));
    expect(await screen.findByRole('heading', { name: '用户详情' })).toBeInTheDocument();
  });

  it('详情只显示配置：设置、同步、存储与设备', async () => {
    const s = defaultState();
    renderApp(`/users/${s.detail.user.id}`);
    expect(await screen.findByText('深色')).toBeInTheDocument();
    expect(screen.getByText('120%')).toBeInTheDocument();
    expect(screen.getByText('周日')).toBeInTheDocument();
    expect(screen.getByText('准时')).toBeInTheDocument();
    expect(screen.getByText('提前 15 分钟')).toBeInTheDocument();
    expect(screen.getByText('1.0 MB / 2.0 GB')).toBeInTheDocument();
    expect(screen.getByText('Pixel 9')).toBeInTheDocument();
    expect(screen.getByText('已同步')).toBeInTheDocument();
    expect(screen.getByText('落后 6')).toBeInTheDocument();
    expect(screen.getByText('已退出')).toBeInTheDocument();
    expect(screen.getByText(/看不到工作日志、笔记、备忘录和记账的任何内容/)).toBeInTheDocument();
  });

  it('用户不存在时显示原因', async () => {
    renderApp('/users/00000000-0000-7000-8000-00000000ffff');
    expect(await screen.findByText('对象不存在')).toBeInTheDocument();
  });
});

describe('审计日志', () => {
  it('显示操作、对象与说明，可按操作筛选', async () => {
    const api = renderApp('/audit');
    expect(await screen.findByText('登录失败')).toBeInTheDocument();
    expect(screen.getByText('原因：密码错误')).toBeInTheDocument();
    expect(screen.getByText(/^user 0000/)).toBeInTheDocument();

    await userEvent.click(screen.getByLabelText('操作'));
    await userEvent.click(await screen.findByTitle('查看用户详情'));
    await waitFor(() => expect(api.calls.at(-1)?.query.get('action')).toBe('view_user'));
    await waitFor(() => expect(screen.queryByText('原因：密码错误')).not.toBeInTheDocument());
  });
});

describe('管理员', () => {
  it('新建管理员、修改角色、停用、重置密码', async () => {
    const api = renderApp('/admins');
    expect(await screen.findByText('viewer1')).toBeInTheDocument();
    expect(screen.getByText('当前账号')).toBeInTheDocument();

    // 新建：校验用户名与密码
    await userEvent.click(screen.getByRole('button', { name: /新建管理员/ }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByLabelText('用户名'), '1bad');
    await userEvent.type(within(dialog).getByLabelText('初始密码'), 'onlyletters');
    await userEvent.click(within(dialog).getByRole('button', { name: spaced('新建') }));
    expect(await within(dialog).findByText('4–20 位字母、数字或下划线，以字母开头')).toBeInTheDocument();
    expect(await within(dialog).findByText('密码需要同时包含字母和数字')).toBeInTheDocument();
    await userEvent.clear(within(dialog).getByLabelText('用户名'));
    await userEvent.type(within(dialog).getByLabelText('用户名'), 'auditor');
    await userEvent.clear(within(dialog).getByLabelText('初始密码'));
    await userEvent.type(within(dialog).getByLabelText('初始密码'), 'Auditor2026');
    await userEvent.click(within(dialog).getByRole('button', { name: spaced('新建') }));
    expect(await screen.findByText('auditor')).toBeInTheDocument();
    expect(api.calls.find((c) => c.method === 'POST' && c.path === '/api/admin/v1/admins')?.body).toEqual({
      username: 'auditor',
      role: 'viewer',
      password: 'Auditor2026',
    });
    expect(screen.getAllByText('待修改初始密码').length).toBeGreaterThan(0);

    // 修改角色
    await userEvent.click(screen.getByLabelText('viewer1 的角色'));
    await userEvent.click((await screen.findAllByTitle('超级管理员')).at(-1)!);
    await waitFor(() =>
      expect(api.calls.find((c) => c.method === 'PATCH')?.body).toEqual({ role: 'super_admin' }),
    );

    // 停用需要确认
    const row = screen.getByText('viewer1').closest('tr')!;
    await userEvent.click(within(row).getByRole('button', { name: spaced('停用') }));
    const titles = await screen.findAllByText('停用 viewer1？');
    const confirm = titles.map((t) => t.closest<HTMLElement>('.ant-modal')).find(Boolean)!;
    await userEvent.click(within(confirm).getByRole('button', { name: spaced('停用') }));
    expect(await screen.findByText('已停用')).toBeInTheDocument();

    // 重置密码
    await userEvent.click(within(screen.getByText('viewer1').closest('tr')!).getByRole('button', { name: '重置密码' }));
    const reset = (await screen.findAllByText('重置 viewer1 的密码'))
      .map((t) => t.closest<HTMLElement>('.ant-modal'))
      .find(Boolean)!;
    await userEvent.type(within(reset).getByLabelText('新密码'), 'Reset2026ab');
    await userEvent.click(within(reset).getByRole('button', { name: spaced('重置') }));
    await waitFor(() =>
      expect(api.calls.some((c) => c.path.endsWith('/password') && c.method === 'POST')).toBe(true),
    );
  }, 30_000);

  it('服务端拒绝时提示原因', async () => {
    renderApp('/admins', { failures: { '/api/admin/v1/admins/00000000-0000-7000-8000-000000000002': [409, 'LAST_SUPER_ADMIN', '至少要保留一个启用的超级管理员'] } });
    await userEvent.click(await screen.findByLabelText('viewer1 的角色'));
    await userEvent.click((await screen.findAllByTitle('超级管理员')).at(-1)!);
    expect(await screen.findByText('至少要保留一个启用的超级管理员')).toBeInTheDocument();
  });

  it('只读管理员直接打开管理员页时提示没有权限', async () => {
    const s = defaultState();
    renderApp('/admins', { admin: { ...s.admin, role: 'viewer' } });
    expect(await screen.findByText('只有超级管理员可以管理管理员账号。')).toBeInTheDocument();
  });
});
