// 下载清单 latest.json 的读取（浏览器端）：官网下载页据此显示版本、大小与校验值。
// 清单由部署工作流生成（build-manifest.mjs），随安装包一起上传到服务器的 /download/。
export const SEMVER = /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/;
const FILE_NAME = /^jikelog-[0-9A-Za-z.-]+\.(apk|msix|cer)$/;
const SHA256 = /^[0-9a-f]{64}$/;
const SHA1 = /^[0-9a-f]{40}$/;

function parseFile(f) {
  if (!f || typeof f !== 'object') return undefined;
  const { name, size, sha256 } = f;
  if (typeof name !== 'string' || !FILE_NAME.test(name)) return undefined;
  if (!Number.isSafeInteger(size) || size <= 0) return undefined;
  if (typeof sha256 !== 'string' || !SHA256.test(sha256)) return undefined;
  const parsed = { name, size, sha256, url: `/download/${name}` };
  // 证书的 SHA-1 指纹（只有 windowsCert 有），按 Windows 证书对话框的习惯大写显示
  if (typeof f.sha1 === 'string' && SHA1.test(f.sha1)) parsed.sha1 = f.sha1.toUpperCase();
  return parsed;
}

/** 校验从服务器取到的清单。整体不合法返回 null；个别安装包条目不合法时只丢弃该条。 */
export function parseManifest(json) {
  if (!json || typeof json !== 'object') return null;
  const { version, publishedAt, releaseUrl, files } = json;
  if (typeof version !== 'string' || !SEMVER.test(version)) return null;
  if (typeof releaseUrl !== 'string' || !releaseUrl.startsWith('https://github.com/')) return null;
  const date = new Date(publishedAt);
  if (Number.isNaN(date.getTime())) return null;
  const parsed = {};
  for (const key of ['android', 'windows', 'windowsCert']) {
    const f = parseFile(files?.[key]);
    if (f) parsed[key] = f;
  }
  return { version, publishedAt: date, releaseUrl, files: parsed };
}

export function formatSize(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

