import { Button, Layout, Menu, Typography } from 'antd';
import { useState } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router';
import { useAuth } from '../auth/useAuth';
import { Logo } from '../components/Logo';
import { COMMON_ITEMS, MODULE_ITEMS, selectedKey, type NavItem } from './nav';
import { useMediaQuery } from './useMediaQuery';
import styles from '../App.module.css';

/** 宽屏（≥ 840px）时侧栏常驻；窄屏时侧栏为浮层，选择后自动收起。 */
const WIDE_QUERY = '(min-width: 840px)';

/** 应用外壳：左上角入口图标展开或收起左侧导航栏，上方是功能模块，下方是通用入口。 */
export function AppShell() {
  const { admin } = useAuth();
  const wide = useMediaQuery(WIDE_QUERY);
  // 宽屏与窄屏各自记住展开状态：宽屏默认展开，窄屏默认收起
  const [openWide, setOpenWide] = useState(true);
  const [openNarrow, setOpenNarrow] = useState(false);
  const open = wide ? openWide : openNarrow;
  const setOpen = wide ? setOpenWide : setOpenNarrow;
  const navigate = useNavigate();
  const { pathname } = useLocation();

  const visible = (items: NavItem[]) =>
    items
      .filter((i) => !i.superOnly || admin?.role === 'super_admin')
      .map(({ key, icon, label }) => ({ key, icon, label }));
  const go = ({ key }: { key: string }) => {
    navigate(key);
    if (!wide) setOpenNarrow(false);
  };
  const selected = [selectedKey(pathname)];

  return (
    <Layout className={styles.root}>
      <Layout.Header className={styles.header}>
        <Button
          type="text"
          aria-label="导航"
          aria-expanded={open}
          icon={<Logo />}
          onClick={() => setOpen(!open)}
          className={styles.entry}
        />
        <Typography.Title level={5} className={styles.title}>
          即刻日志管理后台
        </Typography.Title>
        {admin && <Typography.Text type="secondary">{admin.username}</Typography.Text>}
      </Layout.Header>
      <Layout className={styles.body}>
        {open && (
          <>
            {!wide && <div className={styles.scrim} onClick={() => setOpenNarrow(false)} aria-hidden />}
            <nav className={styles.nav} aria-label="主导航">
              <Menu mode="inline" items={visible(MODULE_ITEMS)} selectedKeys={selected} onClick={go} />
              <Menu
                mode="inline"
                items={visible(COMMON_ITEMS)}
                selectedKeys={selected}
                onClick={go}
                className={styles.navBottom}
              />
            </nav>
          </>
        )}
        <Layout.Content className={styles.content}>
          <Outlet />
        </Layout.Content>
      </Layout>
    </Layout>
  );
}
