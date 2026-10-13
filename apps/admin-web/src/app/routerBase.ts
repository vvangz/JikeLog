/** 路由的基础路径：部署在 /admin/ 下时为 /admin（构建时的 base 带结尾斜杠）。 */
export function routerBase(base: string): string {
  return base.replace(/\/+$/, '') || '/';
}
