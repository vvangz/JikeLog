<script setup lang="ts">
import JkIcon from '../JkIcon.vue';

const modules = [
  {
    icon: 'briefcase',
    color: 'var(--jk-mod-worklog)',
    title: '工作日志',
    desc: '按日期记下工作地点与内容，回顾一周、一月做了什么。',
    points: ['Markdown 排版，自动保存', '附件、修订历史随时找回', '可关联相关笔记'],
    link: '/guide/worklog',
  },
  {
    icon: 'notebook',
    color: 'var(--jk-mod-notes)',
    title: '笔记',
    desc: '富文本与 Markdown 两种写法，整理知识和资料。',
    points: ['代码块、表格、待办清单', '文件夹、标签、收藏、置顶', '图片、PDF、录音附件'],
    link: '/guide/notes',
  },
  {
    icon: 'alarm',
    color: 'var(--jk-mod-memos)',
    title: '备忘录',
    desc: '写下要做的事和时间，到点准时提醒。',
    points: ['提前 5 分钟到 1 天多档提醒', '日历视图一览全月安排', '应用关闭后照常通知'],
    link: '/guide/memos',
  },
  {
    icon: 'wallet',
    color: 'var(--jk-mod-ledger)',
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
      <div class="jk-center">
        <span class="jk-eyebrow">四个模块</span>
        <h2 class="jk-h2">一个应用，管好工作与生活的记录</h2>
        <p class="jk-lead">不用在几个应用之间来回切换。四个模块共用同一个账号、同一套搜索与同步。</p>
      </div>
      <div class="grid">
        <a v-for="m in modules" :key="m.title" class="card" :href="m.link" :style="{ '--c': m.color }">
          <span class="card__icon"><JkIcon :name="m.icon" /></span>
          <h3>{{ m.title }}</h3>
          <p>{{ m.desc }}</p>
          <ul>
            <li v-for="p in m.points" :key="p"><JkIcon name="check" :size="15" />{{ p }}</li>
          </ul>
          <span class="card__more">查看教程 <JkIcon name="arrow" :size="15" /></span>
        </a>
      </div>
    </div>
  </section>
</template>

<style scoped>
.grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
  margin-top: 48px;
}
.card {
  position: relative;
  display: flex;
  flex-direction: column;
  padding: 26px 24px 22px;
  border-radius: 18px;
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
  box-shadow: var(--jk-card-shadow);
  text-decoration: none;
  color: inherit;
  transition: transform 0.25s ease, box-shadow 0.25s ease, border-color 0.25s ease;
  overflow: hidden;
}
.card::before {
  content: '';
  position: absolute;
  inset: 0 0 auto;
  height: 3px;
  background: var(--c);
  opacity: 0.85;
}
.card:hover {
  transform: translateY(-4px);
  box-shadow: var(--jk-card-shadow-hover);
  border-color: color-mix(in srgb, var(--c) 45%, var(--vp-c-divider));
}
.card:focus-visible {
  outline: 2px solid var(--c);
  outline-offset: 3px;
}
.card__icon {
  display: grid;
  place-items: center;
  width: 46px;
  height: 46px;
  border-radius: 14px;
  color: var(--c);
  background: color-mix(in srgb, var(--c) 13%, transparent);
}
h3 {
  margin: 18px 0 8px;
  font-size: 20px;
  font-weight: 700;
  color: var(--vp-c-text-1);
}
p {
  margin: 0;
  font-size: 14.5px;
  line-height: 1.7;
  color: var(--vp-c-text-2);
}
ul {
  list-style: none;
  padding: 0;
  margin: 16px 0 18px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
li {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  color: var(--vp-c-text-1);
}
li :deep(svg) {
  color: var(--c);
  flex: none;
}
.card__more {
  margin-top: auto;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 14px;
  font-weight: 600;
  color: var(--c);
}
@media (max-width: 1080px) {
  .grid {
    grid-template-columns: repeat(2, 1fr);
  }
}
@media (max-width: 560px) {
  .grid {
    grid-template-columns: 1fr;
  }
}
</style>
