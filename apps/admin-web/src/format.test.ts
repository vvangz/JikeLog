import { describe, expect, it } from 'vitest';
import { ApiError, errorMessage, toApiError } from './api/errors';
import { selectedKey } from './app/nav';
import { describeAudit, formatBytes, formatTime, fromNow, platformLabel, reminderLabel, themeLabel } from './format';
import { passwordProblem } from './pages/passwordRules';

describe('格式化', () => {
  it('文件大小', () => {
    expect(formatBytes(512)).toBe('512 B');
    expect(formatBytes(1536)).toBe('1.5 KB');
    expect(formatBytes(25 * 1024 * 1024)).toBe('25 MB');
    expect(formatBytes(3 * 1024 ** 4)).toBe('3.0 TB');
  });

  it('时间与相对时间', () => {
    expect(formatTime(undefined)).toBe('—');
    const now = new Date('2026-10-11T12:00:00Z');
    const ago = (s: number) => new Date(now.getTime() - s * 1000).toISOString();
    expect(fromNow(null, now)).toBe('—');
    expect(fromNow(ago(10), now)).toBe('刚刚');
    expect(fromNow(ago(300), now)).toBe('5 分钟前');
    expect(fromNow(ago(7200), now)).toBe('2 小时前');
    expect(fromNow(ago(86400 * 3), now)).toBe('3 天前');
    expect(fromNow('2026-01-02T00:00:00Z', now)).toBe('2026-01-02');
  });

  it('平台、主题与提醒', () => {
    expect(platformLabel('android')).toBe('Android');
    expect(platformLabel('beos')).toBe('beos');
    expect(themeLabel('system')).toBe('跟随系统');
    expect(themeLabel('x')).toBe('x');
    expect([0, 15, 60, 1440, 90].map(reminderLabel)).toEqual(['准时', '提前 15 分钟', '提前 1 小时', '提前 1 天', '提前 90 分钟']);
  });

  it('审计说明', () => {
    expect(describeAudit({})).toBe('—');
    expect(describeAudit({ q: 'alice', page: 2, empty: '' })).toBe('搜索：alice · 页码：2');
    expect(describeAudit({ reason: 'locked' })).toBe('原因：账号已锁定');
    expect(describeAudit({ reason: 'other', disabled: true, custom: 1 })).toBe('原因：other · 停用：是 · custom：1');
  });
});

describe('错误', () => {
  it('由错误信封构造，字段错误优先显示', () => {
    const e = toApiError({ error: { code: 'VALIDATION_FAILED', message: '参数校验失败', details: { fields: { password: '密码太短' } } } }, 422);
    expect(e).toBeInstanceOf(ApiError);
    expect(e.code).toBe('VALIDATION_FAILED');
    expect(errorMessage(e)).toBe('密码太短');
    expect(errorMessage(toApiError({ error: { code: 'X' } }, 400))).toBe('请求失败');
    expect(errorMessage(toApiError(undefined, 0))).toBe('无法连接服务器，请检查网络');
    expect(errorMessage(toApiError('bad gateway', 502))).toBe('请求失败（502）');
    expect(errorMessage(new Error('boom'))).toBe('出了点问题，请稍后重试');
  });
});

describe('其他', () => {
  it('密码规则', () => {
    expect(passwordProblem('short1')).toBe('密码至少 10 位');
    expect(passwordProblem('a'.repeat(129) + '1')).toBe('密码最多 128 位');
    expect(passwordProblem('1234567890')).toBe('密码需要同时包含字母和数字');
    expect(passwordProblem('密码密码密码12345')).toBeNull();
  });

  it('导航选中项', () => {
    expect(selectedKey('/users/abc')).toBe('/users');
    expect(selectedKey('/dashboard')).toBe('/dashboard');
    expect(selectedKey('/unknown')).toBe('');
  });
});
