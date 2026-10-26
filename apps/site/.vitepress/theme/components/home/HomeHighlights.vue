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
      <span v-reveal class="jk-eyebrow">细节</span>
      <h2 v-reveal="60" class="jk-h2">记录这件事，应该顺手</h2>
      <p v-reveal="120" class="jk-lead">从同步、搜索到导出，日常会用到的功能都考虑到了。</p>
      <div class="grid">
        <a v-for="(it, i) in items" :key="it.title" v-reveal="(i % 3) * 90" class="item" :href="it.link">
          <JkIcon :name="it.icon" :size="22" />
          <h3>{{ it.title }}</h3>
          <p>{{ it.desc }}</p>
        </a>
      </div>
    </div>
  </section>
</template>

<style scoped>
.alt {
  background: var(--vp-c-bg-alt);
  border-top: 1px solid var(--vp-c-divider);
  border-bottom: 1px solid var(--vp-c-divider);
}
.grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 56px 48px;
  margin-top: 72px;
}
.item {
  display: block;
  text-decoration: none;
  color: inherit;
}
.item :deep(svg) {
  color: var(--vp-c-text-1);
}
.item:focus-visible {
  outline: 2px solid var(--jk-accent);
  outline-offset: 6px;
  border-radius: 4px;
}
h3 {
  margin: 20px 0 8px;
  font-size: 17px;
  font-weight: 600;
  color: var(--vp-c-text-1);
  transition: color 0.2s;
}
.item:hover h3 {
  color: var(--jk-accent);
}
p {
  margin: 0;
  font-size: 14.5px;
  line-height: 1.75;
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
    gap: 40px;
    margin-top: 48px;
  }
}
</style>
