/** 管理员密码规则：至少 10 位，同时包含字母和数字（与服务端一致）。 */
export function passwordProblem(pw: string): string | null {
  if (pw.length < 10) return '密码至少 10 位';
  if (pw.length > 128) return '密码最多 128 位';
  if (!/\p{L}/u.test(pw) || !/\p{N}/u.test(pw)) return '密码需要同时包含字母和数字';
  return null;
}

export const passwordRule = {
  validator: async (_: unknown, v: string | undefined) => {
    const p = passwordProblem(v ?? '');
    if (p) throw new Error(p);
  },
};
