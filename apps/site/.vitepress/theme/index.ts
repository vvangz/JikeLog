import type { Theme } from 'vitepress';
import DefaultTheme from 'vitepress/theme';
import { h } from 'vue';
import DownloadCards from './components/DownloadCards.vue';
import GuideCards from './components/GuideCards.vue';
import HomePage from './components/home/HomePage.vue';
import SiteFooter from './components/SiteFooter.vue';
import './style.css';

export default {
  extends: DefaultTheme,
  Layout: () => h(DefaultTheme.Layout, null, { 'layout-bottom': () => h(SiteFooter) }),
  enhanceApp({ app }) {
    app.component('HomePage', HomePage);
    app.component('DownloadCards', DownloadCards);
    app.component('GuideCards', GuideCards);
  },
} satisfies Theme;
