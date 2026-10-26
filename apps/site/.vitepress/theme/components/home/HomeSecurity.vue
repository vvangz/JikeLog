<script setup lang="ts">
// 说法须与实际实现一致（ADR-006 加密、ADR-011 管理后台、ADR-012 备份），修改前先核对代码与隐私政策
import JkIcon from '../JkIcon.vue';

const items = [
  { icon: 'lock', title: '双重传输加密', desc: 'HTTPS 之上，记录内容与附件文件名再经 AES-256-GCM 加密传输。' },
  { icon: 'shield', title: '加密存储', desc: '记录内容在服务器上加密保存，每个账号使用独立密钥。' },
  { icon: 'archive', title: '异地加密备份', desc: '每 14 天全量备份，加密后异地保存，故障时可完整恢复。' },
  { icon: 'export', title: '数据自主可控', desc: '随时导出全部数据；注销后，账号与记录随即从服务器删除。' },
] as const;
</script>

<template>
  <section class="sec">
    <div class="sec__inner">
      <div v-reveal class="sec__intro">
        <span class="eyebrow">安全与隐私</span>
        <h2>你的记录，只属于你</h2>
        <p>从传输、存储到备份，每个环节都经过加密。</p>
        <a class="link" href="/privacy">阅读隐私政策 <JkIcon name="arrow" :size="15" /></a>
      </div>
      <div class="sec__grid">
        <div v-for="(it, i) in items" :key="it.title" v-reveal="120 + i * 90" class="item">
          <JkIcon :name="it.icon" :size="20" />
          <h3>{{ it.title }}</h3>
          <p>{{ it.desc }}</p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
/* 反色区块：浅色主题下是全站唯一的深色面，深色主题下以细线与正文区分 */
.sec {
  padding: 128px 24px;
  color: #d4d4d4;
  background: var(--jk-inverse-bg);
  border-top: 1px solid var(--jk-inverse-line);
  border-bottom: 1px solid var(--jk-inverse-line);
}
.sec__inner {
  max-width: 1120px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: 0.85fr 1.4fr;
  gap: 80px;
  align-items: start;
}
.eyebrow {
  font-size: 13px;
  font-weight: 500;
  letter-spacing: 0.04em;
  color: #8f8f8f;
}
h2 {
  margin: 16px 0 18px;
  font-size: clamp(28px, 4.2vw, 44px);
  line-height: 1.2;
  font-weight: 500;
  letter-spacing: -0.02em;
  color: #fafafa;
}
.sec__intro p {
  margin: 0;
  font-size: 16.5px;
  line-height: 1.8;
  color: #a3a3a3;
}
.link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 28px;
  font-weight: 500;
  color: #fafafa;
  text-decoration: none;
  border-bottom: 1px solid rgba(255, 255, 255, 0.3);
  padding-bottom: 2px;
  transition: border-color 0.2s;
}
.link:hover {
  border-color: #fafafa;
}
.sec__grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  border-top: 1px solid var(--jk-inverse-line);
}
.item {
  padding: 32px 32px 32px 0;
  border-bottom: 1px solid var(--jk-inverse-line);
}
.item:nth-child(even) {
  padding: 32px 0 32px 32px;
  border-left: 1px solid var(--jk-inverse-line);
}
/* 卡片之间以边框分隔：出现时只淡入不位移，避免线条在动画中错开 */
.item.jk-reveal {
  transform: none;
}
.item :deep(svg) {
  color: #fafafa;
}
h3 {
  margin: 18px 0 8px;
  font-size: 17px;
  font-weight: 600;
  color: #fafafa;
}
.item p {
  margin: 0;
  font-size: 14.5px;
  line-height: 1.75;
  color: #a3a3a3;
}
@media (max-width: 960px) {
  .sec__inner {
    grid-template-columns: 1fr;
    gap: 48px;
  }
}
@media (max-width: 600px) {
  .sec {
    padding: 88px 16px;
  }
  .sec__grid {
    grid-template-columns: 1fr;
  }
  .item,
  .item:nth-child(even) {
    padding: 28px 0;
    border-left: 0;
  }
}
</style>
