// 生成下载清单 latest.json（Node 端）：发布时由部署工作流（scripts/collect-downloads.sh）调用 scripts/make-manifest.mjs，
// 读取从 GitHub Release 下载的安装包，核对 .sha256 后生成清单。
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { SEMVER } from './manifest.mjs';

const CERT_NAME = 'jikelog-windows.cer';

const PLATFORMS = {
  android: (v) => `jikelog-${v}.apk`,
  windows: (v) => `jikelog-${v}.msix`,
};

const digest = (algorithm, content) => createHash(algorithm).update(content).digest('hex');

async function describe(dir, name) {
  const content = await readFile(path.join(dir, name));
  return { name, size: content.length, sha256: digest('sha256', content) };
}

/**
 * 读取 dir 中某个版本的安装包，核对 .sha256 后生成清单。
 * - 安装包与 .sha256 不符时报错：不发布被替换的安装包。
 * - 缺少 .sha256（或 Windows 缺少证书）的平台不收录，经 onWarning 提示：Release 可能还没上传完。
 * publishedAt 为 Release 的发布时间；省略时取当前时间。
 */
export async function buildManifest({ dir, version, repoUrl, publishedAt, onWarning = console.warn }) {
  if (!SEMVER.test(version)) throw new Error(`版本号不合法：${version}`);
  const date = publishedAt === undefined ? new Date() : new Date(publishedAt);
  if (Number.isNaN(date.getTime())) throw new Error(`发布时间不合法：${publishedAt}`);

  const present = new Set(await readdir(dir));
  const files = {};
  for (const [platform, nameFor] of Object.entries(PLATFORMS)) {
    const name = nameFor(version);
    if (!present.has(name)) continue;
    if (!present.has(`${name}.sha256`)) {
      onWarning(`缺少 ${name}.sha256，不收录 ${name}`);
      continue;
    }
    const file = await describe(dir, name);
    const expected = (await readFile(path.join(dir, `${name}.sha256`), 'utf8')).trim().split(/\s+/)[0];
    if (expected !== file.sha256) throw new Error(`${name} 与 ${name}.sha256 不符：${file.sha256} ≠ ${expected}`);
    files[platform] = file;
  }
  if (files.windows) {
    if (present.has(CERT_NAME)) {
      const cert = await readFile(path.join(dir, CERT_NAME));
      // SHA-1 即 Windows 显示的证书指纹，下载页据此提示用户核对
      files.windowsCert = { ...(await describe(dir, CERT_NAME)), sha1: digest('sha1', cert) };
    } else {
      onWarning(`缺少证书 ${CERT_NAME}，不收录 ${files.windows.name}`);
      delete files.windows;
    }
  }
  return {
    version,
    publishedAt: date.toISOString(),
    releaseUrl: `${repoUrl}/releases/tag/v${version}`,
    files,
  };
}
