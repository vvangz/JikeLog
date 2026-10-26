<script setup lang="ts">
import JkIcon from '../JkIcon.vue';

const platforms = [
  {
    id: 'android',
    icon: 'android',
    name: 'Android',
    req: 'Android 8.0 及以上',
    notes: ['APK 安装包，覆盖安装即可升级', '本地通知按时提醒', '可同步备忘到系统日历'],
    guide: '/guide/quick-start',
  },
  {
    id: 'windows',
    icon: 'windows',
    name: 'Windows',
    req: 'Windows 10（1809）及以上 64 位',
    notes: ['MSIX 安装包，首次安装前信任证书', 'Windows 通知按时提醒', '大窗口布局与键盘快捷键'],
    guide: '/guide/windows',
  },
] as const;
</script>

<template>
  <section class="jk-section">
    <div class="jk-section__inner">
      <span v-reveal class="jk-eyebrow">多端可用</span>
      <h2 v-reveal="60" class="jk-h2">手机和电脑，用同一个账号</h2>
      <p v-reveal="120" class="jk-lead">在任何一台设备上的修改，几秒内出现在其他设备上。</p>
      <div v-reveal="180" class="grid jk-hairline-grid">
        <div v-for="p in platforms" :key="p.id" class="card">
          <JkIcon :name="p.icon" :size="28" />
          <h3>{{ p.name }}</h3>
          <span class="req">{{ p.req }}</span>
          <ul>
            <li v-for="n in p.notes" :key="n">{{ n }}</li>
          </ul>
          <div class="card__actions">
            <a class="jk-btn jk-btn--primary" :href="`/download#${p.id}`"><JkIcon name="download" />下载</a>
            <a class="jk-btn jk-btn--ghost" :href="p.guide">安装说明</a>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.grid {
  grid-template-columns: repeat(2, 1fr);
  margin-top: 64px;
}
.card {
  padding: 40px;
  display: flex;
  flex-direction: column;
}
.card > :deep(svg) {
  color: var(--vp-c-text-1);
}
h3 {
  margin: 32px 0 4px;
  font-size: 24px;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--vp-c-text-1);
}
.req {
  font-size: 14px;
  color: var(--vp-c-text-3);
}
ul {
  list-style: none;
  padding: 0;
  margin: 28px 0 36px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
li {
  font-size: 15px;
  color: var(--vp-c-text-2);
}
li::before {
  content: '—';
  margin-right: 10px;
  color: var(--vp-c-text-3);
}
.card__actions {
  margin-top: auto;
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}
@media (max-width: 760px) {
  .grid {
    grid-template-columns: 1fr;
    margin-top: 48px;
  }
  .card {
    padding: 28px 22px;
  }
}
</style>
