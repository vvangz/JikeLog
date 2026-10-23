<script setup lang="ts">
import JkIcon from '../JkIcon.vue';
import AppMock from './AppMock.vue';
</script>

<template>
  <section class="hero">
    <div class="hero__bg" aria-hidden="true" />
    <div class="hero__inner">
      <div class="hero__text">
        <a class="badge" href="/guide/windows">
          <span class="badge__dot" />现已支持 Windows 电脑
          <JkIcon name="arrow" :size="14" />
        </a>
        <h1>
          记下每一天的<br />
          <span class="grad">工作与生活</span>
        </h1>
        <p class="lead">
          即刻日志把<strong>工作日志、笔记、备忘录、记账</strong>放进一个应用。手机和电脑实时同步，没有网络也能记，记录的内容加密保存。
        </p>
        <div class="actions">
          <a class="jk-btn jk-btn--primary" href="/download#android">
            <JkIcon name="android" />下载 Android 版
          </a>
          <a class="jk-btn jk-btn--ghost" href="/download#windows">
            <JkIcon name="windows" />下载 Windows 版
          </a>
        </div>
        <ul class="facts">
          <li><JkIcon name="check" :size="16" />Android 8.0 及以上</li>
          <li><JkIcon name="check" :size="16" />Windows 10 / 11</li>
          <li><JkIcon name="check" :size="16" />一个账号，多端同步</li>
        </ul>
      </div>
      <div class="hero__visual">
        <AppMock />
      </div>
    </div>
  </section>
</template>

<style scoped>
.hero {
  position: relative;
  overflow: hidden;
  padding: 72px 24px 96px;
}
.hero__bg {
  position: absolute;
  inset: 0;
  background:
    radial-gradient(60% 60% at 85% 10%, rgba(37, 99, 235, 0.12), transparent 70%),
    radial-gradient(50% 60% at 10% 0%, rgba(20, 184, 166, 0.16), transparent 70%);
  pointer-events: none;
}
.hero__bg::after {
  content: '';
  position: absolute;
  inset: 0;
  background-image: radial-gradient(var(--vp-c-divider) 1px, transparent 1px);
  background-size: 22px 22px;
  mask-image: linear-gradient(to bottom, rgba(0, 0, 0, 0.6), transparent 75%);
}
.hero__inner {
  position: relative;
  max-width: 1152px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: 1.05fr 1fr;
  gap: 48px;
  align-items: center;
}
.badge {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px 6px 10px;
  border-radius: 999px;
  font-size: 13px;
  font-weight: 600;
  color: var(--vp-c-brand-1);
  background: var(--vp-c-brand-soft);
  text-decoration: none;
  transition: background-color 0.2s;
}
.badge:hover {
  background: rgba(13, 148, 136, 0.22);
}
.badge__dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--vp-c-brand-2);
  box-shadow: 0 0 0 4px rgba(20, 184, 166, 0.25);
}
h1 {
  margin: 22px 0 18px;
  font-size: clamp(38px, 6vw, 60px);
  line-height: 1.12;
  font-weight: 800;
  letter-spacing: -0.02em;
  color: var(--vp-c-text-1);
}
.grad {
  background: var(--jk-gradient);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
.lead {
  font-size: 18px;
  line-height: 1.8;
  color: var(--vp-c-text-2);
  max-width: 520px;
  margin: 0;
}
.lead strong {
  color: var(--vp-c-text-1);
  font-weight: 600;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 32px;
}
.facts {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 20px;
  list-style: none;
  padding: 0;
  margin: 26px 0 0;
  font-size: 14px;
  color: var(--vp-c-text-2);
}
.facts li {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.facts :deep(svg) {
  color: var(--vp-c-brand-2);
}

@media (max-width: 960px) {
  .hero__inner {
    grid-template-columns: 1fr;
    gap: 56px;
  }
  .hero__text {
    text-align: center;
  }
  .lead {
    margin: 0 auto;
  }
  .actions,
  .facts {
    justify-content: center;
  }
}
@media (max-width: 640px) {
  .hero {
    padding: 40px 16px 64px;
  }
  .actions .jk-btn {
    flex: 1 1 100%;
    justify-content: center;
  }
}
</style>
