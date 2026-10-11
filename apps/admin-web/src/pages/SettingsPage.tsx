import { Card, Segmented, Typography } from 'antd';
import type { ThemeMode } from '../theme/themeMode';
import styles from '../App.module.css';

const THEME_OPTIONS: { label: string; value: ThemeMode }[] = [
  { label: '浅色', value: 'light' },
  { label: '深色', value: 'dark' },
  { label: '跟随系统', value: 'system' },
];

interface SettingsPageProps {
  theme: ThemeMode;
  onTheme: (m: ThemeMode) => void;
}

/** 设置：主题（保存在本机浏览器）。 */
export function SettingsPage({ theme, onTheme }: SettingsPageProps) {
  return (
    <div className={styles.page}>
      <Typography.Title level={3} className={styles.pageTitle}>
        设置
      </Typography.Title>
      <Card title="外观">
        <Typography.Paragraph>主题</Typography.Paragraph>
        <Segmented<ThemeMode> aria-label="主题" options={THEME_OPTIONS} value={theme} onChange={onTheme} />
      </Card>
    </div>
  );
}
