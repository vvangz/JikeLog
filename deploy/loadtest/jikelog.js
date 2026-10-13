// 即刻日志压测（k6）。性能目标见实施计划：
//   - 同区域接口 p95 < 100ms（场景 api）
//   - 500 条变更的推送与拉取 p95 < 200ms（场景 sync500）：接口每次最多推送 100 条、每页最多返回 100 条，
//     500 条分 5 次请求，按 5 次请求的总耗时计算
//   - 实时通知 1 秒内到达另一台设备（场景 realtime）
// 工作日志的敏感字段与 App 一样用传输会话密钥加密（AES-256-GCM），会话密钥由 e2e-keys.sh 预先算好。
// 运行方式见 run.sh 与 docs/部署运维/压测.md。
import http from 'k6/http';
import ws from 'k6/ws';
import encoding from 'k6/encoding';
import exec from 'k6/execution';
import { check, fail } from 'k6';
import { Trend } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://api:8080';
const USERS = Number(__ENV.USERS || 8);
const DURATION = __ENV.DURATION || '2m';
const API_RATE = Number(__ENV.API_RATE || 30); // 每秒请求组数（每组 3 个读接口）
const SYNC_RATE = Number(__ENV.SYNC_RATE || 1); // 每秒完成多少轮"推送 500 条 + 拉取 500 条"
const RUN = __ENV.RUN_ID || `${Date.now().toString(36)}`;
const BATCH = 100; // 接口限制：一次推送最多 100 条
const BATCHES = 5;

const pushBatch = new Trend('sync_push_100', true);
const push500 = new Trend('sync_push_500_total', true);
const pullPage = new Trend('sync_pull_page', true);
const pull500 = new Trend('sync_pull_500_total', true);
const notifyLatency = new Trend('realtime_notify', true);

export const options = {
  setupTimeout: '120s',
  scenarios: {
    api: {
      executor: 'constant-arrival-rate', exec: 'readApi', rate: API_RATE, timeUnit: '1s',
      duration: DURATION, preAllocatedVUs: 20, maxVUs: 60,
    },
    sync500: {
      executor: 'constant-arrival-rate', exec: 'sync500', rate: SYNC_RATE, timeUnit: '1s',
      duration: DURATION, preAllocatedVUs: 4, maxVUs: 16,
    },
    realtime: {
      executor: 'constant-vus', exec: 'realtime', vus: 2, duration: DURATION,
    },
  },
  thresholds: {
    'http_req_duration{kind:api}': ['p(95)<100'],
    sync_push_500_total: ['p(95)<200'],
    sync_pull_500_total: ['p(95)<200'],
    realtime_notify: ['p(95)<1000'],
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// ───────── 工具 ─────────

function utf8(s) {
  const bin = unescape(encodeURIComponent(s));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function fromUtf8(bytes) {
  let bin = '';
  for (const b of new Uint8Array(bytes)) bin += String.fromCharCode(b);
  return decodeURIComponent(escape(bin));
}

let sessionKey;
function key() {
  sessionKey ??= crypto.subtle.importKey(
    'raw', encoding.b64decode(__ENV.E2E_SESSION_KEY, 'std'), { name: 'AES-GCM' }, false, ['encrypt', 'decrypt'],
  );
  return sessionKey;
}

const aad = (entity, id, field) => `jikelog-e2e-v1|${entity}|${id}|${field}|v`;

async function seal(entity, id, field, plain) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv, additionalData: utf8(aad(entity, id, field)) }, await key(), utf8(plain),
  );
  const out = new Uint8Array(12 + ct.byteLength);
  out.set(iv);
  out.set(new Uint8Array(ct), 12);
  return encoding.b64encode(out.buffer, 'std');
}

async function open(entity, id, field, sealed) {
  const raw = new Uint8Array(encoding.b64decode(sealed, 'std'));
  const plain = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: raw.slice(0, 12), additionalData: utf8(aad(entity, id, field)) }, await key(), raw.slice(12),
  );
  return fromUtf8(plain);
}

let hlcCounter = 0;
function hlc(node) {
  hlcCounter = (hlcCounter + 1) % 0x10000;
  return `${Date.now()}-${hlcCounter.toString(16).padStart(4, '0')}-${node}`;
}

const json = (body, token, sid) => ({
  headers: {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(sid ? { 'X-JikeLog-E2E': sid } : {}),
  },
  body: body === undefined ? undefined : JSON.stringify(body),
});

function call(method, path, body, token, sid, tags) {
  const p = json(body, token, sid);
  return http.request(method, `${BASE}${path}`, p.body, { headers: p.headers, tags });
}

const CONTENT = '今天完成了同步模块的联调，修复了离线编辑后合并冲突的问题；下午和产品讨论了备份策略，'
  + '确认每 14 天做一次全量加密备份并上传异地存储。明天计划压测接口性能，整理上线检查清单。';

// ───────── 准备：每个账号两台设备（A 推送，B 接收实时通知） ─────────

function device(user, label) {
  return { installationId: `k6-${RUN}-${user}-${label}`, platform: 'android', model: 'k6', appVersion: 'loadtest' };
}

function login(username, password, label) {
  const res = call('POST', '/api/v1/auth/login/password', { username, password, device: device(username, label) });
  if (res.status !== 200) fail(`登录失败 ${username}: ${res.status} ${res.body}`);
  const d = res.json('data');
  return { token: d.tokens.accessToken, deviceId: d.deviceId };
}

function e2eSession(token) {
  const res = call('POST', '/api/v1/sync/e2e/session', {
    clientPublicKey: __ENV.E2E_CLIENT_PUBLIC_KEY, serverKeyId: __ENV.E2E_SERVER_KEY_ID,
  }, token);
  if (res.status !== 201) fail(`建立加密会话失败: ${res.status} ${res.body}`);
  return res.json('data.sessionId');
}

export function setup() {
  const users = [];
  for (let i = 0; i < USERS; i++) {
    const username = `k6${RUN}u${i}`.slice(0, 20);
    const password = `Load-test-${RUN}-1`;
    const reg = call('POST', '/api/v1/auth/register', { username, password, device: device(username, 'a') });
    let a;
    if (reg.status === 201) {
      a = { token: reg.json('data.tokens.accessToken'), deviceId: reg.json('data.deviceId') };
    } else if (reg.status === 409) {
      a = login(username, password, 'a');
    } else {
      fail(`注册失败 ${username}: ${reg.status} ${reg.body}`);
    }
    const b = login(username, password, 'b');
    users.push({ username, a: { ...a, sid: e2eSession(a.token) }, b: { ...b, sid: e2eSession(b.token) } });
  }
  return { users };
}

// 按场景内的迭代序号轮流使用各账号，使每个账号的推送频率低于服务端限制（每分钟 120 次）
const userFor = (data) => data.users[exec.scenario.iterationInTest % data.users.length];

async function worklogChange(node, i) {
  const id = crypto.randomUUID();
  const day = new Date(Date.now() - (i % 365) * 86400000).toISOString().slice(0, 10);
  const c = hlc(node);
  return {
    entity: 'worklog', id,
    fields: {
      date: day,
      location: await seal('worklog', id, 'location', '公司'),
      content: await seal('worklog', id, 'content', `${CONTENT}（${i}）`),
    },
    clocks: { date: c, location: c, content: c },
  };
}

// ───────── 场景 ─────────

/** 常用读接口：个人信息、增量拉取（无新数据）、附件用量。 */
export function readApi(data) {
  const u = userFor(data).b;
  const tags = { kind: 'api' };
  const res = [
    call('GET', '/api/v1/me', undefined, u.token, undefined, tags),
    call('GET', '/api/v1/sync/pull?since=999999999&limit=50', undefined, u.token, u.sid, tags),
    call('GET', '/api/v1/attachments/usage', undefined, u.token, undefined, tags),
  ];
  check(res, { '读接口 200': (rs) => rs.every((r) => r.status === 200) });
}

/** 推送 500 条工作日志（5 次），再分页拉取这 500 条并抽查解密。 */
export async function sync500(data) {
  const u = userFor(data).a;
  const node = u.deviceId.replace(/-/g, '').slice(0, 16);
  const pushed = new Set();
  let first = 0;
  let last = 0;
  let total = 0;
  for (let b = 0; b < BATCHES; b++) {
    const changes = [];
    for (let i = 0; i < BATCH; i++) changes.push(await worklogChange(node, b * BATCH + i));
    changes.forEach((c) => pushed.add(c.id));
    const res = call('POST', '/api/v1/sync/push', { changes }, u.token, u.sid, { name: 'sync_push' });
    total += res.timings.duration;
    pushBatch.add(res.timings.duration);
    const ok = check(res, {
      '推送 200': (r) => r.status === 200 || console.warn(`推送失败 ${r.status} ${r.body}`),
      '推送全部生效': (r) => r.status === 200 && r.json('data.results').every((x) => x.status === 'applied'),
    });
    if (!ok) return;
    if (b === 0) first = res.json('data.results.0.serverSeq');
    last = res.json(`data.results.${BATCH - 1}.serverSeq`);
  }
  push500.add(total);

  // 同一账号的其他场景也在推送，所以只数本轮推送的记录
  const recs = [];
  let since = first - 1;
  let elapsed = 0;
  while (recs.length < BATCH * BATCHES) {
    const res = call('GET', `/api/v1/sync/pull?since=${since}&limit=500`, undefined, u.token, u.sid, { name: 'sync_pull' });
    elapsed += res.timings.duration;
    pullPage.add(res.timings.duration);
    if (!check(res, { '拉取 200': (r) => r.status === 200 })) return;
    recs.push(...res.json('data.records').filter((r) => pushed.has(r.id)));
    since = res.json('data.nextSince');
    if (!res.json('data.hasMore') || since >= last) break;
  }
  pull500.add(elapsed);
  check(recs, { '拉取到 500 条': (r) => r.length === BATCH * BATCHES });
  if (recs.length > 0) {
    const r = recs[0];
    const content = await open('worklog', r.id, 'content', r.fields.content);
    check(content, { '拉取的密文可以解开': (c) => c.startsWith(CONTENT) });
  }
}

/**
 * 设备 B 保持实时连接，设备 A 每秒推送一条，测量从 A 发出推送到 B 收到通知的时间（含推送请求本身）。
 * WebSocket 回调中不能 await，所以先把要推送的变更加密好。
 */
export async function realtime(data) {
  const u = data.users[(exec.vu.idInTest + exec.vu.iterationInScenario) % data.users.length];
  const node = u.a.deviceId.replace(/-/g, '').slice(0, 16);
  const pending = [];
  for (let i = 0; i < 25; i++) pending.push(await worklogChange(node, i));
  const wsUrl = `${BASE.replace(/^http/, 'ws')}/api/v1/sync/ws`;
  let sentAt = 0;
  let hello = false;
  const res = ws.connect(wsUrl, { headers: { Authorization: `Bearer ${u.b.token}` } }, (socket) => {
    const pushOne = () => {
      const change = pending.pop();
      if (!change) return socket.close();
      sentAt = Date.now();
      call('POST', '/api/v1/sync/push', { changes: [change] }, u.a.token, u.a.sid, { name: 'sync_push_one' });
    };
    socket.on('message', (msg) => {
      const m = JSON.parse(msg);
      if (m.type === 'hello' && !hello) {
        hello = true;
        pushOne();
      } else if (m.type === 'changed' && sentAt > 0) {
        notifyLatency.add(Date.now() - sentAt);
        sentAt = 0;
        socket.setTimeout(pushOne, 1000);
      }
    });
    socket.setTimeout(() => socket.close(), 20000);
  });
  check(res, { '实时连接 101': (r) => r && r.status === 101 });
}
