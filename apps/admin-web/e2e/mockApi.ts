import type { Page } from '@playwright/test';
import { defaultState, fakeApi, type FakeState } from '../src/test/fakeApi';

/** 在浏览器层拦截 /api 请求，交给内存中的模拟接口处理。返回模拟接口，便于断言请求。 */
export async function mockApi(page: Page, over: Partial<FakeState> = {}) {
  const api = fakeApi({ ...defaultState(), ...over });
  await page.route('**/api/**', async (route) => {
    const r = route.request();
    const req = new Request(r.url(), {
      method: r.method(),
      headers: await r.allHeaders(),
      body: ['GET', 'HEAD'].includes(r.method()) ? undefined : (r.postData() ?? undefined),
    });
    const res = await api.fetch(req);
    await route.fulfill({ status: res.status, contentType: 'application/json', body: await res.text() });
  });
  return api;
}
