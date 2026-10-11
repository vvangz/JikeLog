import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('内容安全策略', () => {
  it('index.html 中内联脚本的哈希与 CSP 一致', () => {
    const html = readFileSync(resolve(process.cwd(), 'index.html'), 'utf-8');
    const script = /<script>([\s\S]*?)<\/script>/.exec(html)?.[1] ?? '';
    const hash = createHash('sha256').update(script, 'utf8').digest('base64');
    const csp = /http-equiv="Content-Security-Policy"\s+content="([^"]+)"/.exec(html)?.[1] ?? '';
    expect(csp).toContain(`'sha256-${hash}'`);
    expect(csp).toContain("object-src 'none'");
  });
});
