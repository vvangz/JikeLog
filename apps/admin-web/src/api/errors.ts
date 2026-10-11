/** 接口返回的错误：错误码、给用户看的说明与 HTTP 状态码。 */
export class ApiError extends Error {
  readonly code: string;
  readonly status: number;
  readonly fields: Record<string, string>;

  constructor(code: string, message: string, status: number, fields: Record<string, string> = {}) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
    this.fields = fields;
  }
}

interface ErrorEnvelope {
  error?: { code?: string; message?: string; details?: { fields?: Record<string, string> } };
}

/** 由错误信封构造 ApiError；没有信封（网络错误、网关错误）时给出通用说明。 */
export function toApiError(body: unknown, status: number): ApiError {
  const e = (body as ErrorEnvelope | undefined)?.error;
  if (e?.code) {
    return new ApiError(e.code, e.message ?? '请求失败', status, e.details?.fields ?? {});
  }
  if (status === 0) return new ApiError('NETWORK', '无法连接服务器，请检查网络', status);
  return new ApiError('UNEXPECTED', `请求失败（${status}）`, status);
}

/** 任意错误的用户可读说明。 */
export function errorMessage(err: unknown): string {
  if (err instanceof ApiError) {
    const field = Object.values(err.fields)[0];
    return field ?? err.message;
  }
  return '出了点问题，请稍后重试';
}
