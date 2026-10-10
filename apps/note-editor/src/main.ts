import { createBridge, type Bridge } from './bridge';
import { installFonts } from './fonts';
import './style.css';

declare global {
  interface Window {
    jikelog?: Bridge;
    /** Flutter 注入的 JavaScript 通道。 */
    JikeLog?: { postMessage(message: string): void };
  }
}

installFonts();

const element = document.getElementById('editor');
if (element && window.JikeLog) {
  const channel = window.JikeLog;
  window.jikelog = createBridge({ element, post: (json) => channel.postMessage(json) });
} else {
  console.error('即刻日志编辑器：缺少编辑区域或 Flutter 通道');
}
