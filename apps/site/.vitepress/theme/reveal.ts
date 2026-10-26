// v-reveal：元素滚动进入视野时淡入上浮。用法：v-reveal 或 v-reveal="延迟毫秒"。
// 只在浏览器中、且系统未开启"减少动态效果"时生效；服务端渲染与禁用脚本时内容照常可见。
import type { Directive } from 'vue';

let observer: IntersectionObserver | undefined;

function getObserver(): IntersectionObserver {
  observer ??= new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.classList.add('is-in');
        observer?.unobserve(e.target);
      }
    },
    // 元素露出底部 8% 后再出现，避免刚擦边就播放完
    { rootMargin: '0px 0px -8% 0px', threshold: 0.01 },
  );
  return observer;
}

export const reveal: Directive<HTMLElement, number | undefined> = {
  mounted(el, binding) {
    if (typeof IntersectionObserver === 'undefined' || matchMedia('(prefers-reduced-motion: reduce)').matches) {
      return;
    }
    el.style.setProperty('--jk-reveal-delay', `${binding.value ?? 0}ms`);
    el.classList.add('jk-reveal');
    getObserver().observe(el);
  },
  unmounted(el) {
    observer?.unobserve(el);
  },
};
