import type { Theme } from 'vitepress';
import DefaultTheme from 'vitepress/theme';
import { h } from 'vue';
import DownloadCards from './components/DownloadCards.vue';
import GuideCards from './components/GuideCards.vue';
import HomePage from './components/home/HomePage.vue';
import SiteFooter from './components/SiteFooter.vue';
import { reveal } from './reveal';
// 字体随站点自托管（CSP 只允许本站字体）：Geist（OFL 许可）用于西文与数字；
// 标题的中文字体由构建脚本裁剪生成（见 lib/display-font.mjs 与 .vitepress/config.mts）。
import '@fontsource-variable/geist';
import './style.css';

export default {
  extends: DefaultTheme,
  Layout: () => h(DefaultTheme.Layout, null, { 'layout-bottom': () => h(SiteFooter) }),
  enhanceApp({ app }) {
    app.component('HomePage', HomePage);
    app.component('DownloadCards', DownloadCards);
    app.component('GuideCards', GuideCards);
    app.directive('reveal', reveal);
  },
} satisfies Theme;
