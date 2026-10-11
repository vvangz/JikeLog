import { LockOutlined, UserOutlined } from '@ant-design/icons';
import { Alert, Button, Card, Form, Input, Space, Typography } from 'antd';
import { useState } from 'react';
import { errorMessage } from '../api/errors';
import { useAuth } from '../auth/useAuth';
import { Logo } from '../components/Logo';
import styles from '../App.module.css';

interface LoginForm {
  username: string;
  password: string;
}

/** 管理员登录。 */
export function LoginPage() {
  const { login } = useAuth();
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (v: LoginForm) => {
    setBusy(true);
    setError(null);
    try {
      await login(v.username.trim(), v.password);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={styles.center}>
      <Card className={styles.loginCard}>
        <Space direction="vertical" size="large" style={{ width: '100%' }}>
          <Space align="center">
            <Logo size={36} />
            <Typography.Title level={4} style={{ margin: 0 }}>
              即刻日志管理后台
            </Typography.Title>
          </Space>
          {error && <Alert type="error" showIcon message={error} />}
          <Form<LoginForm> layout="vertical" onFinish={submit} requiredMark={false} disabled={busy}>
            <Form.Item label="用户名" name="username" rules={[{ required: true, message: '请输入用户名' }]}>
              <Input prefix={<UserOutlined />} autoComplete="username" autoFocus />
            </Form.Item>
            <Form.Item label="密码" name="password" rules={[{ required: true, message: '请输入密码' }]}>
              <Input.Password prefix={<LockOutlined />} autoComplete="current-password" />
            </Form.Item>
            <Button type="primary" htmlType="submit" block loading={busy}>
              登录
            </Button>
          </Form>
          <Typography.Text type="secondary">管理员只能查看用户的配置信息，所有操作都会记录在审计日志中。</Typography.Text>
        </Space>
      </Card>
    </div>
  );
}
