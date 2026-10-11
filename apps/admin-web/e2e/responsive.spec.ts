import { expect, test } from '@playwright/test';
import { mockApi } from './mockApi';

test('手机宽度：侧栏为浮层，选择后自动收起，页面不出现横向滚动', async ({ page }) => {
  await mockApi(page, { session: true });
  await page.goto('/dashboard');
  await expect(page.getByText('用户总数')).toBeVisible();
  const nav = page.getByRole('navigation', { name: '主导航' });
  await expect(nav).toBeHidden();

  await page.getByRole('button', { name: '导航' }).click();
  await expect(nav).toBeVisible();
  await nav.getByText('用户').click();
  await expect(nav).toBeHidden();
  await expect(page.getByRole('heading', { name: '用户' })).toBeVisible();

  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});
