import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { anchorFor, assertSafeMarkdown, rewriteLinks, siteRouteFor, syncDocs } from '../lib/docs.mjs';

const REPO_URL = 'https://github.com/vvangz/JikeLog';
const rw = (md, from = 'docs/使用说明/01-快速上手.md') => rewriteLinks(md, from, { repoUrl: REPO_URL });

test('siteRouteFor 把文档路径映射为官网地址', () => {
  assert.equal(siteRouteFor('docs/使用说明/03-工作日志.md'), '/guide/worklog');
  assert.equal(siteRouteFor('docs/使用说明/09-Windows版.md'), '/guide/windows');
  assert.equal(siteRouteFor('docs/使用说明'), '/guide/');
  assert.equal(siteRouteFor('docs/发布说明/v1.0.0.md'), '/changelog/v1.0.0');
  assert.equal(siteRouteFor('docs/法律/隐私政策.md'), '/privacy');
  assert.equal(siteRouteFor('docs/法律/用户协议.md'), '/terms');
  assert.equal(siteRouteFor('docs/管理员手册.md'), null);
});

test('siteRouteFor 遇到没有登记网址的使用说明章节时报错，避免新章节悄悄缺席', () => {
  assert.throws(() => siteRouteFor('docs/使用说明/11-新章节.md'), /11-新章节/);
});

test('anchorFor 与 VitePress 生成的标题锚点一致', () => {
  assert.equal(anchorFor('5-修订历史与冲突版本'), '_5-修订历史与冲突版本');
  assert.equal(anchorFor('同步时机'), '同步时机');
});

test('站内章节链接改为官网地址，保留锚点', () => {
  assert.equal(rw('见[工作日志](03-工作日志.md)。'), '见[工作日志](/guide/worklog)。');
  assert.equal(
    rw('[历史](03-工作日志.md#5-修订历史与冲突版本)'),
    '[历史](/guide/worklog#_5-修订历史与冲突版本)',
  );
  assert.equal(rw('[说明](../使用说明)', 'docs/发布说明/v1.0.0.md'), '[说明](/guide/)');
  assert.equal(
    rw('[上手](../使用说明/01-快速上手.md)', 'docs/发布说明/v1.0.0.md'),
    '[上手](/guide/quick-start)',
  );
});

test('不在官网上的仓库文件改为 GitHub 链接', () => {
  assert.equal(
    rw('[证书](../../deploy/windows/jikelog-windows.cer)', 'docs/使用说明/09-Windows版.md'),
    `[证书](${REPO_URL}/blob/main/deploy/windows/jikelog-windows.cer)`,
  );
  assert.equal(
    rw('[手册](../管理员手册.md)'),
    `[手册](${REPO_URL}/blob/main/docs/${encodeURIComponent('管理员手册.md')})`,
  );
});

test('图片、外链、页内锚点与代码块保持不变', () => {
  const md = [
    '![登录](images/01-login.png)',
    '[外链](https://example.com/a.md)',
    '[本页](#安装)',
    '```',
    '[示例](03-工作日志.md)',
    '```',
  ].join('\n');
  assert.equal(rw(md), md);
});

test('指向官网自身的绝对地址改为站内路径', () => {
  const md = '[下载页](https://www.pingvv.top/download#windows)';
  assert.equal(rewriteLinks(md, 'docs/使用说明/09-Windows版.md', { repoUrl: REPO_URL, siteUrl: 'https://www.pingvv.top' }), '[下载页](/download#windows)');
  assert.equal(rw('[首页](https://www.pingvv.top)'), '[首页](https://www.pingvv.top)', '未传 siteUrl 时不改');
});

test('页内的数字锚点同样改为 VitePress 写法', () => {
  assert.equal(rw('[见上文](#5-修订历史)'), '[见上文](#_5-修订历史)');
});

test('官网地址后直接跟锚点时指向首页', () => {
  const md = '[功能](https://www.pingvv.top#features)';
  assert.equal(rewriteLinks(md, 'docs/使用说明/01-快速上手.md', { repoUrl: REPO_URL, siteUrl: 'https://www.pingvv.top' }), '[功能](/#features)');
});

test('无法解码的百分号转义不让构建崩溃，按原样处理', () => {
  assert.equal(rw('[坏链接](../%E4%zz.md)'), `[坏链接](${REPO_URL}/blob/main/docs/${encodeURIComponent('%E4%zz.md')})`);
});

test('assertSafeMarkdown 拒绝文档中的脚本与危险 HTML，代码块与行内代码除外', () => {
  for (const bad of [
    '<script>alert(1)</script>',
    '<img src=x onerror="alert(1)">',
    '[点我](javascript:alert(1))',
    '<iframe src="https://evil"></iframe>',
    '<meta http-equiv="refresh" content="0;url=https://evil">',
    '<form action="https://evil"></form>',
    '<object data="x"></object>',
    '<base href="https://evil/">',
  ]) {
    assert.throws(() => assertSafeMarkdown(`正文\n${bad}\n`, 'x.md'), /x\.md/, bad);
  }
  assert.doesNotThrow(() =>
    assertSafeMarkdown('```html\n<script>示例</script>\n```\n行内 `<script>` 与 `onload=` 只是文字\n', 'x.md'),
  );
});

test('带标题的链接只替换地址', () => {
  assert.equal(rw('[笔记](05-笔记.md "笔记")'), '[笔记](/guide/notes "笔记")');
});

test('syncDocs 生成教程、更新日志与法律页面，并复制图片', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'jikelog-site-'));
  const repo = path.join(root, 'repo');
  const out = path.join(root, 'out');
  await mkdir(path.join(repo, 'docs/使用说明/images'), { recursive: true });
  await mkdir(path.join(repo, 'docs/发布说明'), { recursive: true });
  await mkdir(path.join(repo, 'docs/法律'), { recursive: true });
  await writeFile(
    path.join(repo, 'docs/使用说明/README.md'),
    [
      '# 目录',
      '',
      '| 章节 | 内容 | 上线版本 |',
      '|---|---|---|',
      '| [01 快速上手](01-快速上手.md) | 安装、注册 | v0.2.0 |',
      '| 10 常见问题 | 待补充 | 待补充 |',
      '',
    ].join('\n'),
  );
  await writeFile(path.join(repo, 'docs/使用说明/01-快速上手.md'), '# 快速上手\n\n[笔记](05-笔记.md)\n');
  await writeFile(path.join(repo, 'docs/使用说明/05-笔记.md'), '# 笔记\n');
  await writeFile(path.join(repo, 'docs/使用说明/images/a.png'), 'png');
  await writeFile(path.join(repo, 'docs/发布说明/v1.0.0.md'), '# v1.0.0\n');
  await writeFile(path.join(repo, 'docs/发布说明/v0.9.0.md'), '# v0.9.0\n');
  await writeFile(path.join(repo, 'docs/发布说明/v1.0.0-rc.1.md'), '# v1.0.0-rc.1\n');
  await writeFile(path.join(repo, 'docs/发布说明/v0.10.0.md'), '# v0.10.0\n');
  await writeFile(path.join(repo, 'docs/发布说明/README.md'), '# 发布说明\n');
  await writeFile(path.join(repo, 'docs/法律/隐私政策.md'), '# 隐私政策\n\n运营者：【待填写：运营者名称】\n');
  await writeFile(path.join(repo, 'docs/法律/用户协议.md'), '# 用户协议\n');

  // 上次生成的旧文件应被清掉
  await mkdir(path.join(out, 'guide'), { recursive: true });
  await writeFile(path.join(out, 'guide/stale.md'), '# 旧\n');

  const result = await syncDocs({ repoRoot: repo, outRoot: out, repoUrl: REPO_URL });

  assert.deepEqual((await readdir(path.join(out, 'guide'))).sort(), ['images', 'index.md', 'notes.md', 'quick-start.md']);
  assert.match(await readFile(path.join(out, 'guide/index.md'), 'utf8'), /<GuideCards \/>/);
  assert.match(await readFile(path.join(out, 'guide/quick-start.md'), 'utf8'), /\[笔记\]\(\/guide\/notes\)/);
  assert.equal(await readFile(path.join(out, 'guide/images/a.png'), 'utf8'), 'png');
  assert.ok(await readFile(path.join(out, 'privacy.md'), 'utf8'));
  assert.ok(await readFile(path.join(out, 'terms.md'), 'utf8'));
  assert.deepEqual(result.drafts, ['docs/法律/隐私政策.md'], '列出还有待填写内容的法律文本');
  assert.deepEqual(result.changelog, ['v1.0.0', 'v1.0.0-rc.1', 'v0.10.0', 'v0.9.0'], '新版本在前，预发布版排在正式版之后，README 不算版本');
  assert.deepEqual(
    result.guide,
    [
      { link: '/guide/quick-start', title: '快速上手', desc: '安装、注册' },
      { link: '/guide/notes', title: '笔记', desc: '' },
    ],
  );
  const index = await readFile(path.join(out, 'changelog/index.md'), 'utf8');
  assert.ok(index.indexOf('v1.0.0') < index.indexOf('v0.9.0'), '新版本在前');
});
