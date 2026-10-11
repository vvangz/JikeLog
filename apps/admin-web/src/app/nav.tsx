import {
  AuditOutlined,
  DashboardOutlined,
  SafetyCertificateOutlined,
  SettingOutlined,
  TeamOutlined,
  UserOutlined,
} from '@ant-design/icons';
import type { ReactNode } from 'react';

export interface NavItem {
  key: string;
  icon: ReactNode;
  label: string;
  /** 只对超级管理员显示。 */
  superOnly?: boolean;
}

/** 侧栏上方：功能模块。 */
export const MODULE_ITEMS: NavItem[] = [
  { key: '/dashboard', icon: <DashboardOutlined />, label: '仪表盘' },
  { key: '/users', icon: <TeamOutlined />, label: '用户' },
  { key: '/audit', icon: <AuditOutlined />, label: '审计日志' },
];

/** 侧栏下方：管理员、设置、账号等通用入口。 */
export const COMMON_ITEMS: NavItem[] = [
  { key: '/admins', icon: <SafetyCertificateOutlined />, label: '管理员', superOnly: true },
  { key: '/settings', icon: <SettingOutlined />, label: '设置' },
  { key: '/account', icon: <UserOutlined />, label: '账号' },
];

/** 当前路径所属的入口（子页面归属于上级入口）。 */
export function selectedKey(pathname: string): string {
  const all = [...MODULE_ITEMS, ...COMMON_ITEMS];
  return all.find((i) => pathname === i.key || pathname.startsWith(`${i.key}/`))?.key ?? '';
}
