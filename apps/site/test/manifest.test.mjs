import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildManifest } from '../lib/build-manifest.mjs';
import { formatSize, parseManifest } from '../lib/manifest.mjs';

const sha = (s) => createHash('sha256').update(s).digest('hex');
const sha1 = (s) => createHash('sha1').update(s).digest('hex');
const REPO_URL = 'https://github.com/vvangz/JikeLog';

async function releaseDir(files) {
  const dir = await mkdtemp(path.join(tmpdir(), 'jikelog-dl-'));
  for (const [name, content] of Object.entries(files)) await writeFile(path.join(dir, name), content);
  return dir;
}

test('buildManifest 核对校验文件并列出各平台安装包', async () => {
  const dir = await releaseDir({
    'jikelog-1.1.0.apk': 'apk',
    'jikelog-1.1.0.apk.sha256': `${sha('apk')}  jikelog-1.1.0.apk\n`,
    'jikelog-1.1.0.msix': 'msix!',
    'jikelog-1.1.0.msix.sha256': `${sha('msix!')}  jikelog-1.1.0.msix\n`,
    'jikelog-windows.cer': 'cer',
  });
  const m = await buildManifest({ dir, version: '1.1.0', repoUrl: REPO_URL, publishedAt: '2026-10-20T08:00:00Z' });
  assert.deepEqual(m, {
    version: '1.1.0',
    publishedAt: '2026-10-20T08:00:00.000Z',
    releaseUrl: `${REPO_URL}/releases/tag/v1.1.0`,
    files: {
      android: { name: 'jikelog-1.1.0.apk', size: 3, sha256: sha('apk') },
      windows: { name: 'jikelog-1.1.0.msix', size: 5, sha256: sha('msix!') },
      windowsCert: { name: 'jikelog-windows.cer', size: 3, sha256: sha('cer'), sha1: sha1('cer') },
    },
  });
});

test('buildManifest 在校验值不符时报错，不发布被替换的安装包', async () => {
  const dir = await releaseDir({
    'jikelog-1.1.0.apk': 'tampered',
    'jikelog-1.1.0.apk.sha256': `${sha('apk')}  jikelog-1.1.0.apk\n`,
  });
  await assert.rejects(buildManifest({ dir, version: '1.1.0', repoUrl: REPO_URL }), /jikelog-1\.1\.0\.apk/);
});

test('buildManifest 缺少校验文件或证书的平台不收录，并给出警告（上传到一半的 Release）', async () => {
  const dir = await releaseDir({
    'jikelog-1.1.0.apk': 'apk',
    'jikelog-1.1.0.msix': 'msix',
    'jikelog-1.1.0.msix.sha256': `${sha('msix')}  jikelog-1.1.0.msix\n`,
  });
  const warnings = [];
  const m = await buildManifest({ dir, version: '1.1.0', repoUrl: REPO_URL, onWarning: (w) => warnings.push(w) });
  assert.deepEqual(m.files, {});
  assert.equal(warnings.length, 2);
  assert.match(warnings[0], /jikelog-1\.1\.0\.apk\.sha256/);
  assert.match(warnings[1], /jikelog-windows\.cer/);
});

test('buildManifest 只收录有的平台', async () => {
  const apkOnly = await releaseDir({
    'jikelog-1.1.0.apk': 'apk',
    'jikelog-1.1.0.apk.sha256': `${sha('apk')}  jikelog-1.1.0.apk\n`,
  });
  const m = await buildManifest({ dir: apkOnly, version: '1.1.0', repoUrl: REPO_URL });
  assert.deepEqual(Object.keys(m.files), ['android']);
});

test('buildManifest 拒绝不合法的发布时间', async () => {
  const dir = await releaseDir({});
  await assert.rejects(buildManifest({ dir, version: '1.1.0', repoUrl: REPO_URL, publishedAt: 'yesterday' }), /发布时间/);
});

test('buildManifest 拒绝不合法的版本号', async () => {
  const dir = await releaseDir({});
  await assert.rejects(buildManifest({ dir, version: '1.1.0; rm -rf /', repoUrl: REPO_URL }), /版本号/);
});

const valid = {
  version: '1.1.0',
  publishedAt: '2026-10-20T08:00:00.000Z',
  releaseUrl: `${REPO_URL}/releases/tag/v1.1.0`,
  files: {
    android: { name: 'jikelog-1.1.0.apk', size: 3, sha256: 'a'.repeat(64) },
    windows: { name: 'jikelog-1.1.0.msix', size: 5, sha256: 'b'.repeat(64) },
    windowsCert: { name: 'jikelog-windows.cer', size: 3, sha256: 'c'.repeat(64), sha1: 'd'.repeat(40) },
  },
};

test('parseManifest 接受合法清单并补上下载地址', () => {
  const m = parseManifest(valid);
  assert.equal(m.version, '1.1.0');
  assert.equal(m.files.android.url, '/download/jikelog-1.1.0.apk');
  assert.equal(m.files.windowsCert.url, '/download/jikelog-windows.cer');
  assert.equal(m.files.windowsCert.sha1, 'D'.repeat(40), 'SHA-1 指纹按 Windows 的习惯大写显示');
  const badSha1 = parseManifest({ ...valid, files: { windowsCert: { ...valid.files.windowsCert, sha1: 'x' } } });
  assert.equal(badSha1.files.windowsCert.sha1, undefined);
  assert.equal(m.publishedAt.toISOString(), valid.publishedAt);
});

test('parseManifest 丢弃不合法的条目，整份不合法时返回 null', () => {
  assert.equal(parseManifest(null), null);
  assert.equal(parseManifest({ ...valid, version: '<script>' }), null);
  assert.equal(parseManifest({ ...valid, releaseUrl: 'javascript:alert(1)' }), null);
  const m = parseManifest({
    ...valid,
    files: {
      ...valid.files,
      android: { name: '../../etc/passwd', size: 1, sha256: 'a'.repeat(64) },
      windows: { name: 'jikelog-1.1.0.msix', size: -1, sha256: 'b'.repeat(64) },
    },
  });
  assert.equal(m.files.android, undefined);
  assert.equal(m.files.windows, undefined);
  assert.ok(m.files.windowsCert);
});

test('formatSize 以 MB/KB 显示', () => {
  assert.equal(formatSize(33658588), '32.1 MB');
  assert.equal(formatSize(2048), '2 KB');
  assert.equal(formatSize(500), '500 B');
});

test('make-manifest 脚本写出 latest.json；参数缺失或校验失败时以非零状态退出', async () => {
  const { execFileSync, spawnSync } = await import('node:child_process');
  const { readFile: read } = await import('node:fs/promises');
  const { fileURLToPath } = await import('node:url');
  const script = fileURLToPath(new URL('../scripts/make-manifest.mjs', import.meta.url));
  const dir = await releaseDir({
    'jikelog-1.1.0.apk': 'apk',
    'jikelog-1.1.0.apk.sha256': `${sha('apk')}  jikelog-1.1.0.apk\n`,
  });
  execFileSync(process.execPath, [script, dir, '1.1.0', '2026-10-20T08:00:00Z']);
  const written = JSON.parse(await read(path.join(dir, 'latest.json'), 'utf8'));
  assert.equal(written.files.android.sha256, sha('apk'));
  assert.equal(written.publishedAt, '2026-10-20T08:00:00.000Z');

  const usage = spawnSync(process.execPath, [script]);
  assert.equal(usage.status, 2);
  const bad = await releaseDir({ 'jikelog-1.1.0.apk': 'apk', 'jikelog-1.1.0.apk.sha256': 'deadbeef\n' });
  const failed = spawnSync(process.execPath, [script, bad, '1.1.0']);
  assert.equal(failed.status, 1);
});
