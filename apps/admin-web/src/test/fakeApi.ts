import type { components } from '../api/schema.gen';

type S = components['schemas'];

export interface FakeState {
  /** 刷新接口能否成功（模拟浏览器中已有有效的 Refresh Cookie）。 */
  session: boolean;
  admin: S['AdminProfile'];
  admins: S['AdminProfile'][];
  users: S['AdminUserSummary'][];
  detail: S['AdminUserDetail'];
  dashboard: S['AdminDashboard'];
  logs: S['AuditLog'][];
  /** 下一次受保护接口返回 401（模拟 Access Token 过期）。 */
  expireOnce: boolean;
  /** 指定路径返回的错误（路径 → [状态码, 错误码, 说明]）。 */
  failures: Record<string, [number, string, string]>;
}

export interface Recorded {
  method: string;
  path: string;
  query: URLSearchParams;
  body: unknown;
  headers: Headers;
}

const now = '2026-10-11T08:00:00Z';

export function adminProfile(over: Partial<S['AdminProfile']> = {}): S['AdminProfile'] {
  return {
    id: '00000000-0000-7000-8000-000000000001',
    username: 'root',
    role: 'super_admin',
    disabled: false,
    mustChangePassword: false,
    lastLoginAt: now,
    createdAt: now,
    ...over,
  };
}

export function userSummary(i: number, over: Partial<S['AdminUserSummary']> = {}): S['AdminUserSummary'] {
  return {
    id: `00000000-0000-7000-8000-0000000001${String(i).padStart(2, '0')}`,
    username: `user${String(i).padStart(2, '0')}`,
    nickname: i === 1 ? '小明' : '',
    phoneMasked: i === 1 ? '+86 138****5678' : undefined,
    createdAt: now,
    lastActiveAt: now,
    deviceCount: 1,
    storageBytes: 2048,
    ...over,
  };
}

export function defaultState(): FakeState {
  const users = Array.from({ length: 25 }, (_, i) => userSummary(i + 1));
  return {
    session: false,
    admin: adminProfile(),
    admins: [adminProfile(), adminProfile({ id: '00000000-0000-7000-8000-000000000002', username: 'viewer1', role: 'viewer' })],
    users,
    detail: {
      user: users[0]!,
      settings: { themeMode: 'dark', fontScale: 1.2, weekStart: 7, defaultReminders: [0, 15], updatedAt: now },
      devices: [
        {
          id: '00000000-0000-7000-8000-000000000201',
          platform: 'android',
          model: 'Pixel 9',
          osVersion: 'Android 16',
          appVersion: '0.7.0',
          lastActiveAt: now,
          createdAt: now,
          signedIn: true,
          localReminders: true,
          pushEnabled: true,
          ackSeq: 10,
        },
        {
          id: '00000000-0000-7000-8000-000000000202',
          platform: 'android',
          model: '',
          osVersion: '',
          appVersion: '',
          lastActiveAt: now,
          createdAt: now,
          signedIn: false,
          localReminders: false,
          pushEnabled: false,
          ackSeq: 4,
        },
      ],
      sync: { serverSeq: 10, lastSyncAt: now },
      storage: { used: 1024 * 1024, quota: 2 * 1024 * 1024 * 1024 },
    },
    dashboard: {
      totalUsers: 25,
      newUsersToday: 3,
      activeToday: 7,
      activeWeek: 12,
      activeMonth: 20,
      storageBytes: 5 * 1024 * 1024,
      newUsersDaily: Array.from({ length: 30 }, (_, i) => ({ day: `2026-09-${String(i + 1).padStart(2, '0')}`, count: i % 4 })),
      platforms: [
        { platform: 'android', devices: 18 },
        { platform: 'web', devices: 2 },
      ],
    },
    logs: [
      {
        id: '00000000-0000-7000-8000-000000000301',
        adminId: '00000000-0000-7000-8000-000000000001',
        username: 'root',
        action: 'login_failed',
        targetType: '',
        targetId: '',
        ip: '203.0.113.5',
        userAgent: 'test',
        detail: { reason: 'password' },
        createdAt: now,
      },
      {
        id: '00000000-0000-7000-8000-000000000302',
        adminId: '00000000-0000-7000-8000-000000000001',
        username: 'root',
        action: 'view_user',
        targetType: 'user',
        targetId: users[0]!.id,
        ip: '203.0.113.5',
        userAgent: 'test',
        detail: {},
        createdAt: now,
      },
    ],
    expireOnce: false,
    failures: {},
  };
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const ok = (data: unknown, meta?: unknown) => json(200, { success: true, requestId: 't', data, ...(meta ? { meta } : {}) });
const fail = (status: number, code: string, message: string) =>
  json(status, { success: false, requestId: 't', error: { code, message } });

/** 内存中的管理接口：记录每次请求，按 state 返回结果。 */
export function fakeApi(state: FakeState = defaultState()) {
  const calls: Recorded[] = [];
  const session = () => ({ accessToken: 'token-1', expiresAt: now, admin: state.admin });

  const fetch = async (req: Request): Promise<Response> => {
    const url = new URL(req.url);
    const path = url.pathname;
    const text = req.method === 'GET' ? '' : await req.text();
    calls.push({ method: req.method, path, query: url.searchParams, body: text ? JSON.parse(text) : undefined, headers: req.headers });
    const failure = state.failures[path];
    if (failure) return fail(...failure);

    if (path === '/api/admin/v1/auth/refresh') {
      return state.session ? ok(session()) : fail(401, 'UNAUTHORIZED', '登录已失效');
    }
    if (path === '/api/admin/v1/auth/login') {
      const body = JSON.parse(text) as { password: string };
      if (body.password !== 'Admin12345') return fail(401, 'INVALID_CREDENTIALS', '用户名或密码错误');
      state.session = true;
      return ok(session());
    }
    if (path === '/api/admin/v1/auth/logout') {
      state.session = false;
      return ok({ ok: true });
    }
    if (req.headers.get('Authorization') !== 'Bearer token-1') return fail(401, 'UNAUTHORIZED', '请先登录');
    if (state.expireOnce) {
      state.expireOnce = false;
      return fail(401, 'UNAUTHORIZED', '令牌已过期');
    }
    if (state.admin.mustChangePassword && !['/api/admin/v1/me', '/api/admin/v1/me/password'].includes(path)) {
      return fail(403, 'PASSWORD_CHANGE_REQUIRED', '请先修改初始密码');
    }
    return route(req.method, path, url.searchParams, text ? JSON.parse(text) : undefined);
  };

  const route = (method: string, path: string, q: URLSearchParams, body: Record<string, unknown> | undefined) => {
    if (path === '/api/admin/v1/me') return ok(state.admin);
    if (path === '/api/admin/v1/me/password') {
      if (body?.currentPassword !== 'Admin12345') {
        return json(422, { success: false, requestId: 't', error: { code: 'VALIDATION_FAILED', message: '参数校验失败', details: { fields: { currentPassword: '当前密码不正确' } } } });
      }
      state.admin = { ...state.admin, mustChangePassword: false };
      return ok({ ok: true });
    }
    if (path === '/api/admin/v1/dashboard') return ok(state.dashboard);
    if (path === '/api/admin/v1/users') {
      const term = q.get('q') ?? '';
      const page = Number(q.get('page') ?? 1);
      const size = Number(q.get('pageSize') ?? 20);
      const all = state.users.filter((u) => !term || u.username.includes(term) || (u.phoneMasked ?? '').endsWith(term));
      return ok(all.slice((page - 1) * size, page * size), { total: all.length, page, limit: size });
    }
    if (path.startsWith('/api/admin/v1/users/')) {
      return path.endsWith(state.detail.user.id) ? ok(state.detail) : fail(404, 'NOT_FOUND', '对象不存在');
    }
    if (path === '/api/admin/v1/audit-logs') {
      const action = q.get('action');
      const items = state.logs.filter((l) => !action || l.action === action);
      return ok(items, { total: items.length, page: 1, limit: 20 });
    }
    if (path === '/api/admin/v1/admins' && method === 'GET') return ok(state.admins);
    if (path === '/api/admin/v1/admins' && method === 'POST') {
      const a = adminProfile({ id: `00000000-0000-7000-8000-00000000000${state.admins.length + 1}`, username: String(body?.username), role: body?.role as S['AdminRole'], mustChangePassword: true });
      state.admins = [...state.admins, a];
      return json(201, { success: true, requestId: 't', data: a });
    }
    const m = /^\/api\/admin\/v1\/admins\/([^/]+)(\/password)?$/.exec(path);
    if (m) {
      const id = m[1];
      if (m[2]) return ok({ ok: true });
      state.admins = state.admins.map((a) => (a.id === id ? { ...a, ...(body as Partial<S['AdminProfile']>) } : a));
      return ok(state.admins.find((a) => a.id === id));
    }
    return fail(404, 'NOT_FOUND', '请求的资源不存在');
  };

  return { fetch, calls, state };
}
