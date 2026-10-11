import { useQuery } from '@tanstack/react-query';
import { Card, Col, Empty, Progress, Row, Statistic, Typography } from 'antd';
import { useAuth } from '../auth/useAuth';
import type { components } from '../api/schema.gen';
import { formatBytes, platformLabel } from '../format';
import { QueryState } from '../components/QueryState';
import styles from '../App.module.css';
import chart from './DashboardPage.module.css';

type Dashboard = components['schemas']['AdminDashboard'];

/** 仪表盘：用户总数、新增、活跃、平台分布与存储用量。 */
export function DashboardPage() {
  const { client, call } = useAuth();
  const q = useQuery({
    queryKey: ['dashboard'],
    queryFn: () => call(() => client.GET('/api/admin/v1/dashboard')).then((r) => r.data),
  });
  return (
    <div className={styles.page}>
      <Typography.Title level={3} className={styles.pageTitle}>
        仪表盘
      </Typography.Title>
      <QueryState query={q}>{(d) => <DashboardView d={d} />}</QueryState>
    </div>
  );
}

function DashboardView({ d }: { d: Dashboard }) {
  const stats: [string, number | string][] = [
    ['用户总数', d.totalUsers],
    ['今日新增', d.newUsersToday],
    ['今日活跃', d.activeToday],
    ['近 7 天活跃', d.activeWeek],
    ['近 30 天活跃', d.activeMonth],
    ['附件总用量', formatBytes(d.storageBytes)],
  ];
  return (
    <Row gutter={[16, 16]}>
      {stats.map(([title, value]) => (
        <Col key={title} xs={12} md={8} xl={4}>
          <Card>
            <Statistic title={title} value={value} />
          </Card>
        </Col>
      ))}
      <Col xs={24} lg={16}>
        <Card title="近 30 天新增用户">
          <DailyChart days={d.newUsersDaily} />
        </Card>
      </Col>
      <Col xs={24} lg={8}>
        <Card title="活跃设备平台（近 30 天）">
          <Platforms platforms={d.platforms} />
        </Card>
      </Col>
    </Row>
  );
}

/** 每日新增的柱状图（纯 CSS）；读屏读到的是每天的数量。 */
function DailyChart({ days }: { days: Dashboard['newUsersDaily'] }) {
  const max = Math.max(1, ...days.map((d) => d.count));
  return (
    <div className={chart.bars} role="list" aria-label="每日新增用户">
      {days.map((d) => (
        <div
          key={d.day}
          role="listitem"
          aria-label={`${d.day}：${d.count} 人`}
          title={`${d.day}：${d.count} 人`}
          className={chart.bar}
          style={{ height: `${Math.max(2, (d.count / max) * 100)}%` }}
        />
      ))}
    </div>
  );
}

function Platforms({ platforms }: { platforms: Dashboard['platforms'] }) {
  const total = platforms.reduce((n, p) => n + p.devices, 0);
  if (total === 0) return <Empty description="暂无活跃设备" />;
  return (
    <>
      {platforms.map((p) => (
        <div key={p.platform}>
          <Typography.Text>
            {platformLabel(p.platform)} · {p.devices} 台
          </Typography.Text>
          <Progress percent={Math.round((p.devices / total) * 100)} />
        </div>
      ))}
    </>
  );
}
