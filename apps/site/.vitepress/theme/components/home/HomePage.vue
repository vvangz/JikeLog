<script setup lang="ts">
import JkIcon from '../JkIcon.vue';
import HomeFaq from './HomeFaq.vue';
import HomeHero from './HomeHero.vue';
import HomeHighlights from './HomeHighlights.vue';
import HomeModules from './HomeModules.vue';
import HomePlatforms from './HomePlatforms.vue';
import HomeSecurity from './HomeSecurity.vue';
</script>

<template>
  <div class="home">
    <HomeHero />
    <HomeModules />
    <HomeHighlights />
    <HomeSecurity />
    <HomePlatforms />
    <HomeFaq />
    <section class="cta">
      <h2>现在开始，把每一天记下来</h2>
      <p>下载即刻日志，注册账号，手机和电脑上的记录自动同步。</p>
      <div class="cta__actions">
        <a class="jk-btn jk-btn--primary" href="/download"><JkIcon name="download" />立即下载</a>
        <a class="jk-btn jk-btn--ghost" href="/guide/quick-start">快速上手</a>
      </div>
    </section>
  </div>
</template>

<style scoped>
.cta {
  max-width: 1120px;
  margin: 0 auto;
  padding: 136px 24px 144px;
  text-align: center;
  border-top: 1px solid var(--vp-c-divider);
}
h2 {
  margin: 0 0 16px;
  font-size: clamp(30px, 5vw, 52px);
  line-height: 1.15;
  font-weight: 500;
  letter-spacing: -0.03em;
  color: var(--vp-c-text-1);
}
p {
  margin: 0;
  font-size: 17px;
  color: var(--vp-c-text-2);
}
.cta__actions {
  display: flex;
  justify-content: center;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 40px;
}
@media (max-width: 600px) {
  .cta {
    padding: 88px 16px 96px;
  }
  .cta__actions .jk-btn {
    flex: 1 1 100%;
  }
}
</style>
