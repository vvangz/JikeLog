import { PlusOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { App, Button, Form, Input, Modal, Select, Space, Table, Tag, Typography } from 'antd';
import { useState } from 'react';
import type { components } from '../api/schema.gen';
import { errorMessage } from '../api/errors';
import { useAuth } from '../auth/useAuth';
import { QueryState } from '../components/QueryState';
import { formatTime, ROLE_LABELS, type AdminRole } from '../format';
import { passwordRule } from './passwordRules';
import styles from '../App.module.css';

type Admin = components['schemas']['AdminProfile'];

const ROLE_OPTIONS = (Object.keys(ROLE_LABELS) as AdminRole[]).map((value) => ({ value, label: ROLE_LABELS[value] }));

/** 管理员账号管理（仅超级管理员）：新建、修改角色、停用、重置密码。 */
export function AdminsPage() {
  const { client, call, admin: me } = useAuth();
  const queryClient = useQueryClient();
  const { message, modal } = App.useApp();
  const [creating, setCreating] = useState(false);
  const [resetting, setResetting] = useState<Admin | null>(null);

  const admins = useQuery({
    queryKey: ['admins'],
    queryFn: () => call(() => client.GET('/api/admin/v1/admins')).then((r) => r.data),
  });
  const done = (text: string) => {
    void message.success(text);
    void queryClient.invalidateQueries({ queryKey: ['admins'] });
  };
  const update = useMutation({
    mutationFn: (v: { id: string; role?: AdminRole; disabled?: boolean }) =>
      call(() =>
        client.PATCH('/api/admin/v1/admins/{adminId}', {
          params: { path: { adminId: v.id } },
          body: { role: v.role, disabled: v.disabled },
        }),
      ),
    onSuccess: () => done('已保存'),
    onError: (e) => void message.error(errorMessage(e)),
  });

  const toggle = (a: Admin) =>
    modal.confirm({
      title: a.disabled ? `启用 ${a.username}？` : `停用 ${a.username}？`,
      content: a.disabled ? '启用后对方可以重新登录。' : '停用后对方立即退出登录，并且不能再登录。',
      okText: a.disabled ? '启用' : '停用',
      okButtonProps: { danger: !a.disabled },
      onOk: () => update.mutateAsync({ id: a.id, disabled: !a.disabled }),
    });

  if (me?.role !== 'super_admin') {
    return <Typography.Paragraph>只有超级管理员可以管理管理员账号。</Typography.Paragraph>;
  }

  return (
    <div className={styles.page}>
      <Space style={{ width: '100%', justifyContent: 'space-between' }}>
        <Typography.Title level={3} className={styles.pageTitle}>
          管理员
        </Typography.Title>
        <Button type="primary" icon={<PlusOutlined />} onClick={() => setCreating(true)}>
          新建管理员
        </Button>
      </Space>
      <QueryState query={admins}>
        {(list) => (
          <Table<Admin>
            rowKey="id"
            dataSource={list}
            pagination={false}
            scroll={{ x: 760 }}
            columns={[
              { title: '用户名', dataIndex: 'username' },
              {
                title: '角色',
                dataIndex: 'role',
                render: (role: AdminRole, a) =>
                  a.id === me.id ? (
                    ROLE_LABELS[role]
                  ) : (
                    <Select<AdminRole>
                      aria-label={`${a.username} 的角色`}
                      size="small"
                      value={role}
                      options={ROLE_OPTIONS}
                      style={{ width: 130 }}
                      onChange={(r) => update.mutate({ id: a.id, role: r })}
                    />
                  ),
              },
              {
                title: '状态',
                render: (_, a) => (
                  <Space size={4} wrap>
                    {a.disabled ? <Tag color="error">已停用</Tag> : <Tag color="success">正常</Tag>}
                    {a.mustChangePassword && <Tag color="warning">待修改初始密码</Tag>}
                  </Space>
                ),
              },
              { title: '最后登录', dataIndex: 'lastLoginAt', render: (v?: string) => formatTime(v) },
              {
                title: '操作',
                render: (_, a) =>
                  a.id === me.id ? (
                    <Typography.Text type="secondary">当前账号</Typography.Text>
                  ) : (
                    <Space>
                      <Button size="small" onClick={() => setResetting(a)}>
                        重置密码
                      </Button>
                      <Button size="small" danger={!a.disabled} onClick={() => toggle(a)}>
                        {a.disabled ? '启用' : '停用'}
                      </Button>
                    </Space>
                  ),
              },
            ]}
          />
        )}
      </QueryState>
      <CreateAdminModal open={creating} onClose={() => setCreating(false)} onCreated={() => done('已新建管理员')} />
      <ResetPasswordModal admin={resetting} onClose={() => setResetting(null)} onDone={() => done('已重置密码')} />
    </div>
  );
}

interface CreateForm {
  username: string;
  role: AdminRole;
  password: string;
}

interface CreateAdminModalProps {
  open: boolean;
  onClose: () => void;
  onCreated: () => void;
}

function CreateAdminModal({ open, onClose, onCreated }: CreateAdminModalProps) {
  const { client, call } = useAuth();
  const { message } = App.useApp();
  const [form] = Form.useForm<CreateForm>();
  const create = useMutation({
    mutationFn: (v: CreateForm) => call(() => client.POST('/api/admin/v1/admins', { body: v })),
    onSuccess: () => {
      form.resetFields();
      onClose();
      onCreated();
    },
    onError: (e) => void message.error(errorMessage(e)),
  });
  return (
    <Modal
      title="新建管理员"
      open={open}
      okText="新建"
      onOk={() => form.submit()}
      onCancel={onClose}
      confirmLoading={create.isPending}
      destroyOnHidden
    >
      <Form<CreateForm> name="createAdmin" form={form} layout="vertical" initialValues={{ role: 'viewer' }} onFinish={(v) => create.mutate(v)}>
        <Form.Item
          label="用户名"
          name="username"
          rules={[
            { required: true, message: '请输入用户名' },
            { pattern: /^[A-Za-z][A-Za-z0-9_]{3,19}$/, message: '4–20 位字母、数字或下划线，以字母开头' },
          ]}
        >
          <Input autoComplete="off" />
        </Form.Item>
        <Form.Item label="角色" name="role">
          <Select<AdminRole> options={ROLE_OPTIONS} />
        </Form.Item>
        <Form.Item
          label="初始密码"
          name="password"
          extra="对方第一次登录时必须修改"
          rules={[{ required: true, message: '请输入初始密码' }, passwordRule]}
        >
          <Input.Password autoComplete="new-password" />
        </Form.Item>
      </Form>
    </Modal>
  );
}

interface ResetPasswordModalProps {
  admin: Admin | null;
  onClose: () => void;
  onDone: () => void;
}

function ResetPasswordModal({ admin, onClose, onDone }: ResetPasswordModalProps) {
  const { client, call } = useAuth();
  const { message } = App.useApp();
  const [form] = Form.useForm<{ password: string }>();
  const reset = useMutation({
    mutationFn: (v: { id: string; password: string }) =>
      call(() =>
        client.POST('/api/admin/v1/admins/{adminId}/password', {
          params: { path: { adminId: v.id } },
          body: { password: v.password },
        }),
      ),
    onSuccess: () => {
      form.resetFields();
      onClose();
      onDone();
    },
    onError: (e) => void message.error(errorMessage(e)),
  });
  return (
    <Modal
      title={admin ? `重置 ${admin.username} 的密码` : ''}
      open={admin !== null}
      okText="重置"
      onOk={() => form.submit()}
      onCancel={onClose}
      confirmLoading={reset.isPending}
      destroyOnHidden
    >
      <Typography.Paragraph type="secondary">对方会立即退出登录，下次登录时必须修改密码。</Typography.Paragraph>
      <Form<{ password: string }>
        name="resetPassword"
        form={form}
        layout="vertical"
        onFinish={(v) => admin && reset.mutate({ id: admin.id, password: v.password })}
      >
        <Form.Item label="新密码" name="password" rules={[{ required: true, message: '请输入新密码' }, passwordRule]}>
          <Input.Password autoComplete="new-password" />
        </Form.Item>
      </Form>
    </Modal>
  );
}
