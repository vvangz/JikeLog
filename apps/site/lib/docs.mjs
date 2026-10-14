// 把仓库 docs/ 下面向用户的文档同步为官网页面：使用说明 → /guide/，发布说明 → /changelog/，法律文本 → /privacy、/terms。
// 文档只维护一份（仓库里的 Markdown），官网构建前由 scripts/sync-docs.mjs 调用这里生成页面。
import { cp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

// 使用说明各章在官网上的网址。新增章节时在这里登记，否则同步时报错。
const GUIDE_SLUGS = {
  '01-快速上手': 'quick-start',
  '02-界面与导航': 'interface',
  '03-工作日志': 'worklog',
  '04-多设备同步': 'sync',
  '05-笔记': 'notes',
  '06-备忘录': 'memos',
  '07-记账': 'ledger',
  '08-搜索与导出': 'search-export',
  '09-Windows版': 'windows',
};

const LEGAL_SLUGS = {
  隐私政策: 'privacy',
  用户协议: 'terms',
};

const COLLECTIONS = [
  {
    src: 'docs/使用说明',
    route: (name) => {
      if (name === 'README') return null; // 官网的教程首页单独编写
      const slug = GUIDE_SLUGS[name];
      if (!slug) throw new Error(`使用说明「${name}」没有官网网址：在 apps/site/lib/docs.mjs 的 GUIDE_SLUGS 中登记`);
      return `/guide/${slug}`;
    },
    index: '/guide/',
  },
  { src: 'docs/发布说明', route: (name) => (name === 'README' ? null : `/changelog/${name}`), index: '/changelog/' },
  { src: 'docs/法律', route: (name) => (LEGAL_SLUGS[name] ? `/${LEGAL_SLUGS[name]}` : null), index: null },
];

/** 仓库内的文档路径（相对仓库根目录，用 /）对应的官网地址；不在官网上的返回 null。 */
export function siteRouteFor(repoPath) {
  const p = repoPath.replace(/\/+$/, '');
  for (const c of COLLECTIONS) {
    if (p === c.src) return c.index;
    if (path.posix.dirname(p) === c.src && p.endsWith('.md')) {
      return c.route(path.posix.basename(p, '.md'));
    }
  }
  return null;
}

/** GitHub 风格的标题锚点转为 VitePress 的写法：以数字开头的锚点前面加下划线。 */
export function anchorFor(anchor) {
  return /^\d/.test(anchor) ? `_${anchor}` : anchor;
}

const LINK = /(!?\[[^\]]*\]\()([^)\s]+)((?:\s+"[^"]*")?\))/g;

// 不合法的百分号转义按原样处理，不让一个坏链接中断构建
const safeDecode = (s) => {
  try {
    return decodeURI(s);
  } catch {
    return s;
  }
};

function rewriteTarget(target, fromRepoPath, repoUrl, siteUrl) {
  // 文档里写官网的完整地址（在 GitHub 上阅读时可点击），官网上改为站内路径
  if (siteUrl && (target === siteUrl || target.startsWith(`${siteUrl}/`) || target.startsWith(`${siteUrl}#`))) {
    const rest = target.slice(siteUrl.length);
    return rest.startsWith('/') ? rest : `/${rest}`;
  }
  if (target.startsWith('#')) return `#${anchorFor(target.slice(1))}`;
  if (/^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith('/')) return target;
  const [rawPath, anchor] = target.split('#', 2);
  const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(fromRepoPath), safeDecode(rawPath)));
  const route = siteRouteFor(resolved);
  if (route) return anchor ? `${route}#${anchorFor(anchor)}` : route;
  // 同一目录下的图片等资源随页面一起复制，相对路径不变
  if (!resolved.endsWith('.md') && path.posix.dirname(resolved).startsWith(path.posix.dirname(fromRepoPath))) {
    return target;
  }
  const encoded = resolved.split('/').map(encodeURIComponent).join('/');
  return `${repoUrl}/blob/main/${encoded}${anchor ? `#${anchor}` : ''}`;
}

// 官网与管理后台同源，文档里不允许出现能执行脚本或跳转的 HTML（lib/csp.mjs 也会拦下未知的内联脚本，这里提前给出清楚的报错）
const UNSAFE_HTML = [
  /<\s*(script|iframe|object|embed|meta|base|form|link|style)\b/i,
  /<[^>]*\son[a-z]+\s*=/i,
  /\]\(\s*(javascript|data|vbscript):/i,
  /\b(href|src)\s*=\s*["']?\s*(javascript|data|vbscript):/i,
];

/** 文档中出现脚本、事件属性、javascript: 链接或可跳转的标签时报错。代码块与行内代码中的示例不算。 */
export function assertSafeMarkdown(markdown, file) {
  const prose = markdown
    .replace(/^\s*(```|~~~)[\s\S]*?^\s*\1/gm, '')
    .replace(/`[^`\n]*`/g, '');
  for (const re of UNSAFE_HTML) {
    const m = prose.match(re);
    if (m) throw new Error(`${file} 中有不允许的 HTML 或链接「${m[0]}」：官网与管理后台同源，文档不能包含脚本`);
  }
}

/** 改写 Markdown 中的相对链接（代码块内不动）。fromRepoPath 为该文档相对仓库根目录的路径。 */
export function rewriteLinks(markdown, fromRepoPath, { repoUrl, siteUrl }) {
  let inFence = false;
  return markdown
    .split('\n')
    .map((line) => {
      if (/^\s*(```|~~~)/.test(line)) {
        inFence = !inFence;
        return line;
      }
      if (inFence) return line;
      return line.replace(LINK, (_, open, target, close) => open + rewriteTarget(target, fromRepoPath, repoUrl, siteUrl) + close);
    })
    .join('\n');
}

// 使用说明 README 中的章节表：| [01 快速上手](01-快速上手.md) | 安装、注册… | v0.2.0 |，取"内容"一列作为教程首页的简介
function chapterDescriptions(readme) {
  const desc = {};
  for (const m of readme.matchAll(/^\|\s*\[[^\]]*\]\(([^)#]+)\.md\)\s*\|\s*([^|]+?)\s*\|/gm)) {
    desc[safeDecode(m[1])] = m[2];
  }
  return desc;
}

const titleOf = (markdown) =>
  (markdown.match(/^#\s+(.+)$/m)?.[1] ?? '').replace(/^\d+\s+/, '').trim();

// 版本号从新到旧；同一版本的预发布版（1.0.0-rc.1）排在正式版之后
const semverDesc = (a, b) => {
  const parse = (v) => {
    const [core, pre = ''] = v.replace(/^v/, '').split('-', 2);
    return { nums: core.split('.').map((n) => Number.parseInt(n, 10) || 0), pre };
  };
  const pa = parse(a);
  const pb = parse(b);
  for (let i = 0; i < 3; i++) if (pa.nums[i] !== pb.nums[i]) return pb.nums[i] - pa.nums[i];
  if (pa.pre === pb.pre) return 0;
  if (!pa.pre) return -1;
  if (!pb.pre) return 1;
  return pb.pre.localeCompare(pa.pre, 'en', { numeric: true });
};

async function listMarkdown(dir) {
  try {
    return (await readdir(dir)).filter((f) => f.endsWith('.md')).sort();
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
}

/**
 * 生成页面到 outRoot（官网的 src 目录）。返回侧栏与更新日志需要的列表。
 * 每次先删除上次生成的内容，文档被删除或改名时不会留下旧页面。
 */
export async function syncDocs({ repoRoot, outRoot, repoUrl, siteUrl }) {
  await rm(path.join(outRoot, 'guide'), { recursive: true, force: true });
  await rm(path.join(outRoot, 'changelog'), { recursive: true, force: true });
  for (const slug of Object.values(LEGAL_SLUGS)) await rm(path.join(outRoot, `${slug}.md`), { force: true });

  const readme = await readFile(path.join(repoRoot, 'docs/使用说明/README.md'), 'utf8').catch(() => '');
  const descriptions = chapterDescriptions(readme);
  const guide = [];
  const changelog = [];
  const drafts = []; // 还有【待填写】的法律文本
  for (const c of COLLECTIONS) {
    for (const file of await listMarkdown(path.join(repoRoot, c.src))) {
      const repoPath = `${c.src}/${file}`;
      const route = siteRouteFor(repoPath);
      if (!route) continue;
      const source = await readFile(path.join(repoRoot, c.src, file), 'utf8');
      assertSafeMarkdown(source, repoPath);
      const target = path.join(outRoot, `${route.slice(1)}.md`);
      await mkdir(path.dirname(target), { recursive: true });
      await writeFile(target, rewriteLinks(source, repoPath, { repoUrl, siteUrl }), 'utf8');
      if (route.startsWith('/guide/')) {
        guide.push({ link: route, title: titleOf(source), desc: descriptions[path.basename(file, '.md')] ?? '' });
      }
      if (route.startsWith('/changelog/')) changelog.push(path.basename(file, '.md'));
      if (c.src === 'docs/法律' && source.includes('【待填写')) drafts.push(repoPath);
    }
  }

  const images = path.join(repoRoot, 'docs/使用说明/images');
  await cp(images, path.join(outRoot, 'guide/images'), { recursive: true }).catch((err) => {
    if (err.code !== 'ENOENT') throw err;
  });

  await writeFile(
    path.join(outRoot, 'guide/index.md'),
    [
      '---',
      'title: 使用教程',
      'description: 即刻日志各功能的使用说明：安装、工作日志、笔记、备忘录、记账、同步、搜索与导出、Windows 版。',
      '---',
      '',
      '# 使用教程',
      '',
      '从安装到每个模块的用法。遇到问题时，也可以先看对应章节末尾的说明。',
      '',
      '<GuideCards />',
      '',
    ].join('\n'),
    'utf8',
  );

  changelog.sort(semverDesc);
  await mkdir(path.join(outRoot, 'changelog'), { recursive: true });
  await writeFile(
    path.join(outRoot, 'changelog/index.md'),
    [
      '---',
      'title: 更新日志',
      '---',
      '',
      '# 更新日志',
      '',
      '每个版本的新功能、改进与修复。安装包见[下载页](/download)，更早的版本见 [GitHub Release](' +
        `${repoUrl}/releases)。`,
      '',
      ...changelog.map((v) => `- [${v}](/changelog/${v})`),
      '',
    ].join('\n'),
    'utf8',
  );
  return { guide, changelog, drafts };
}
