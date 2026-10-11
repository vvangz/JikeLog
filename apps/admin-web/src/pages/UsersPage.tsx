import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { Input, Table, Typography } from 'antd';
import { Link, useSearchParams } from 'react-router';
import type { components } from '../api/schema.gen';
import { errorMessage } from '../api/errors';
import { useAuth } from '../auth/useAuth';
import { formatBytes, formatTime, fromNow } from '../format';
import styles from '../App.module.css';

type UserSummary = components['schemas']['AdminUserSummary'];

const PAGE_SIZE = 20;

/** 用户列表：按用户名、昵称或手机号末尾搜索；手机号脱敏显示。搜索词与页码保存在地址中。 */
export function UsersPage() {
  const { client, call } = useAuth();
  const [params, setParams] = useSearchParams();
  const q = params.get('q') ?? '';
  const rawPage = Number(params.get('page'));
  const page = Number.isInteger(rawPage) && rawPage >= 1 && rawPage <= 1000 ? rawPage : 1;

  const users = useQuery({
    queryKey: ['users', q, page],
    queryFn: () =>
      call(() =>
        client.GET('/api/admin/v1/users', { params: { query: { q: q || undefined, page, pageSize: PAGE_SIZE } } }),
      ),
    placeholderData: keepPreviousData,
  });

  const update = (next: { q?: string; page?: number }) => {
    const p = new URLSearchParams();
    const nq = next.q ?? q;
    const np = next.page ?? page;
    if (nq) p.set('q', nq);
    if (np > 1) p.set('page', String(np));
    // 翻页不新增历史记录；新的搜索才新增
    setParams(p, { replace: next.q === undefined });
  };

  return (
    <div className={styles.page}>
      <Typography.Title level={3} className={styles.pageTitle}>
        用户
      </Typography.Title>
      <Input.Search
        aria-label="搜索用户"
        placeholder="用户名、昵称或手机号后 4 位"
        allowClear
        key={q}
        defaultValue={q}
        maxLength={30}
        onSearch={(v) => update({ q: v.trim(), page: 1 })}
        style={{ maxWidth: 360, marginBottom: 16 }}
      />
      {users.isError && (
        <Typography.Paragraph type="danger" role="alert">
          {errorMessage(users.error)}
        </Typography.Paragraph>
      )}
      <Table<UserSummary>
        rowKey="id"
        loading={users.isFetching}
        dataSource={users.data?.data ?? []}
        scroll={{ x: 760 }}
        pagination={{
          current: page,
          pageSize: PAGE_SIZE,
          total: users.data?.meta?.total ?? 0,
          showSizeChanger: false,
          showTotal: (t) => `共 ${t} 位用户`,
          onChange: (p) => update({ page: p }),
        }}
        columns={[
          {
            title: '用户名',
            dataIndex: 'username',
            render: (v: string, u) => <Link to={`/users/${u.id}`}>{v}</Link>,
          },
          { title: '昵称', dataIndex: 'nickname', render: (v: string) => v || '—' },
          { title: '手机号', dataIndex: 'phoneMasked', render: (v?: string) => v ?? '未绑定' },
          { title: '注册时间', dataIndex: 'createdAt', render: (v: string) => formatTime(v) },
          { title: '最后活跃', dataIndex: 'lastActiveAt', render: (v?: string) => fromNow(v) },
          { title: '设备', dataIndex: 'deviceCount', align: 'right' },
          { title: '附件', dataIndex: 'storageBytes', align: 'right', render: (v: number) => formatBytes(v) },
        ]}
      />
    </div>
  );
}
