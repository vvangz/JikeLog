<script setup lang="ts">
import JkIcon from '../JkIcon.vue';

const modules = [
  {
    icon: 'briefcase',
    title: '工作日志',
    desc: '按日期记下工作地点与内容，回顾一周、一月做了什么。',
    points: ['Markdown 排版，自动保存', '附件、修订历史随时找回', '可关联相关笔记'],
    link: '/guide/worklog',
  },
  {
    icon: 'notebook',
    title: '笔记',
    desc: '富文本与 Markdown 两种写法，整理知识和资料。',
    points: ['代码块、表格、待办清单', '文件夹、标签、收藏、置顶', '图片、PDF、录音附件'],
    link: '/guide/notes',
  },
  {
    icon: 'alarm',
    title: '备忘录',
    desc: '写下要做的事和时间，到点准时提醒。',
    points: ['提前 5 分钟到 1 天多档提醒', '日历视图一览全月安排', '应用关闭后照常通知'],
    link: '/guide/memos',
  },
  {
    icon: 'wallet',
    title: '记账',
    desc: '收入、支出、转账、借贷，钱的去向一目了然。',
    points: ['多账户余额自动统计', '分类占比图表', '借贷待收待还，逾期标出'],
    link: '/guide/ledger',
  },
] as const;
</script>

<template>
  <section id="features" class="jk-section">
    <div class="jk-section__inner">
      <span class="jk-eyebrow">四个模块</span>
      <h2 class="jk-h2">一个应用，管好工作与生活的记录</h2>
      <p class="jk-lead">不用在几个应用之间来回切换。四个模块共用同一个账号、同一套搜索与同步。</p>
      <div class="grid jk-hairline-grid">
        <a v-for="(m, i) in modules" :key="m.title" class="cell" :href="m.link">
          <div class="cell__top">
            <JkIcon :name="m.icon" :size="22" />
            <span class="no">0{{ i + 1 }}</span>
          </div>
          <h3>{{ m.title }}</h3>
          <p>{{ m.desc }}</p>
          <ul>
            <li v-for="p in m.points" :key="p">{{ p }}</li>
          </ul>
          <span class="more">查看教程 <JkIcon name="arrow" :size="14" /></span>
        </a>
      </div>
    </div>
  </section>
</template>

<style scoped>
.grid {
  grid-template-columns: repeat(4, 1fr);
  margin-top: 64px;
}
.cell {
  display: flex;
  flex-direction: column;
  padding: 32px 28px 28px;
  text-decoration: none;
  color: inherit;
  transition: background-color 0.2s;
}
.cell:hover {
  background: var(--vp-c-bg-alt);
}
.cell:focus-visible {
  outline: 2px solid var(--jk-accent);
  outline-offset: -2px;
}
.cell__top {
  display: flex;
  justify-content: space-between;
  align-items: center;
  color: var(--vp-c-text-1);
}
.no {
  font-size: 13px;
  font-variant-numeric: tabular-nums;
  color: var(--vp-c-text-3);
}
h3 {
  margin: 48px 0 10px;
  font-size: 20px;
  font-weight: 600;
  color: var(--vp-c-text-1);
}
p {
  margin: 0;
  font-size: 14.5px;
  line-height: 1.75;
  color: var(--vp-c-text-2);
}
ul {
  list-style: none;
  padding: 18px 0 0;
  margin: 18px 0 28px;
  border-top: 1px solid var(--vp-c-divider);
  display: flex;
  flex-direction: column;
  gap: 8px;
}
li {
  font-size: 14px;
  color: var(--vp-c-text-2);
}
.more {
  margin-top: auto;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 14px;
  font-weight: 500;
  color: var(--vp-c-text-1);
}
.more :deep(svg) {
  transition: transform 0.2s;
}
.cell:hover .more :deep(svg) {
  transform: translateX(3px);
}
@media (max-width: 1080px) {
  .grid {
    grid-template-columns: repeat(2, 1fr);
  }
}
@media (max-width: 560px) {
  .grid {
    grid-template-columns: 1fr;
    margin-top: 48px;
  }
  .cell {
    padding: 28px 22px 24px;
  }
  h3 {
    margin-top: 28px;
  }
}
</style>
