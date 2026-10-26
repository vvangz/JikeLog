<script setup lang="ts">
// 下载卡片：从本站 /download/latest.json 读取最新版本（发布时由部署工作流生成），
// 读不到时退回 GitHub Release 页面。
import { computed, onMounted, ref } from 'vue';
import { formatSize, parseManifest } from '../../../lib/manifest.mjs';
import JkIcon from './JkIcon.vue';

const RELEASES = 'https://github.com/vvangz/JikeLog/releases/latest';
// Windows 安装包签名证书的 SHA-1 指纹：优先显示 latest.json 中的（部署时已与仓库变量核对），读不到时显示这里的。
// 更换证书时同步修改此处与使用说明第 9 章（test/site.test.mjs 校验两处一致）
const CERT_SHA1 = 'F44C3F6641E3DB7CE741AB769F6BE2063E4AB890';

type Manifest = NonNullable<ReturnType<typeof parseManifest>>;
const state = ref<'loading' | 'ready' | 'unavailable'>('loading');
const manifest = ref<Manifest | null>(null);
const copied = ref('');

onMounted(async () => {
  try {
    const res = await fetch('/download/latest.json', { cache: 'no-cache' });
    manifest.value = res.ok ? parseManifest(await res.json()) : null;
  } catch {
    manifest.value = null;
  }
  state.value = manifest.value ? 'ready' : 'unavailable';
});

const certSha1 = computed(() => manifest.value?.files.windowsCert?.sha1 ?? CERT_SHA1);

const date = computed(() =>
  manifest.value?.publishedAt.toLocaleDateString('zh-CN', { year: 'numeric', month: 'long', day: 'numeric' }),
);

const cards = computed(() => [
  {
    id: 'android',
    icon: 'android' as const,
    name: 'Android 版',
    req: 'Android 8.0 及以上',
    file: manifest.value?.files.android,
    guide: '/guide/quick-start',
  },
  {
    id: 'windows',
    icon: 'windows' as const,
    name: 'Windows 版',
    req: 'Windows 10（1809）/ 11，64 位',
    file: manifest.value?.files.windows,
    guide: '/guide/windows',
  },
]);

async function copy(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    copied.value = text;
    setTimeout(() => (copied.value = ''), 1600);
  } catch {
    // 不支持剪贴板时用户可以手动选择文字复制
  }
}
</script>

<template>
  <div class="dl">
    <p v-if="state === 'ready'" class="dl__meta">
      最新版本 <strong>v{{ manifest!.version }}</strong> · 发布于 {{ date }} ·
      <a :href="manifest!.releaseUrl" target="_blank" rel="noopener noreferrer">发布说明与全部文件</a>
    </p>
    <p v-else-if="state === 'unavailable'" class="dl__notice">
      暂时无法从本站获取安装包，请从 <a :href="RELEASES" target="_blank" rel="noopener noreferrer">GitHub Release</a> 下载。
    </p>

    <noscript>
      <p class="dl__notice">
        浏览器未启用 JavaScript，请从 <a href="https://github.com/vvangz/JikeLog/releases/latest">GitHub Release</a> 下载。
      </p>
    </noscript>
    <div class="dl__grid">
      <section v-for="c in cards" :id="c.id" :key="c.id" class="card">
        <div class="card__head">
          <span class="card__icon"><JkIcon :name="c.icon" :size="30" /></span>
          <div>
            <h2>{{ c.name }}</h2>
            <span class="req">{{ c.req }}</span>
          </div>
        </div>

        <div class="card__actions">
          <!-- 读取清单前不显示下载按钮，避免先出现 GitHub 链接再变成本站链接 -->
          <span v-if="state === 'loading'" class="jk-btn jk-btn--ghost loading" aria-live="polite">
            <JkIcon name="sync" />正在获取最新版本…
          </span>
          <a v-else-if="c.file" class="jk-btn jk-btn--primary" :href="c.file.url" download>
            <JkIcon name="download" />下载 {{ c.file.name.endsWith('.apk') ? 'APK' : 'MSIX' }}
            <span class="size">{{ formatSize(c.file.size) }}</span>
          </a>
          <a v-else class="jk-btn jk-btn--primary" :href="RELEASES" target="_blank" rel="noopener noreferrer">
            <JkIcon name="github" />前往 GitHub 下载
          </a>
          <a class="guide" :href="c.guide">安装说明 <JkIcon name="arrow" :size="14" /></a>
        </div>

        <!-- 必须做的一步保持可见；指纹等核对信息收进下方的"校验信息" -->
        <p v-if="c.id === 'windows'" class="note">
          <JkIcon name="shield" :size="16" />
          <span>
            首次安装前需导入签名证书（只需一次）<br />
            <a v-if="manifest?.files.windowsCert" :href="manifest.files.windowsCert.url" download>下载证书</a>
            <span v-if="manifest?.files.windowsCert" class="sep">·</span>
            <a href="/guide/windows">查看步骤</a>
          </span>
        </p>

        <details v-if="c.file || c.id === 'windows'" class="verify">
          <summary>校验信息</summary>
          <p class="verify__hint">用于确认文件完整、未被篡改。</p>
          <dl>
            <template v-if="c.file">
              <dt>文件名</dt>
              <dd><code>{{ c.file.name }}</code></dd>
              <dt>SHA-256</dt>
              <dd class="hash">
                <code>{{ c.file.sha256 }}</code>
                <button type="button" class="copy" :aria-label="`复制 ${c.name} 的 SHA-256`" @click="copy(c.file.sha256)">
                  <JkIcon :name="copied === c.file.sha256 ? 'check' : 'copy'" :size="14" />
                </button>
              </dd>
            </template>
            <template v-if="c.id === 'windows'">
              <dt>证书指纹</dt>
              <dd class="hash">
                <code>{{ certSha1 }}</code>
                <button type="button" class="copy" aria-label="复制证书 SHA-1 指纹" @click="copy(certSha1)">
                  <JkIcon :name="copied === certSha1 ? 'check' : 'copy'" :size="14" />
                </button>
              </dd>
            </template>
          </dl>
        </details>

        <p class="backup">
          下载慢或失败？<a :href="manifest?.releaseUrl ?? RELEASES" target="_blank" rel="noopener noreferrer">从 GitHub 下载</a>
        </p>
      </section>
    </div>
  </div>
</template>

<style scoped>
.dl__meta,
.dl__notice {
  margin: 0 0 20px;
  font-size: 15px;
  color: var(--vp-c-text-2);
}
.dl__notice {
  padding: 12px 16px;
  border-radius: 12px;
  background: var(--vp-c-warning-soft);
  color: var(--vp-c-text-1);
}
.dl__grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 20px;
}
.card {
  display: flex;
  flex-direction: column;
  gap: 18px;
  padding: 32px;
  border-radius: 20px;
  border: 1px solid var(--vp-c-divider);
  background-color: var(--vp-c-bg);
  scroll-margin-top: calc(var(--vp-nav-height) + 24px);
}
.card:target {
  border-color: var(--vp-c-text-1);
}
.card__head {
  display: flex;
  align-items: center;
  gap: 14px;
}
.card__icon {
  display: grid;
  place-items: center;
  width: 52px;
  height: 52px;
  border-radius: 14px;
  color: var(--vp-c-text-1);
  background: var(--vp-c-bg-soft);
}
.vp-doc .card h2 {
  margin: 0;
  padding: 0;
  border: 0;
  font-size: 21px;
  font-weight: 600;
  letter-spacing: -0.01em;
}
.req {
  font-size: 14px;
  color: var(--vp-c-text-2);
}
.card__actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px 20px;
}
/* 安装说明：文字链接，放得下时与下载按钮同一行 */
.vp-doc .guide {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 14px;
  font-weight: 500;
  color: var(--vp-c-text-1);
  text-decoration: none;
}
.guide :deep(svg) {
  transition: transform 0.2s;
}
.guide:hover :deep(svg) {
  transform: translateX(3px);
}
.loading {
  cursor: progress;
  color: var(--vp-c-text-2) !important;
}
.size {
  font-weight: 500;
  opacity: 0.85;
  font-size: 13px;
}
.note {
  display: flex;
  gap: 10px;
  margin: 0;
  font-size: 14px;
  line-height: 1.7;
  color: var(--vp-c-text-2);
}
.note :deep(svg) {
  flex: none;
  margin-top: 4px;
  color: var(--vp-c-text-1);
}
.note a {
  font-weight: 500;
  white-space: nowrap;
}
.sep {
  margin: 0 8px;
  color: var(--vp-c-text-3);
}
/* 校验信息：默认收起，放在卡片底部 */
.verify {
  margin-top: auto;
  padding-top: 16px;
  border-top: 1px solid var(--vp-c-divider);
}
.verify summary {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  list-style: none;
  cursor: pointer;
  font-size: 13px;
  color: var(--vp-c-text-2);
  transition: color 0.2s;
}
.verify summary::-webkit-details-marker {
  display: none;
}
/* 右侧的小三角，展开后朝下 */
.verify summary::after {
  content: '';
  width: 6px;
  height: 6px;
  border-right: 1.5px solid currentColor;
  border-bottom: 1.5px solid currentColor;
  transform: rotate(-45deg);
  transition: transform 0.2s;
}
.verify[open] summary::after {
  transform: rotate(45deg);
}
.verify summary:hover {
  color: var(--vp-c-text-1);
}
.verify summary:focus-visible {
  outline: 2px solid var(--jk-accent);
  outline-offset: 3px;
  border-radius: 4px;
}
.verify__hint {
  margin: 12px 0 10px !important;
  font-size: 13px;
  color: var(--vp-c-text-3);
}
.verify dl {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 8px 14px;
  margin: 0;
  font-size: 13px;
}
.verify dt {
  color: var(--vp-c-text-3);
}
.verify dd {
  margin: 0;
  min-width: 0;
}
.verify code {
  font-size: 12px;
  word-break: break-all;
}
.hash {
  display: flex;
  align-items: flex-start;
  gap: 6px;
}
.copy {
  flex: none;
  display: grid;
  place-items: center;
  width: 26px;
  height: 26px;
  border-radius: 7px;
  color: var(--vp-c-text-3);
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg);
  cursor: pointer;
  transition: color 0.2s, border-color 0.2s;
}
.copy:hover {
  color: var(--vp-c-text-1);
  border-color: var(--jk-line-strong);
}
.backup {
  margin: 0 !important;
  font-size: 13px;
  color: var(--vp-c-text-3);
}
@media (max-width: 820px) {
  .dl__grid {
    grid-template-columns: 1fr;
  }
  .card {
    padding: 22px 18px;
  }
}
</style>
