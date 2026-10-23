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
      <div class="jk-center">
        <span class="jk-eyebrow">多端可用</span>
        <h2 class="jk-h2">手机和电脑，用同一个账号</h2>
        <p class="jk-lead">在任何一台设备上的修改，几秒内出现在其他设备上。</p>
      </div>
      <div class="grid">
        <div v-for="p in platforms" :key="p.id" class="card">
          <div class="card__head">
            <span class="card__icon"><JkIcon :name="p.icon" :size="28" /></span>
            <div>
              <h3>{{ p.name }}</h3>
              <span class="req">{{ p.req }}</span>
            </div>
          </div>
          <ul>
            <li v-for="n in p.notes" :key="n"><JkIcon name="check" :size="16" />{{ n }}</li>
          </ul>
          <div class="card__actions">
            <a class="jk-btn jk-btn--primary" :href="`/download#${p.id}`"><JkIcon name="download" />下载</a>
            <a class="jk-btn jk-btn--ghost" :href="p.guide"><JkIcon name="book" />安装说明</a>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 24px;
  max-width: 920px;
  margin: 48px auto 0;
}
.card {
  padding: 30px;
  border-radius: 20px;
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
  box-shadow: var(--jk-card-shadow);
  background-image: var(--jk-gradient-soft);
}
.card__head {
  display: flex;
  align-items: center;
  gap: 16px;
}
.card__icon {
  display: grid;
  place-items: center;
  width: 56px;
  height: 56px;
  border-radius: 16px;
  color: var(--vp-c-brand-1);
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
}
h3 {
  margin: 0;
  font-size: 22px;
  font-weight: 800;
  color: var(--vp-c-text-1);
}
.req {
  font-size: 14px;
  color: var(--vp-c-text-2);
}
ul {
  list-style: none;
  padding: 0;
  margin: 22px 0 26px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
li {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 15px;
  color: var(--vp-c-text-1);
}
li :deep(svg) {
  color: var(--vp-c-brand-2);
  flex: none;
}
.card__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}
@media (max-width: 760px) {
  .grid {
    grid-template-columns: 1fr;
  }
  .card {
    padding: 24px 20px;
  }
}
</style>
