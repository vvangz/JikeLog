<script setup lang="ts">
// 全站页脚：站点导航、法律文本、版权与 ICP 备案号（备案号由构建时的 SITE_ICP 注入，未备案时不显示）
import { useLayout } from 'vitepress/theme';

const { hasSidebar } = useLayout();
const icp = __SITE_ICP__;
const year = new Date().getFullYear();

const columns = [
  {
    title: '产品',
    links: [
      { text: '下载', href: '/download' },
      { text: '更新日志', href: '/changelog/' },
      { text: '功能介绍', href: '/#features' },
    ],
  },
  {
    title: '帮助',
    links: [
      { text: '快速上手', href: '/guide/quick-start' },
      { text: 'Windows 版', href: '/guide/windows' },
      { text: '多设备同步', href: '/guide/sync' },
    ],
  },
  {
    title: '关于',
    links: [
      { text: '隐私政策', href: '/privacy' },
      { text: '用户协议', href: '/terms' },
      { text: '源代码', href: 'https://github.com/vvangz/JikeLog' },
    ],
  },
];
</script>

<template>
  <footer class="footer" :class="{ 'has-sidebar': hasSidebar }">
    <div class="footer__inner">
      <div class="brand">
        <a href="/" class="brand__name"><img src="/logo.svg" alt="" width="28" height="28" />即刻日志</a>
        <p>工作日志、笔记、备忘录、记账，<br />一个应用全部记下。</p>
      </div>
      <nav v-for="c in columns" :key="c.title" class="col" :aria-label="c.title">
        <h2>{{ c.title }}</h2>
        <a v-for="l in c.links" :key="l.text" :href="l.href">{{ l.text }}</a>
      </nav>
    </div>
    <div class="footer__bottom">
      <span>© {{ year }} 即刻日志 保留所有权利</span>
      <a v-if="icp" href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">{{ icp }}</a>
    </div>
  </footer>
</template>

<style scoped>
.footer {
  border-top: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg-alt);
  padding: 56px 24px 28px;
}
@media (min-width: 960px) {
  .footer.has-sidebar {
    padding-left: calc(var(--vp-sidebar-width) + 32px);
  }
}
@media (min-width: 1440px) {
  .footer.has-sidebar {
    padding-left: calc((100vw - var(--vp-layout-max-width)) / 2 + var(--vp-sidebar-width) + 32px);
  }
}
.footer__inner {
  max-width: 1152px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: 1.6fr repeat(3, 1fr);
  gap: 32px;
}
.brand__name {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  font-size: 18px;
  font-weight: 800;
  color: var(--vp-c-text-1);
  text-decoration: none;
}
.brand p {
  margin: 12px 0 0;
  font-size: 14px;
  line-height: 1.8;
  color: var(--vp-c-text-2);
}
.col {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.col h2 {
  margin: 0 0 4px;
  font-size: 14px;
  font-weight: 700;
  color: var(--vp-c-text-1);
}
.col a {
  font-size: 14px;
  color: var(--vp-c-text-2);
  text-decoration: none;
  width: fit-content;
}
.col a:hover {
  color: var(--vp-c-brand-1);
}
.footer__bottom {
  max-width: 1152px;
  margin: 40px auto 0;
  padding-top: 22px;
  border-top: 1px solid var(--vp-c-divider);
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 8px 24px;
  font-size: 13px;
  color: var(--vp-c-text-3);
}
.footer__bottom a {
  color: var(--vp-c-text-3);
  text-decoration: none;
}
.footer__bottom a:hover {
  color: var(--vp-c-text-1);
}
@media (max-width: 760px) {
  .footer {
    padding: 40px 16px 24px;
  }
  .footer__inner {
    grid-template-columns: repeat(3, 1fr);
  }
  .brand {
    grid-column: 1 / -1;
  }
}
</style>
