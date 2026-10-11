import { ArrowLeftOutlined } from '@ant-design/icons';
import { useQuery } from '@tanstack/react-query';
import { Alert, Button, Card, Descriptions, Progress, Space, Table, Tag, Typography } from 'antd';
import { Link, useParams } from 'react-router';
import type { components } from '../api/schema.gen';
import { useAuth } from '../auth/useAuth';
import { QueryState } from '../components/QueryState';
import { formatBytes, formatTime, fromNow, platformLabel, reminderLabel, themeLabel } from '../format';
import styles from '../App.module.css';

type Detail = components['schemas']['AdminUserDetail'];
type Device = components['schemas']['AdminUserDevice'];

/** 用户详情：只有配置与元数据（设置、设备、同步状态、附件用量），看不到任何内容。 */
export function UserDetailPage() {
  const { id = '' } = useParams();
  const { client, call } = useAuth();
  const q = useQuery({
    queryKey: ['user', id],
    queryFn: () =>
      call(() => client.GET('/api/admin/v1/users/{userId}', { params: { path: { userId: id } } })).then((r) => r.data),
  });
  return (
    <div className={styles.page}>
      <Space style={{ marginBottom: 16 }}>
        <Link to="/users" aria-label="返回用户列表">
          <Button icon={<ArrowLeftOutlined />} tabIndex={-1} />
        </Link>
        <Typography.Title level={3} className={styles.pageTitle} style={{ margin: 0 }}>
          用户详情
        </Typography.Title>
      </Space>
      <QueryState query={q}>{(d) => <DetailView d={d} />}</QueryState>
    </div>
  );
}

function DetailView({ d }: { d: Detail }) {
  const { user, settings, sync, storage } = d;
  const percent = storage.quota > 0 ? Math.round((storage.used / storage.quota) * 100) : 0;
  return (
    <Space direction="vertical" size="large" style={{ width: '100%' }}>
      <Alert type="info" showIcon message="管理员只能查看配置信息，看不到工作日志、笔记、备忘录和记账的任何内容。" />
      <Card title="账号">
        <Descriptions column={{ xs: 1, md: 2 }}>
          <Descriptions.Item label="用户名">{user.username}</Descriptions.Item>
          <Descriptions.Item label="昵称">{user.nickname || '—'}</Descriptions.Item>
          <Descriptions.Item label="手机号">{user.phoneMasked ?? '未绑定'}</Descriptions.Item>
          <Descriptions.Item label="注册时间">{formatTime(user.createdAt)}</Descriptions.Item>
          <Descriptions.Item label="最后活跃">{fromNow(user.lastActiveAt)}</Descriptions.Item>
          <Descriptions.Item label="已登录设备">{user.deviceCount} 台</Descriptions.Item>
        </Descriptions>
      </Card>
      <Card title="设置">
        <Descriptions column={{ xs: 1, md: 2 }}>
          <Descriptions.Item label="主题">{themeLabel(settings.themeMode)}</Descriptions.Item>
          <Descriptions.Item label="字号">{Math.round(settings.fontScale * 100)}%</Descriptions.Item>
          <Descriptions.Item label="一周的第一天">{settings.weekStart === 7 ? '周日' : '周一'}</Descriptions.Item>
          <Descriptions.Item label="默认提醒">
            {settings.defaultReminders.length === 0
              ? '不提醒'
              : settings.defaultReminders.map((m) => <Tag key={m}>{reminderLabel(m)}</Tag>)}
          </Descriptions.Item>
        </Descriptions>
      </Card>
      <Card title="同步与存储">
        <Descriptions column={{ xs: 1, md: 2 }}>
          <Descriptions.Item label="最后同步">{formatTime(sync.lastSyncAt)}</Descriptions.Item>
          <Descriptions.Item label="服务端同步序号">{sync.serverSeq}</Descriptions.Item>
          <Descriptions.Item label="附件用量" span="filled">
            <div style={{ width: '100%', maxWidth: 360 }}>
              <Typography.Text>
                {formatBytes(storage.used)} / {formatBytes(storage.quota)}
              </Typography.Text>
              <Progress percent={percent} size="small" />
            </div>
          </Descriptions.Item>
        </Descriptions>
      </Card>
      <Card title="设备">
        <Table<Device>
          rowKey="id"
          dataSource={d.devices}
          pagination={false}
          scroll={{ x: 720 }}
          columns={[
            { title: '平台', dataIndex: 'platform', render: (v: string) => platformLabel(v) },
            { title: '型号', dataIndex: 'model', render: (v: string) => v || '—' },
            { title: '系统', dataIndex: 'osVersion', render: (v: string) => v || '—' },
            { title: 'App 版本', dataIndex: 'appVersion', render: (v: string) => v || '—' },
            { title: '最后活跃', dataIndex: 'lastActiveAt', render: (v: string) => fromNow(v) },
            {
              title: '同步',
              dataIndex: 'ackSeq',
              render: (v: number) =>
                v >= sync.serverSeq ? <Tag color="success">已同步</Tag> : <Tag color="warning">落后 {sync.serverSeq - v}</Tag>,
            },
            {
              title: '状态',
              render: (_, dv) => (
                <Space size={4} wrap>
                  {dv.signedIn ? <Tag color="processing">已登录</Tag> : <Tag>已退出</Tag>}
                  {dv.localReminders && <Tag>本地提醒</Tag>}
                  {dv.pushEnabled && <Tag>推送</Tag>}
                </Space>
              ),
            },
          ]}
        />
      </Card>
    </Space>
  );
}
