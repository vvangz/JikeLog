<script setup lang="ts">
// 常见问题：答案须与使用说明一致，详情链接到对应章节
const faqs = [
  {
    q: '数据存在哪里？安全吗？',
    a: '数据保存在中国境内的服务器上。记录的文字内容在传输和存储时都额外加密，管理员看不到；每 14 天加密备份一次。',
    link: '/privacy',
  },
  {
    q: '没有网络时能用吗？',
    a: '可以。离线时照常新建和修改，恢复网络后自动同步到其他设备。',
    link: '/guide/sync',
  },
  {
    q: '手机和电脑同时改了同一条记录怎么办？',
    a: '按字段合并：改的是不同的地方会自动合在一起；同一处都改了，以较晚的为准，另一个版本保留在修订历史中，随时可以找回。',
    link: '/guide/worklog#_5-修订历史与冲突版本',
  },
  {
    q: '为什么 Windows 版安装前要导入证书？',
    a: '安装包用即刻日志自己的证书签名，Windows 需要先信任这张证书才能安装。只需导入一次，导入前请核对证书指纹。',
    link: '/guide/windows',
  },
  {
    q: '怎样把数据带走？',
    a: '在"导出"中选择模块，导出的笔记是 Markdown、账目和备忘是 Excel 可打开的表格，备忘还有日历文件，可以连同附件一起导出。',
    link: '/guide/search-export',
  },
  {
    q: '支持 iPhone 或 Mac 吗？',
    a: '目前提供 Android 和 Windows 版。其他平台的计划会在更新日志中公布。',
    link: '/changelog/',
  },
];
</script>

<template>
  <section class="jk-section alt">
    <div class="jk-section__inner narrow">
      <div class="jk-center">
        <span class="jk-eyebrow">常见问题</span>
        <h2 class="jk-h2">使用前你可能想知道</h2>
      </div>
      <div class="list">
        <details v-for="f in faqs" :key="f.q">
          <summary>{{ f.q }}</summary>
          <p>
            {{ f.a }}
            <a :href="f.link">了解更多</a>
          </p>
        </details>
      </div>
    </div>
  </section>
</template>

<style scoped>
.alt {
  background: var(--vp-c-bg-alt);
}
.narrow {
  max-width: 820px;
}
.list {
  margin-top: 40px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
details {
  border-radius: 14px;
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
  transition: border-color 0.2s;
}
details[open] {
  border-color: var(--vp-c-brand-2);
}
summary {
  list-style: none;
  cursor: pointer;
  padding: 18px 52px 18px 22px;
  position: relative;
  font-size: 16px;
  font-weight: 600;
  color: var(--vp-c-text-1);
}
summary::-webkit-details-marker {
  display: none;
}
summary::after {
  content: '';
  position: absolute;
  right: 24px;
  top: 50%;
  width: 9px;
  height: 9px;
  border-right: 2px solid var(--vp-c-text-2);
  border-bottom: 2px solid var(--vp-c-text-2);
  transform: translateY(-70%) rotate(45deg);
  transition: transform 0.2s;
}
details[open] summary::after {
  transform: translateY(-30%) rotate(-135deg);
}
summary:focus-visible {
  outline: 2px solid var(--vp-c-brand-2);
  outline-offset: 2px;
  border-radius: 14px;
}
details p {
  margin: 0;
  padding: 0 22px 20px;
  font-size: 15px;
  line-height: 1.8;
  color: var(--vp-c-text-2);
}
details a {
  color: var(--vp-c-brand-1);
  font-weight: 600;
  white-space: nowrap;
}
</style>
