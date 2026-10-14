<script setup lang="ts">
// 首页右侧的产品示意图（纯 CSS 绘制，内容为示例）：桌面窗口展示工作日志，手机展示备忘提醒与记账
import JkIcon from '../JkIcon.vue';

const modules = [
  { icon: 'briefcase', label: '工作日志', active: true },
  { icon: 'notebook', label: '笔记' },
  { icon: 'alarm', label: '备忘录' },
  { icon: 'wallet', label: '记账' },
] as const;

const logs = [
  { day: '14', week: '周二', place: '总部 3 楼', text: '完成 Windows 客户端验收清单，整理发布说明' },
  { day: '13', week: '周一', place: '客户现场', text: '需求评审：导出格式增加 CSV，确认交付时间' },
  { day: '10', week: '周五', place: '远程', text: '修复同步冲突提示，补充修订历史的说明' },
];

const todos = [
  { text: '晨会', time: '09:30', done: true },
  { text: '发周报', time: '15:00', done: false },
  { text: '交房租', time: '20:00', done: false },
];
</script>

<template>
  <div class="mock" aria-hidden="true">
    <div class="mock__glow" />
    <div class="win">
      <div class="win__bar">
        <span class="dot" /><span class="dot" /><span class="dot" />
        <span class="win__title">即刻日志</span>
      </div>
      <div class="win__body">
        <nav class="win__side">
          <div v-for="m in modules" :key="m.label" class="side-item" :class="{ active: 'active' in m }">
            <JkIcon :name="m.icon" :size="16" />
            <span>{{ m.label }}</span>
          </div>
        </nav>
        <div class="win__main">
          <div class="main__head">
            <strong>工作日志</strong>
            <span class="chip">10 月</span>
          </div>
          <div v-for="l in logs" :key="l.day" class="log">
            <div class="log__date">
              <b>{{ l.day }}</b><small>{{ l.week }}</small>
            </div>
            <div class="log__text">
              <span class="log__place">{{ l.place }}</span>
              <p>{{ l.text }}</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="phone">
      <div class="phone__notch" />
      <div class="notice">
        <span class="notice__icon"><JkIcon name="bell" :size="14" /></span>
        <div>
          <b>备忘提醒 · 15:00</b>
          <p>给设计组发周报</p>
        </div>
      </div>
      <div class="ledger">
        <small>本月支出</small>
        <b>¥ 3,286.50</b>
        <div class="bars">
          <span style="--h: 70%; --c: var(--jk-mod-worklog)" />
          <span style="--h: 45%; --c: var(--jk-mod-notes)" />
          <span style="--h: 88%; --c: var(--jk-mod-memos)" />
          <span style="--h: 32%; --c: var(--jk-mod-ledger)" />
          <span style="--h: 58%; --c: var(--jk-teal-500)" />
        </div>
      </div>
      <div class="todo">
        <small>今天</small>
        <div v-for="t in todos" :key="t.text" class="todo__item" :class="{ done: t.done }">
          <span class="todo__box"><JkIcon v-if="t.done" name="check" :size="10" /></span>
          <span>{{ t.text }}</span>
          <em>{{ t.time }}</em>
        </div>
      </div>
      <div class="sync"><JkIcon name="sync" :size="13" /> 已同步</div>
    </div>
  </div>
</template>

<style scoped>
.mock {
  position: relative;
  width: 100%;
  max-width: 560px;
  aspect-ratio: 560 / 440;
  margin: 0 auto;
}
.mock__glow {
  position: absolute;
  inset: 8% 4% 4% 10%;
  background: var(--jk-gradient);
  filter: blur(70px);
  opacity: 0.35;
  border-radius: 50%;
}
.win {
  position: absolute;
  left: 0;
  top: 4%;
  width: 86%;
  border-radius: 14px;
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
  box-shadow: 0 30px 60px -30px rgba(15, 23, 42, 0.45);
  overflow: hidden;
}
.win__bar {
  display: flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 14px;
  background: var(--vp-c-bg-alt);
  border-bottom: 1px solid var(--vp-c-divider);
}
.dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--vp-c-divider);
}
.win__title {
  margin-left: 10px;
  font-size: 12px;
  color: var(--vp-c-text-2);
}
.win__body {
  display: grid;
  grid-template-columns: 30% 1fr;
  min-height: 290px;
}
.win__side {
  padding: 14px 10px;
  border-right: 1px solid var(--vp-c-divider);
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.side-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  border-radius: 8px;
  font-size: 13px;
  color: var(--vp-c-text-2);
  white-space: nowrap;
}
.side-item.active {
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
  font-weight: 600;
}
.win__main {
  /* 右侧留出手机遮住的部分，文字不被挡住 */
  padding: 14px calc(38% + 4px) 14px 16px;
}
.main__head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 14px;
  margin-bottom: 10px;
}
.chip {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--vp-c-bg-alt);
  color: var(--vp-c-text-2);
}
.log {
  display: flex;
  gap: 12px;
  padding: 10px 0;
  border-top: 1px solid var(--vp-c-divider);
}
.log__date {
  display: flex;
  flex-direction: column;
  align-items: center;
  min-width: 34px;
  line-height: 1.2;
}
.log__date b {
  font-size: 18px;
  color: var(--jk-mod-worklog);
}
.log__date small {
  font-size: 10px;
  color: var(--vp-c-text-3);
}
.log__place {
  font-size: 10px;
  color: var(--vp-c-text-3);
}
.log__text p {
  margin: 2px 0 0;
  font-size: 12px;
  line-height: 1.5;
  color: var(--vp-c-text-1);
}
.phone {
  position: absolute;
  right: 0;
  bottom: 0;
  width: 36%;
  aspect-ratio: 9 / 18;
  border-radius: 26px;
  padding: 26px 10px 12px;
  background: var(--vp-c-bg);
  border: 6px solid #0f172a;
  box-shadow: 0 30px 50px -24px rgba(15, 23, 42, 0.55);
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.dark .phone {
  border-color: #334155;
}
.phone__notch {
  position: absolute;
  top: 8px;
  left: 50%;
  width: 34%;
  height: 8px;
  border-radius: 6px;
  transform: translateX(-50%);
  background: #0f172a;
}
.notice {
  display: flex;
  gap: 8px;
  padding: 9px;
  border-radius: 12px;
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-divider);
  font-size: 10.5px;
  line-height: 1.4;
}
.notice p {
  margin: 0;
  color: var(--vp-c-text-2);
}
.notice__icon {
  display: grid;
  place-items: center;
  width: 22px;
  height: 22px;
  border-radius: 7px;
  flex: none;
  color: #fff;
  background: var(--jk-mod-memos);
}
.ledger {
  padding: 10px;
  border-radius: 12px;
  background: var(--jk-gradient-strong);
  color: #fff;
  display: flex;
  flex-direction: column;
}
.ledger small {
  font-size: 10px;
  opacity: 0.85;
}
.ledger b {
  font-size: 15px;
  letter-spacing: 0.02em;
  font-variant-numeric: tabular-nums;
}
.bars {
  display: flex;
  align-items: flex-end;
  gap: 5px;
  height: 46px;
  margin-top: 8px;
}
.bars span {
  flex: 1;
  height: var(--h);
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.85);
}
.todo {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.todo small {
  font-size: 10px;
  color: var(--vp-c-text-3);
}
.todo__item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 10.5px;
  color: var(--vp-c-text-1);
}
.todo__item em {
  margin-left: auto;
  font-style: normal;
  font-size: 9.5px;
  color: var(--vp-c-text-3);
  font-variant-numeric: tabular-nums;
}
.todo__item.done span:nth-child(2) {
  color: var(--vp-c-text-3);
  text-decoration: line-through;
}
.todo__box {
  display: grid;
  place-items: center;
  width: 13px;
  height: 13px;
  border-radius: 4px;
  border: 1.5px solid var(--vp-c-divider);
  color: #fff;
}
.done .todo__box {
  border-color: var(--jk-mod-memos);
  background: var(--jk-mod-memos);
}
/* 窄屏上只保留桌面窗口：缩小后的手机会盖住窗口与上方的文字 */
@media (max-width: 640px) {
  .mock {
    aspect-ratio: auto;
  }
  .win {
    position: relative;
    width: 100%;
    top: 0;
  }
  .win__body {
    grid-template-columns: 38% 1fr;
  }
  .win__main {
    padding-right: 16px;
  }
  .phone {
    display: none;
  }
}
.sync {
  margin-top: auto;
  align-self: center;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  color: var(--jk-mod-ledger);
}
</style>
