// 构建与预览前运行：把仓库 docs/ 中的使用说明、发布说明与法律文本同步为官网页面（见 lib/docs.mjs）。
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syncDocs } from '../lib/docs.mjs';
import { REPO_URL, SITE_URL } from '../lib/site.mjs';

const SITE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const result = await syncDocs({
  repoRoot: path.resolve(SITE, '../..'),
  outRoot: path.join(SITE, 'src'),
  repoUrl: REPO_URL,
  siteUrl: SITE_URL,
});
// 侧栏与教程首页的章节列表
const generated = path.join(SITE, '.vitepress/generated');
await mkdir(generated, { recursive: true });
await writeFile(path.join(generated, 'nav.json'), `${JSON.stringify(result, null, 2)}\n`, 'utf8');
console.log(`✔ 教程 ${result.guide.length} 章，更新日志 ${result.changelog.length} 个版本`);
// 草稿也照常构建（页面上有"草稿"提示），但在 CI 与部署的运行摘要中醒目提示
for (const file of result.drafts) {
  console.log(`::warning file=${file}::${file} 中还有【待填写】的内容，正式发布前须补全`);
}
