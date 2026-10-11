import dayjs from 'dayjs';
import type { components } from './api/schema.gen';

export type AuditAction = components['schemas']['AuditAction'];
export type AdminRole = components['schemas']['AdminRole'];

/** 字节数显示为 1.2 MB 等。 */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let v = bytes / 1024;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(v < 10 ? 1 : 0)} ${units[i]}`;
}

/** 日期时间显示为 2026-10-11 09:30；为空时显示"—"。 */
export function formatTime(iso: string | undefined | null): string {
  return iso ? dayjs(iso).format('YYYY-MM-DD HH:mm') : '—';
}

/** 相对时间：刚刚、5 分钟前、3 小时前、2 天前，更早显示日期。 */
export function fromNow(iso: string | undefined | null, now: Date = new Date()): string {
  if (!iso) return '—';
  const diff = (now.getTime() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return '刚刚';
  if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`;
  if (diff < 86400 * 30) return `${Math.floor(diff / 86400)} 天前`;
  return dayjs(iso).format('YYYY-MM-DD');
}

const PLATFORMS: Record<string, string> = {
  android: 'Android',
  ios: 'iOS',
  windows: 'Windows',
  macos: 'macOS',
  linux: 'Linux',
  web: 'Web',
};

export function platformLabel(p: string): string {
  return PLATFORMS[p] ?? p;
}

export const ACTION_LABELS: Record<AuditAction, string> = {
  login: '登录',
  login_failed: '登录失败',
  logout: '退出',
  view_dashboard: '查看仪表盘',
  list_users: '查看用户列表',
  view_user: '查看用户详情',
  change_password: '修改密码',
  create_admin: '新建管理员',
  update_admin: '修改管理员',
  reset_password: '重置管理员密码',
  list_audit_logs: '查看审计日志',
  list_admins: '查看管理员列表',
};

export const ROLE_LABELS: Record<AdminRole, string> = {
  super_admin: '超级管理员',
  viewer: '只读管理员',
};

const THEMES: Record<string, string> = { system: '跟随系统', light: '浅色', dark: '深色' };

export function themeLabel(t: string): string {
  return THEMES[t] ?? t;
}

/** 提前提醒的分钟数：准时、15 分钟、1 小时、1 天。 */
export function reminderLabel(min: number): string {
  if (min === 0) return '准时';
  if (min % 1440 === 0) return `提前 ${min / 1440} 天`;
  if (min % 60 === 0) return `提前 ${min / 60} 小时`;
  return `提前 ${min} 分钟`;
}

const DETAIL_LABELS: Record<string, string> = {
  q: '搜索',
  page: '页码',
  reason: '原因',
  username: '用户名',
  role: '角色',
  disabled: '停用',
  previousRole: '原角色',
  previousDisabled: '原停用',
  action: '筛选操作',
  via: '方式',
};

const REASONS: Record<string, string> = {
  unknown_user: '用户名不存在',
  password: '密码错误',
  locked: '账号已锁定',
  disabled: '账号已停用',
};

/** 审计说明显示为"搜索：alice · 页码：2"。 */
export function describeAudit(detail: Record<string, unknown>): string {
  const parts = Object.entries(detail)
    .filter(([, v]) => v !== '' && v !== null && v !== undefined)
    .map(([k, v]) => {
      const value = k === 'reason' ? (REASONS[String(v)] ?? String(v)) : typeof v === 'boolean' ? (v ? '是' : '否') : String(v);
      return `${DETAIL_LABELS[k] ?? k}：${value}`;
    });
  return parts.length ? parts.join(' · ') : '—';
}
