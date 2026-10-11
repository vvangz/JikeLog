import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { DatePicker, Select, Space, Table, Tag, Typography } from 'antd';
import type { Dayjs } from 'dayjs';
import { useState } from 'react';
import type { components } from '../api/schema.gen';
import { errorMessage } from '../api/errors';
import { useAuth } from '../auth/useAuth';
import { ACTION_LABELS, describeAudit, formatTime, type AuditAction } from '../format';
import styles from '../App.module.css';

type AuditLog = components['schemas']['AuditLog'];

const PAGE_SIZE = 20;

interface Filters {
  action?: AuditAction;
  range?: [Dayjs, Dayjs];
  page: number;
}

/** 审计日志：按操作与时间筛选，新的在前。只能查看，不能修改或删除。 */
export function AuditLogsPage() {
  const { client, call } = useAuth();
  const [f, setF] = useState<Filters>({ page: 1 });

  const logs = useQuery({
    queryKey: ['audit', f.action, f.range?.[0].valueOf(), f.range?.[1].valueOf(), f.page],
    queryFn: () =>
      call(() =>
        client.GET('/api/admin/v1/audit-logs', {
          params: {
            query: {
              action: f.action,
              from: f.range?.[0].startOf('day').toISOString(),
              to: f.range?.[1].endOf('day').add(1, 'ms').toISOString(),
              page: f.page,
              pageSize: PAGE_SIZE,
            },
          },
        }),
      ),
    placeholderData: keepPreviousData,
  });

  return (
    <div className={styles.page}>
      <Typography.Title level={3} className={styles.pageTitle}>
        审计日志
      </Typography.Title>
      <Space wrap style={{ marginBottom: 16 }}>
        <Select<AuditAction>
          aria-label="操作"
          placeholder="全部操作"
          allowClear
          style={{ width: 180 }}
          value={f.action}
          onChange={(action) => setF({ ...f, action, page: 1 })}
          options={Object.entries(ACTION_LABELS).map(([value, label]) => ({ value: value as AuditAction, label }))}
        />
        <DatePicker.RangePicker
          aria-label="时间"
          value={f.range}
          onChange={(r) => setF({ ...f, range: r?.[0] && r[1] ? [r[0], r[1]] : undefined, page: 1 })}
        />
      </Space>
      {logs.isError && (
        <Typography.Paragraph type="danger" role="alert">
          {errorMessage(logs.error)}
        </Typography.Paragraph>
      )}
      <Table<AuditLog>
        rowKey="id"
        loading={logs.isFetching}
        dataSource={logs.data?.data ?? []}
        scroll={{ x: 900 }}
        pagination={{
          current: f.page,
          pageSize: PAGE_SIZE,
          total: logs.data?.meta?.total ?? 0,
          showSizeChanger: false,
          showTotal: (t) => `共 ${t} 条`,
          onChange: (page) => setF({ ...f, page }),
        }}
        columns={[
          { title: '时间', dataIndex: 'createdAt', width: 160, render: (v: string) => formatTime(v) },
          { title: '管理员', dataIndex: 'username', width: 130 },
          {
            title: '操作',
            dataIndex: 'action',
            width: 150,
            render: (v: AuditAction) => <Tag color={v === 'login_failed' ? 'error' : undefined}>{ACTION_LABELS[v] ?? v}</Tag>,
          },
          { title: '对象', render: (_, l) => (l.targetId ? `${l.targetType} ${l.targetId}` : '—') },
          { title: '说明', dataIndex: 'detail', render: (v: Record<string, unknown>) => describeAudit(v) },
          { title: 'IP', dataIndex: 'ip', width: 130 },
        ]}
      />
    </div>
  );
}
