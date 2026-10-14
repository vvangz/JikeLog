<script setup lang="ts">
import JkIcon from '../JkIcon.vue';

const items = [
  { icon: 'sync', title: '多设备实时同步', desc: '手机上记、电脑上看。同时修改同一条记录时按字段合并，冲突的版本保留在修订历史里。', link: '/guide/sync' },
  { icon: 'offline', title: '离线也能用', desc: '地铁里、飞机上照常记录，恢复网络后自动同步。', link: '/guide/sync' },
  { icon: 'search', title: '全局搜索', desc: '一个搜索框找遍日志、笔记、备忘和账目，可按模块与时间筛选。', link: '/guide/search-export' },
  { icon: 'export', title: '随时导出', desc: '导出为 Markdown、Excel 可打开的表格和日历文件，可连同附件一起带走。', link: '/guide/search-export' },
  { icon: 'moon', title: '浅色与深色主题', desc: '跟随系统或手动切换，字号可调，晚上看也不刺眼。', link: '/guide/interface' },
  { icon: 'keyboard', title: '电脑上更高效', desc: 'Windows 版窗口可自由缩放，Ctrl+F 搜索、Ctrl+N 新建。', link: '/guide/windows' },
] as const;
</script>

<template>
  <section class="jk-section alt">
    <div class="jk-section__inner">
      <div class="jk-center">
        <span class="jk-eyebrow">贴心细节</span>
        <h2 class="jk-h2">记录这件事，应该顺手</h2>
        <p class="jk-lead">从同步、搜索到导出，日常会用到的功能都考虑到了。</p>
      </div>
      <div class="grid">
        <a v-for="it in items" :key="it.title" class="item" :href="it.link">
          <span class="item__icon"><JkIcon :name="it.icon" :size="22" /></span>
          <div>
            <h3>{{ it.title }}</h3>
            <p>{{ it.desc }}</p>
          </div>
        </a>
      </div>
    </div>
  </section>
</template>

<style scoped>
.alt {
  background: var(--vp-c-bg-alt);
}
.grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
  margin-top: 48px;
}
.item {
  display: flex;
  gap: 16px;
  padding: 22px;
  border-radius: 16px;
  text-decoration: none;
  color: inherit;
  border: 1px solid transparent;
  transition: background-color 0.2s, border-color 0.2s;
}
.item:hover {
  background: var(--vp-c-bg);
  border-color: var(--vp-c-divider);
}
.item:focus-visible {
  outline: 2px solid var(--vp-c-brand-2);
  outline-offset: 2px;
}
.item__icon {
  display: grid;
  place-items: center;
  flex: none;
  width: 44px;
  height: 44px;
  border-radius: 12px;
  color: #fff;
  background: var(--jk-gradient-strong);
  box-shadow: 0 8px 18px -10px rgba(13, 148, 136, 0.8);
}
h3 {
  margin: 2px 0 6px;
  font-size: 17px;
  font-weight: 700;
  color: var(--vp-c-text-1);
}
p {
  margin: 0;
  font-size: 14.5px;
  line-height: 1.7;
  color: var(--vp-c-text-2);
}
@media (max-width: 960px) {
  .grid {
    grid-template-columns: repeat(2, 1fr);
  }
}
@media (max-width: 600px) {
  .grid {
    grid-template-columns: 1fr;
  }
  .item {
    padding: 16px 4px;
  }
}
</style>
