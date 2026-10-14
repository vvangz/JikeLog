<script setup lang="ts">
// 说法须与实际实现一致（ADR-006 加密、ADR-011 管理后台、ADR-012 备份），修改前先核对代码与隐私政策
import JkIcon from '../JkIcon.vue';

const items = [
  {
    icon: 'lock',
    title: '传输时两层加密',
    desc: '全程 HTTPS；日志、笔记、备忘、账目的文字内容和附件文件名，在 HTTPS 之上再用 X25519 + AES-256-GCM 加密一次。',
  },
  {
    icon: 'shield',
    title: '存储时加密',
    desc: '这些内容在服务器上以每个账号独立的密钥加密保存，管理员只能看到账号配置，看不到你记录的内容。',
  },
  {
    icon: 'archive',
    title: '定期加密备份',
    desc: '每 14 天全量备份一次，备份加密后保存到异地，服务器出故障也能恢复。',
  },
  {
    icon: 'export',
    title: '数据由你掌控',
    desc: '随时导出全部数据；注销账号后，账号与全部记录立即从服务器删除。',
  },
] as const;
</script>

<template>
  <section class="sec">
    <div class="sec__inner">
      <div class="sec__intro">
        <span class="eyebrow">安全与隐私</span>
        <h2>你的记录，只属于你</h2>
        <p>工作安排、个人笔记、收支明细都是敏感信息。即刻日志在设计时就把加密和隐私放在前面。</p>
        <a class="link" href="/privacy">阅读隐私政策 <JkIcon name="arrow" :size="16" /></a>
      </div>
      <div class="sec__grid">
        <div v-for="it in items" :key="it.title" class="item">
          <JkIcon :name="it.icon" :size="22" />
          <h3>{{ it.title }}</h3>
          <p>{{ it.desc }}</p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.sec {
  padding: 96px 24px;
  color: #e2e8f0;
  background:
    radial-gradient(60% 80% at 100% 0%, rgba(37, 99, 235, 0.35), transparent 60%),
    radial-gradient(50% 70% at 0% 100%, rgba(20, 184, 166, 0.3), transparent 60%),
    #0b1324;
}
.sec__inner {
  max-width: 1152px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: 0.9fr 1.4fr;
  gap: 56px;
  align-items: center;
}
.eyebrow {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.12em;
  color: #5eead4;
}
h2 {
  margin: 12px 0 16px;
  font-size: clamp(28px, 4vw, 38px);
  line-height: 1.25;
  font-weight: 800;
  color: #fff;
}
.sec__intro p {
  margin: 0;
  font-size: 16.5px;
  line-height: 1.8;
  color: #cbd5e1;
}
.link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 24px;
  font-weight: 600;
  color: #5eead4;
  text-decoration: none;
}
.link:hover {
  color: #99f6e4;
}
.sec__grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
}
.item {
  padding: 24px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(6px);
}
.item :deep(svg) {
  color: #5eead4;
}
h3 {
  margin: 14px 0 8px;
  font-size: 17px;
  font-weight: 700;
  color: #fff;
}
.item p {
  margin: 0;
  font-size: 14.5px;
  line-height: 1.75;
  color: #cbd5e1;
}
@media (max-width: 960px) {
  .sec__inner {
    grid-template-columns: 1fr;
    gap: 36px;
  }
}
@media (max-width: 600px) {
  .sec {
    padding: 64px 16px;
  }
  .sec__grid {
    grid-template-columns: 1fr;
  }
}
</style>
