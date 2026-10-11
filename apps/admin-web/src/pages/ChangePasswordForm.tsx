import { App, Button, Form, Input } from 'antd';
import { useState } from 'react';
import { errorMessage } from '../api/errors';
import { useAuth } from '../auth/useAuth';
import { passwordRule } from './passwordRules';

interface PasswordForm {
  currentPassword: string;
  newPassword: string;
  confirm: string;
}

interface ChangePasswordFormProps {
  onDone?: () => void;
}

/** 修改自己的密码：修改后其他会话失效，当前会话保留。 */
export function ChangePasswordForm({ onDone }: ChangePasswordFormProps) {
  const { client, call, passwordChanged } = useAuth();
  const { message } = App.useApp();
  const [form] = Form.useForm<PasswordForm>();
  const [busy, setBusy] = useState(false);

  const submit = async (v: PasswordForm) => {
    setBusy(true);
    try {
      await call(() =>
        client.PUT('/api/admin/v1/me/password', {
          body: { currentPassword: v.currentPassword, newPassword: v.newPassword },
        }),
      );
      form.resetFields();
      passwordChanged();
      void message.success('密码已修改，其他设备上的登录已失效');
      onDone?.();
    } catch (e) {
      void message.error(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Form<PasswordForm> form={form} layout="vertical" onFinish={submit} disabled={busy} style={{ maxWidth: 400 }}>
      <Form.Item label="当前密码" name="currentPassword" rules={[{ required: true, message: '请输入当前密码' }]}>
        <Input.Password autoComplete="current-password" />
      </Form.Item>
      <Form.Item
        label="新密码"
        name="newPassword"
        extra="至少 10 位，同时包含字母和数字"
        rules={[{ required: true, message: '请输入新密码' }, passwordRule]}
      >
        <Input.Password autoComplete="new-password" />
      </Form.Item>
      <Form.Item
        label="确认新密码"
        name="confirm"
        dependencies={['newPassword']}
        rules={[
          { required: true, message: '请再次输入新密码' },
          ({ getFieldValue }) => ({
            validator: async (_, v: string | undefined) => {
              if (v && v !== getFieldValue('newPassword')) throw new Error('两次输入的密码不一致');
            },
          }),
        ]}
      >
        <Input.Password autoComplete="new-password" />
      </Form.Item>
      <Button type="primary" htmlType="submit" loading={busy}>
        修改密码
      </Button>
    </Form>
  );
}
