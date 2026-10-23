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
          <a class="jk-btn jk-btn--ghost" :href="c.guide"><JkIcon name="book" />安装说明</a>
        </div>

        <dl v-if="c.file" class="facts">
          <dt>文件名</dt>
          <dd><code>{{ c.file.name }}</code></dd>
          <dt>SHA-256</dt>
          <dd class="hash">
            <code>{{ c.file.sha256 }}</code>
            <button type="button" class="copy" :aria-label="`复制 ${c.name} 的 SHA-256`" @click="copy(c.file.sha256)">
              <JkIcon :name="copied === c.file.sha256 ? 'check' : 'copy'" :size="15" />
            </button>
          </dd>
        </dl>

        <div v-if="c.id === 'windows'" class="cert">
          <p>
            <strong>首次安装前</strong>需要信任即刻日志的签名证书（只做一次）。核对指纹后按
            <a href="/guide/windows">安装说明</a> 导入。
          </p>
          <p class="cert__fp">证书 SHA-1 指纹：<code>{{ certSha1 }}</code></p>
          <a v-if="manifest?.files.windowsCert" class="cert__link" :href="manifest.files.windowsCert.url" download>
            <JkIcon name="shield" :size="16" />下载证书 {{ manifest.files.windowsCert.name }}
          </a>
        </div>

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
  padding: 26px;
  border-radius: 20px;
  border: 1px solid var(--vp-c-divider);
  background-color: var(--vp-c-bg);
  background-image: var(--jk-gradient-soft);
  box-shadow: var(--jk-card-shadow);
  scroll-margin-top: calc(var(--vp-nav-height) + 24px);
}
.card:target {
  border-color: var(--vp-c-brand-2);
}
.card__head {
  display: flex;
  align-items: center;
  gap: 14px;
}
.card__icon {
  display: grid;
  place-items: center;
  width: 54px;
  height: 54px;
  border-radius: 16px;
  color: var(--vp-c-brand-1);
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
}
.vp-doc .card h2 {
  margin: 0;
  padding: 0;
  border: 0;
  font-size: 21px;
  letter-spacing: 0;
}
.req {
  font-size: 14px;
  color: var(--vp-c-text-2);
}
.card__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
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
.facts {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 6px 12px;
  margin: 0;
  font-size: 13px;
}
.facts dt {
  color: var(--vp-c-text-2);
}
.facts dd {
  margin: 0;
  min-width: 0;
}
.facts code,
.cert code {
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
  width: 28px;
  height: 28px;
  border-radius: 8px;
  color: var(--vp-c-text-2);
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg);
  cursor: pointer;
}
.copy:hover {
  color: var(--vp-c-brand-1);
  border-color: var(--vp-c-brand-2);
}
.cert {
  padding: 14px 16px;
  border-radius: 14px;
  background: var(--vp-c-bg);
  border: 1px dashed var(--vp-c-divider);
  font-size: 14px;
}
.cert p {
  margin: 0;
  line-height: 1.7;
}
.cert__fp {
  margin-top: 6px !important;
  color: var(--vp-c-text-2);
}
.cert__link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 10px;
  font-weight: 600;
}
.backup {
  margin: auto 0 0 !important;
  font-size: 13px;
  color: var(--vp-c-text-2);
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
