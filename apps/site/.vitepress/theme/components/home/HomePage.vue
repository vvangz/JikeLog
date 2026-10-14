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
      <div class="cta__inner">
        <h2>现在开始，把每一天记下来</h2>
        <p>下载即刻日志，注册账号，手机和电脑上的记录自动同步。</p>
        <div class="cta__actions">
          <a class="jk-btn cta__btn" href="/download"><JkIcon name="download" />立即下载</a>
          <a class="jk-btn cta__btn--ghost" href="/guide/quick-start"><JkIcon name="book" />快速上手</a>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
.cta {
  padding: 24px 24px 96px;
}
.cta__inner {
  max-width: 1152px;
  margin: 0 auto;
  padding: 64px 32px;
  border-radius: 28px;
  text-align: center;
  color: #fff;
  background: var(--jk-gradient-strong);
  box-shadow: 0 30px 60px -30px rgba(13, 148, 136, 0.7);
  position: relative;
  overflow: hidden;
}
.cta__inner::before {
  content: '';
  position: absolute;
  inset: 0;
  background-image: radial-gradient(rgba(255, 255, 255, 0.18) 1px, transparent 1px);
  background-size: 20px 20px;
  mask-image: radial-gradient(70% 90% at 50% 50%, #000, transparent);
  pointer-events: none;
}
h2 {
  position: relative;
  margin: 0 0 12px;
  font-size: clamp(26px, 4vw, 38px);
  font-weight: 800;
  color: #fff;
}
p {
  position: relative;
  margin: 0;
  font-size: 17px;
  color: rgba(255, 255, 255, 0.9);
}
.cta__actions {
  position: relative;
  display: flex;
  justify-content: center;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 30px;
}
.cta__btn {
  color: #0f766e !important;
  background: #fff;
}
.cta__btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 24px -12px rgba(0, 0, 0, 0.4);
}
.cta__btn--ghost {
  color: #fff !important;
  border: 1px solid rgba(255, 255, 255, 0.6);
}
.cta__btn--ghost:hover {
  background: rgba(255, 255, 255, 0.12);
}
@media (max-width: 600px) {
  .cta {
    padding: 8px 16px 64px;
  }
  .cta__inner {
    padding: 48px 20px;
    border-radius: 22px;
  }
}
</style>
