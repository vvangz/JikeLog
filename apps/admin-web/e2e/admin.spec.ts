import { expect, test } from '@playwright/test';
import { mockApi } from './mockApi';

test('登录 → 仪表盘 → 用户列表 → 用户详情 → 审计日志 → 退出', async ({ page }) => {
  const api = await mockApi(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '即刻日志管理后台' })).toBeVisible();

  await page.getByLabel('用户名').fill('root');
  await page.getByLabel('密码').fill('wrong-password');
  await page.getByRole('button', { name: /登\s?录/ }).click();
  await expect(page.getByRole('alert')).toContainText('用户名或密码错误');

  await page.getByLabel('密码').fill('Admin12345');
  await page.getByRole('button', { name: /登\s?录/ }).click();
  await expect(page.getByRole('heading', { name: '仪表盘' })).toBeVisible();
  await expect(page.getByText('用户总数')).toBeVisible();
  await expect(page).toHaveURL(/\/dashboard$/);

  await page.getByRole('navigation', { name: '主导航' }).getByText('用户').click();
  await expect(page.getByRole('heading', { name: '用户' })).toBeVisible();
  await page.getByLabel('搜索用户').fill('5678');
  await page.getByLabel('搜索用户').press('Enter');
  await expect(page).toHaveURL(/q=5678/);
  await expect(page.getByText('+86 138****5678')).toBeVisible();
  await page.getByRole('link', { name: 'user01' }).click();

  await expect(page.getByRole('heading', { name: '用户详情' })).toBeVisible();
  await expect(page.getByText('Pixel 9')).toBeVisible();
  await expect(page.getByText(/看不到工作日志、笔记、备忘录和记账的任何内容/)).toBeVisible();

  await page.getByRole('navigation', { name: '主导航' }).getByText('审计日志').click();
  await expect(page.getByText('登录失败')).toBeVisible();

  // 刷新页面后用 Cookie 恢复会话（不需要重新登录）
  await page.reload();
  await expect(page.getByRole('heading', { name: '审计日志' })).toBeVisible();

  await page.getByRole('navigation', { name: '主导航' }).getByText('账号').click();
  await page.getByRole('button', { name: '退出登录' }).click();
  await expect(page.getByRole('button', { name: /登\s?录/ })).toBeVisible();
  expect(api.calls.some((c) => c.path === '/api/admin/v1/auth/logout')).toBe(true);
});

test('超级管理员新建只读管理员', async ({ page }) => {
  await mockApi(page, { session: true });
  await page.goto('/admins');
  await page.getByRole('button', { name: '新建管理员' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('用户名').fill('auditor');
  await dialog.getByLabel('初始密码').fill('Auditor2026');
  await dialog.getByRole('button', { name: /新\s?建/ }).click();
  await expect(page.getByRole('cell', { name: 'auditor' })).toBeVisible();
});

test('宽屏：点击左上角图标，侧栏向右展开或收起（有过渡动画）', async ({ page }) => {
  await mockApi(page, { session: true });
  await page.goto('/dashboard');
  const toggle = page.getByRole('button', { name: '导航' });
  const rail = page.locator('[data-open]');
  const width = () => rail.evaluate((el) => el.getBoundingClientRect().width);
  await expect(page.getByRole('navigation', { name: '主导航' })).toBeVisible();
  expect(await width()).toBe(220);
  // 侧栏与内容左右排列：内容在可视区域内，并且在侧栏右侧
  const heading = page.getByRole('heading', { name: '仪表盘' });
  await expect(heading).toBeInViewport();
  expect((await heading.boundingBox())!.x).toBeGreaterThanOrEqual(220);

  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect.poll(width).toBe(0);
  await expect(page.getByRole('navigation', { name: '主导航' })).toBeHidden();
  await expect(heading).toBeInViewport();

  // 展开过程中宽度逐渐增加
  await toggle.click();
  const samples: number[] = [];
  for (let i = 0; i < 6; i++) {
    samples.push(await width());
    await page.waitForTimeout(40);
  }
  await expect.poll(width).toBe(220);
  expect(samples.some((w) => w > 0 && w < 220)).toBe(true);
  await page.getByRole('navigation', { name: '主导航' }).getByText('用户').click();
  await expect(page.getByRole('heading', { name: '用户' })).toBeVisible();
});
