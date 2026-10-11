import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { App as AntApp, Button, ConfigProvider, Result, Spin } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import 'dayjs/locale/zh-cn';
import dayjs from 'dayjs';
import { useState, type ReactNode } from 'react';
import { BrowserRouter, MemoryRouter, Navigate, Route, Routes } from 'react-router';
import { AppShell } from './app/AppShell';
import { ApiError } from './api/errors';
import { AuthProvider } from './auth/session';
import { useAuth } from './auth/useAuth';
import { AccountPage } from './pages/AccountPage';
import { AdminsPage } from './pages/AdminsPage';
import { AuditLogsPage } from './pages/AuditLogsPage';
import { DashboardPage } from './pages/DashboardPage';
import { LoginPage } from './pages/LoginPage';
import { SettingsPage } from './pages/SettingsPage';
import { UserDetailPage } from './pages/UserDetailPage';
import { UsersPage } from './pages/UsersPage';
import { buildAntdTheme } from './theme/antdTheme';
import type { ThemeMode } from './theme/themeMode';
import { useThemeMode } from './theme/useThemeMode';
import styles from './App.module.css';

dayjs.locale('zh-cn');

interface AppProps {
  /** 测试用：从指定路径开始（使用内存路由）。 */
  initialPath?: string;
  /** 测试用：注入接口的 fetch 实现与基地址。 */
  fetch?: (input: Request) => Promise<Response>;
  baseUrl?: string;
}

function newQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // 登录失效、没有权限等错误重试也不会成功
        retry: (count, err) => count < 2 && !(err instanceof ApiError && err.status >= 400 && err.status < 500),
        refetchOnWindowFocus: false,
      },
    },
  });
}

/** 管理后台根组件：主题、认证与路由。 */
export default function App({ initialPath, fetch, baseUrl }: AppProps) {
  const { mode, resolved, setMode } = useThemeMode();
  const [queryClient] = useState(newQueryClient);
  const routes = <AppRoutes theme={mode} onTheme={setMode} />;
  return (
    <ConfigProvider theme={buildAntdTheme(resolved)} locale={zhCN}>
      <AntApp>
        <QueryClientProvider client={queryClient}>
          <AuthProvider fetch={fetch} baseUrl={baseUrl}>
            {initialPath ? (
              <MemoryRouter initialEntries={[initialPath]}>{routes}</MemoryRouter>
            ) : (
              <BrowserRouter basename={import.meta.env.BASE_URL}>{routes}</BrowserRouter>
            )}
          </AuthProvider>
        </QueryClientProvider>
      </AntApp>
    </ConfigProvider>
  );
}

interface AppRoutesProps {
  theme: ThemeMode;
  onTheme: (m: ThemeMode) => void;
}

function AppRoutes({ theme, onTheme }: AppRoutesProps) {
  const { status, admin, retry } = useAuth();
  if (status === 'offline') {
    return (
      <div className={styles.center}>
        <Result
          status="warning"
          title="无法连接服务器"
          subTitle="请检查网络后重试。"
          extra={
            <Button type="primary" onClick={retry}>
              重试
            </Button>
          }
        />
      </div>
    );
  }
  if (status === 'loading') {
    return (
      <div className={styles.center}>
        <Spin size="large" aria-label="加载中" />
      </div>
    );
  }
  if (status === 'signedOut' || !admin) return <LoginPage />;
  // 必须修改初始密码时只能停留在账号页
  const guard = (page: ReactNode) => (admin.mustChangePassword ? <Navigate to="/account" replace /> : page);
  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={guard(<DashboardPage />)} />
        <Route path="users" element={guard(<UsersPage />)} />
        <Route path="users/:id" element={guard(<UserDetailPage />)} />
        <Route path="audit" element={guard(<AuditLogsPage />)} />
        <Route path="admins" element={guard(<AdminsPage />)} />
        <Route path="settings" element={<SettingsPage theme={theme} onTheme={onTheme} />} />
        <Route path="account" element={<AccountPage />} />
        <Route path="*" element={<Result status="404" title="页面不存在" />} />
      </Route>
    </Routes>
  );
}
