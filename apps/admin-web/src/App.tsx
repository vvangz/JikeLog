import {
  AuditOutlined,
  DashboardOutlined,
  SettingOutlined,
  TeamOutlined,
  UserOutlined,
} from '@ant-design/icons';
import { App as AntApp, Button, ConfigProvider, Layout, Menu, Result, Segmented, Typography } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { useState } from 'react';
import { Logo } from './components/Logo';
import { buildAntdTheme } from './theme/antdTheme';
import type { ThemeMode } from './theme/themeMode';
import { useThemeMode } from './theme/useThemeMode';
import styles from './App.module.css';

const MODULE_ITEMS = [
  { key: 'dashboard', icon: <DashboardOutlined />, label: '仪表盘' },
  { key: 'users', icon: <TeamOutlined />, label: '用户管理' },
  { key: 'audit', icon: <AuditOutlined />, label: '审计日志' },
];

const COMMON_ITEMS = [
  { key: 'settings', icon: <SettingOutlined />, label: '设置' },
  { key: 'account', icon: <UserOutlined />, label: '账号' },
];

const THEME_OPTIONS: { label: string; value: ThemeMode }[] = [
  { label: '浅色', value: 'light' },
  { label: '深色', value: 'dark' },
  { label: '跟随系统', value: 'system' },
];

/** 侧栏：上方为功能模块入口，下方为设置、账号等通用入口；打开时自上而下展开。 */
function SideNav() {
  return (
    <nav className={styles.nav} aria-label="主导航">
      <Menu mode="inline" items={MODULE_ITEMS} defaultSelectedKeys={['dashboard']} />
      <Menu mode="inline" items={COMMON_ITEMS} selectable={false} className={styles.navBottom} />
    </nav>
  );
}

export default function App() {
  const { mode, resolved, setMode } = useThemeMode();
  const [navOpen, setNavOpen] = useState(false);

  return (
    <ConfigProvider theme={buildAntdTheme(resolved)} locale={zhCN}>
      <AntApp>
        <Layout className={styles.root}>
          <Layout.Header className={styles.header}>
            <Button
              type="text"
              aria-label="导航"
              aria-expanded={navOpen}
              icon={<Logo />}
              onClick={() => setNavOpen((v) => !v)}
              className={styles.entry}
            />
            <Typography.Title level={5} className={styles.title}>
              即刻日志管理后台
            </Typography.Title>
            <Segmented<ThemeMode> options={THEME_OPTIONS} value={mode} onChange={setMode} size="small" />
          </Layout.Header>
          <Layout className={styles.body}>
            {navOpen && <SideNav />}
            <Layout.Content className={styles.content}>
              <Result
                icon={<Logo size={64} />}
                title="管理后台建设中"
                subTitle="仪表盘、用户配置查看与审计日志将在 v0.8.0 提供。"
              />
            </Layout.Content>
          </Layout>
        </Layout>
      </AntApp>
    </ConfigProvider>
  );
}
