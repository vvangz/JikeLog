import 'package:dio/dio.dart';

/// 服务端错误码（与 server/api/openapi.yaml 及服务端常量一致）。
abstract final class ApiErrorCode {
  static const unauthorized = 'UNAUTHORIZED';
  static const validationFailed = 'VALIDATION_FAILED';
  static const rateLimited = 'RATE_LIMITED';
  static const smsRateLimited = 'SMS_RATE_LIMITED';
  static const smsCodeInvalid = 'SMS_CODE_INVALID';
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const accountLocked = 'ACCOUNT_LOCKED';
  static const usernameTaken = 'USERNAME_TAKEN';
  static const phoneTaken = 'PHONE_TAKEN';
  static const refreshInvalid = 'REFRESH_INVALID';
  static const ticketInvalid = 'REGISTRATION_TICKET_INVALID';

  // 同步与附件（M2）
  static const e2eSessionInvalid = 'E2E_SESSION_INVALID';
  static const e2eKeyUnknown = 'E2E_KEY_UNKNOWN';
  static const recordNotFound = 'RECORD_NOT_FOUND';
  static const uploadIncomplete = 'UPLOAD_INCOMPLETE';
  static const quotaExceeded = 'QUOTA_EXCEEDED';
  static const attachmentTooLarge = 'ATTACHMENT_TOO_LARGE';

  /// 客户端自定义：网络不可达或超时。
  static const network = 'NETWORK_ERROR';

  /// 客户端自定义：响应无法解析。
  static const unexpected = 'UNEXPECTED_RESPONSE';
}

/// 接口调用失败。[message] 可直接展示给用户。
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.status,
    this.fields = const {},
    this.retryAfter,
  });

  /// 把 dio 错误转换为 ApiException：优先读取服务端错误信封。
  factory ApiException.fromDio(DioException e) {
    final res = e.response;
    final data = res?.data;
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final err = data['error'] as Map<String, dynamic>;
      final details = err['details'];
      final fields = <String, String>{};
      int? retrySecs;
      if (details is Map<String, dynamic>) {
        final f = details['fields'];
        if (f is Map<String, dynamic>) {
          f.forEach((k, v) => fields[k] = '$v');
        }
        final r = details['retryAfterSeconds'];
        if (r is num) retrySecs = r.toInt();
      }
      return ApiException(
        code: '${err['code'] ?? ApiErrorCode.unexpected}',
        message: '${err['message'] ?? '请求失败'}',
        status: res?.statusCode,
        fields: fields,
        retryAfter: retrySecs == null ? null : Duration(seconds: retrySecs),
      );
    }
    if (res == null) {
      return const ApiException(
        code: ApiErrorCode.network,
        message: '网络连接失败，请检查网络后重试',
      );
    }
    return ApiException(
      code: ApiErrorCode.unexpected,
      message: '服务暂时不可用（${res.statusCode}），请稍后重试',
      status: res.statusCode,
    );
  }

  final String code;
  final String message;
  final int? status;

  /// 字段级校验错误：{字段名: 原因}。
  final Map<String, String> fields;
  final Duration? retryAfter;

  bool get isNetwork => code == ApiErrorCode.network;

  @override
  String toString() => 'ApiException($code, $status): $message';
}
