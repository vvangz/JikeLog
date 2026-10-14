import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (rel) => readFile(new URL(rel, import.meta.url), 'utf8');

test('下载页的证书指纹与使用说明第 9 章一致（更换证书时两处须同步修改）', async () => {
  const vue = await read('../.vitepress/theme/components/DownloadCards.vue');
  const guide = await read('../../../docs/使用说明/09-Windows版.md');
  const inPage = vue.match(/const CERT_SHA1 = '([0-9A-F]{40})'/)?.[1];
  const inGuide = guide.match(/SHA-1：`([0-9A-F]{40})`/)?.[1];
  assert.ok(inPage && inGuide, '两处都能找到指纹');
  assert.equal(inPage, inGuide);
});
