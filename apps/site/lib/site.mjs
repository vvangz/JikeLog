// 官网的基本信息，构建脚本与 VitePress 配置共用。
export const REPO_URL = 'https://github.com/vvangz/JikeLog';

// 正式地址；构建时可用 SITE_URL 覆盖（例如在其他域名预览）
export const SITE_URL = (process.env.SITE_URL || 'https://www.pingvv.top').replace(/\/+$/, '');

// ICP 备案号：备案通过后在仓库变量 SITE_ICP 中填写（如"京ICP备2026000000号-1"），页脚随之显示
export const ICP = (process.env.SITE_ICP || '').trim();
