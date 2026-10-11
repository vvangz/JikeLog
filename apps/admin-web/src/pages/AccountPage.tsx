import { Alert, Button, Card, Descriptions, Space, Typography } from 'antd';
import { useAuth } from '../auth/useAuth';
import { formatTime, ROLE_LABELS } from '../format';
import { ChangePasswordForm } from './ChangePasswordForm';
import styles from '../App.module.css';

/** 账号：当前管理员信息、修改密码、退出登录。必须修改初始密码时只显示这一页。 */
export function AccountPage() {
  const { admin, logout } = useAuth();
  if (!admin) return null;
  return (
    <div className={styles.page}>
      <Typography.Title level={3} className={styles.pageTitle}>
        账号
      </Typography.Title>
      <Space direction="vertical" size="large" style={{ width: '100%' }}>
        {admin.mustChangePassword && (
          <Alert type="warning" showIcon message="这是初始密码或已被重置的密码，请先修改密码再使用管理后台。" />
        )}
        <Card title="当前管理员">
          <Descriptions column={{ xs: 1, md: 2 }}>
            <Descriptions.Item label="用户名">{admin.username}</Descriptions.Item>
            <Descriptions.Item label="角色">{ROLE_LABELS[admin.role]}</Descriptions.Item>
            <Descriptions.Item label="最后登录">{formatTime(admin.lastLoginAt)}</Descriptions.Item>
            <Descriptions.Item label="创建时间">{formatTime(admin.createdAt)}</Descriptions.Item>
          </Descriptions>
        </Card>
        <Card title="修改密码">
          <ChangePasswordForm />
        </Card>
        <Button danger onClick={() => void logout()}>
          退出登录
        </Button>
      </Space>
    </div>
  );
}
