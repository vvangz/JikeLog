// 发布时由部署工作流（scripts/collect-downloads.sh）调用：核对从 GitHub Release 下载的安装包，生成 latest.json 写入同一目录。
//   node scripts/make-manifest.mjs <安装包目录> <版本> [Release 的发布时间]
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { buildManifest } from '../lib/build-manifest.mjs';
import { REPO_URL } from '../lib/site.mjs';

const [dir, version, publishedAt] = process.argv.slice(2);
if (!dir || !version) {
  console.error('用法：node scripts/make-manifest.mjs <安装包目录> <版本> [发布时间]');
  process.exit(2);
}
try {
  const manifest = await buildManifest({
    dir,
    version,
    repoUrl: REPO_URL,
    publishedAt: publishedAt || undefined,
    // GitHub Actions 的警告格式，显示在运行摘要中
    onWarning: (w) => console.log(`::warning::${w}`),
  });
  await writeFile(path.join(dir, 'latest.json'), `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  console.log(`✔ latest.json：${Object.keys(manifest.files).join('、') || '（没有安装包）'}`);
} catch (err) {
  console.error(`生成下载清单失败：${err.message}`);
  process.exit(1);
}
