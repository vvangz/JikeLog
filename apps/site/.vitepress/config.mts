import { readFileSync } from 'node:fs';
import { defineConfig } from 'vitepress';
import { addCsp } from '../lib/csp.mjs';
import { ICP, REPO_URL, SITE_URL } from '../lib/site.mjs';

// scripts/sync-docs.mjs 生成：教程章节与更新日志版本
const nav = JSON.parse(readFileSync(new URL('./generated/nav.json', import.meta.url), 'utf8')) as {
  guide: { link: string; title: string; desc: string }[];
  changelog: string[];
};

const DESCRIPTION = '即刻日志：工作日志、笔记、备忘录、记账四合一的记录工具。多设备实时同步，离线可用，记录内容加密存储。支持 Android 与 Windows。';

export default defineConfig({
  lang: 'zh-CN',
  title: '即刻日志',
  titleTemplate: ':title · 即刻日志',
  description: DESCRIPTION,
  srcDir: 'src',
  cleanUrls: true,
  lastUpdated: false,
  // 不从 Google Fonts 等外部地址加载字体（CSP 只允许本站资源，国内也访问不了）
  useWebFonts: false,
  sitemap: { hostname: SITE_URL },

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/logo.svg' }],
    ['link', { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' }],
    ['meta', { name: 'theme-color', content: '#0f766e' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:site_name', content: '即刻日志' }],
    ['meta', { property: 'og:image', content: `${SITE_URL}/og.png` }],
    ['meta', { name: 'referrer', content: 'strict-origin-when-cross-origin' }],
  ],

  // 每个页面的标题与描述也写进 Open Graph，分享链接时显示
  transformPageData(pageData) {
    const title = pageData.frontmatter.title ?? pageData.title;
    const description = pageData.frontmatter.description ?? pageData.description ?? DESCRIPTION;
    const path = pageData.relativePath.replace(/(^|\/)index\.md$/, '$1').replace(/\.md$/, '');
    pageData.frontmatter.head ??= [];
    pageData.frontmatter.head.push(
      ['meta', { property: 'og:title', content: title ? `${title} · 即刻日志` : '即刻日志' }],
      ['meta', { property: 'og:description', content: description }],
      ['meta', { property: 'og:url', content: `${SITE_URL}/${path}` }],
      ['link', { rel: 'canonical', href: `${SITE_URL}/${path}` }],
    );
  },

  transformHtml: (html) => addCsp(html),

  vite: {
    define: { __SITE_ICP__: JSON.stringify(ICP) },
  },

  themeConfig: {
    logo: { src: '/logo.svg', alt: '' },
    siteTitle: '即刻日志',
    nav: [
      { text: '首页', link: '/' },
      { text: '下载', link: '/download' },
      { text: '使用教程', link: '/guide/', activeMatch: '^/guide/' },
      { text: '更新日志', link: '/changelog/', activeMatch: '^/changelog/' },
    ],
    socialLinks: [{ icon: 'github', link: REPO_URL, ariaLabel: 'GitHub 上的即刻日志' }],
    sidebar: {
      '/guide/': [
        { text: '开始', items: [{ text: '教程目录', link: '/guide/' }, { text: '下载与安装', link: '/download' }] },
        { text: '使用说明', items: nav.guide.map((g) => ({ text: g.title, link: g.link })) },
      ],
      '/changelog/': [
        { text: '更新日志', items: [{ text: '全部版本', link: '/changelog/' }, ...nav.changelog.map((v) => ({ text: v, link: `/changelog/${v}` }))] },
      ],
    },
    outline: { level: [2, 3], label: '本页目录' },
    docFooter: { prev: '上一章', next: '下一章' },
    darkModeSwitchLabel: '外观',
    lightModeSwitchTitle: '切换到浅色',
    darkModeSwitchTitle: '切换到深色',
    sidebarMenuLabel: '目录',
    returnToTopLabel: '回到顶部',
    langMenuLabel: '语言',
    skipToContentLabel: '跳到正文',
    notFound: {
      title: '页面不存在',
      quote: '这个地址没有内容，可能已经移动或被删除。',
      linkLabel: '回到首页',
      linkText: '回到首页',
      code: '404',
    },
    search: {
      provider: 'local',
      options: {
        miniSearch: {
          options: {
            // 中文没有空格分词：按词切分，否则整句成为一个词，搜不到句中的词
            tokenize: (text: string) =>
              [...new Intl.Segmenter('zh-CN', { granularity: 'word' }).segment(text)]
                .filter((s) => s.isWordLike)
                .map((s) => s.segment),
          },
          searchOptions: { prefix: true, fuzzy: 0.1, combineWith: 'AND' },
        },
        translations: {
          button: { buttonText: '搜索教程', buttonAriaLabel: '搜索教程' },
          modal: {
            displayDetails: '显示详细列表',
            resetButtonTitle: '清除',
            backButtonTitle: '关闭搜索',
            noResultsText: '没有找到相关内容',
            footer: { selectText: '打开', navigateText: '切换', closeText: '关闭' },
          },
        },
      },
    },
  },
});
