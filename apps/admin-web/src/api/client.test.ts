import { describe, expect, it, vi } from 'vitest';
import { createApiClient } from './client';

describe('createApiClient', () => {
  it('按 OpenAPI 契约请求并返回统一信封', async () => {
    const body = {
      success: true,
      requestId: 'req-1',
      data: { name: 'jikelog-api', version: '0.1.0', commit: 'dev', buildTime: 'unknown', serverTime: '2026-10-08T00:00:00Z' },
    };
    const fetchMock = vi.fn(async (req: Request) => {
      expect(req.url).toBe('https://api.example.com/api/v1/system/info');
      return new Response(JSON.stringify(body), { headers: { 'Content-Type': 'application/json' } });
    });

    const client = createApiClient({ baseUrl: 'https://api.example.com', fetch: fetchMock });
    const { data, error } = await client.GET('/api/v1/system/info');

    expect(error).toBeUndefined();
    expect(data?.success).toBe(true);
    expect(data?.data?.version).toBe('0.1.0');
    expect(fetchMock).toHaveBeenCalledOnce();
  });
});

describe('错误响应', () => {
  it('非 2xx 时返回类型化的错误信封', async () => {
    const body = { success: false, requestId: 'req-2', error: { code: 'NOT_FOUND', message: '请求的资源不存在' } };
    const fetchMock = vi.fn(
      async () => new Response(JSON.stringify(body), { status: 404, headers: { 'Content-Type': 'application/json' } }),
    );
    const client = createApiClient({ baseUrl: 'https://api.example.com', fetch: fetchMock });
    const { data, error } = await client.GET('/api/v1/system/info');

    expect(data).toBeUndefined();
    expect(error?.error.code).toBe('NOT_FOUND');
    expect(error?.requestId).toBe('req-2');
  });
});
