import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it } from 'vitest';
import App from './App';

describe('App 外壳', () => {
  beforeEach(() => {
    localStorage.clear();
    delete document.documentElement.dataset.theme;
  });

  it('显示标题，左上角入口图标可展开/收起侧栏', async () => {
    render(<App />);
    expect(screen.getByText('即刻日志管理后台')).toBeInTheDocument();

    const entry = screen.getByRole('button', { name: '导航' });
    expect(entry).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();

    await userEvent.click(entry);
    expect(entry).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('navigation')).toBeInTheDocument();
    expect(screen.getByText('用户管理')).toBeInTheDocument();
    expect(screen.getByText('设置')).toBeInTheDocument();
  });

  it('切换深色主题后写入 data-theme 并持久化', async () => {
    render(<App />);
    await userEvent.click(screen.getByText('深色'));
    expect(document.documentElement.dataset.theme).toBe('dark');
    expect(localStorage.getItem('jikelog.admin.theme')).toBe('dark');
  });
});
