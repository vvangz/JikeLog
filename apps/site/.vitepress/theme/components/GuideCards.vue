<script setup lang="ts">
// 教程首页的章节卡片：章节与简介来自 docs/使用说明（scripts/sync-docs.mjs 生成 nav.json）
import nav from '../../generated/nav.json';

const chapters = nav.guide.map((g, i) => ({ ...g, no: String(i + 1).padStart(2, '0') }));
</script>

<template>
  <div class="cards">
    <a v-for="c in chapters" :key="c.link" class="card" :href="c.link">
      <span class="no">{{ c.no }}</span>
      <div>
        <strong>{{ c.title }}</strong>
        <span v-if="c.desc" class="desc">{{ c.desc }}</span>
      </div>
    </a>
  </div>
</template>

<style scoped>
.cards {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 12px;
  margin-top: 24px;
}
.card {
  display: flex;
  gap: 14px;
  padding: 16px 18px;
  border-radius: 14px;
  border: 1px solid var(--vp-c-divider);
  background: var(--vp-c-bg);
  text-decoration: none !important;
  color: inherit !important;
  transition: border-color 0.2s, box-shadow 0.2s, transform 0.2s;
}
.card:hover {
  border-color: var(--vp-c-brand-2);
  box-shadow: var(--jk-card-shadow-hover);
  transform: translateY(-2px);
}
.no {
  font-size: 13px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: var(--vp-c-brand-1);
  padding-top: 2px;
}
strong {
  display: block;
  font-size: 16px;
  color: var(--vp-c-text-1);
}
.desc {
  display: block;
  margin-top: 4px;
  font-size: 13.5px;
  line-height: 1.6;
  color: var(--vp-c-text-2);
}
@media (max-width: 640px) {
  .cards {
    grid-template-columns: 1fr;
  }
}
</style>
