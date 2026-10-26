<script setup lang="ts">
import JkIcon from '../JkIcon.vue';
import AppMock from './AppMock.vue';
</script>

<template>
  <section class="hero">
    <div class="hero__text">
      <a class="badge jk-rise" href="/guide/windows">
        现已支持 Windows 电脑
        <JkIcon name="arrow" :size="14" />
      </a>
      <h1 class="jk-rise" style="--jk-rise-delay: 80ms">
        记下每一天的<br />
        <span class="muted">工作与生活</span>
      </h1>
      <p class="lead jk-rise" style="--jk-rise-delay: 200ms">
        工作日志、笔记、备忘录、记账，放进一个应用。手机和电脑实时同步，没有网络也能记，记录的内容加密保存。
      </p>
      <div class="actions jk-rise" style="--jk-rise-delay: 300ms">
        <a class="jk-btn jk-btn--primary" href="/download#android">
          <JkIcon name="android" />下载 Android 版
        </a>
        <a class="jk-btn jk-btn--ghost" href="/download#windows">
          <JkIcon name="windows" />下载 Windows 版
        </a>
      </div>
      <p class="facts jk-rise" style="--jk-rise-delay: 380ms">Android 8.0 及以上 · Windows 10 / 11 · 一个账号，多端同步</p>
    </div>
    <div class="hero__visual jk-rise" style="--jk-rise-delay: 480ms">
      <AppMock />
    </div>
  </section>
</template>

<style scoped>
.hero {
  padding: 112px 24px 40px;
  max-width: 1120px;
  margin: 0 auto;
}
.hero__text {
  text-align: center;
}
.badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 14px;
  border-radius: 999px;
  font-size: 13px;
  color: var(--vp-c-text-2);
  border: 1px solid var(--vp-c-divider);
  text-decoration: none;
  transition: border-color 0.2s, color 0.2s;
}
.badge:hover {
  color: var(--vp-c-text-1);
  border-color: var(--jk-line-strong);
}
h1 {
  margin: 28px 0 24px;
  font-size: clamp(40px, 7vw, 76px);
  line-height: 1.1;
  font-weight: 500;
  letter-spacing: -0.03em;
  color: var(--vp-c-text-1);
}
.muted {
  color: var(--vp-c-text-3);
}
.lead {
  font-size: 18px;
  line-height: 1.8;
  color: var(--vp-c-text-2);
  max-width: 560px;
  margin: 0 auto;
  text-wrap: balance;
}
.actions {
  display: flex;
  justify-content: center;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 40px;
}
.facts {
  margin: 22px 0 0;
  font-size: 13px;
  color: var(--vp-c-text-3);
}
.hero__visual {
  margin-top: 88px;
}

@media (max-width: 640px) {
  .hero {
    padding: 64px 16px 24px;
  }
  .lead {
    font-size: 16px;
  }
  .actions .jk-btn {
    flex: 1 1 100%;
  }
  .hero__visual {
    margin-top: 56px;
  }
}
</style>
