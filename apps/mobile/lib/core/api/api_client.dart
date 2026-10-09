import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/stores.dart';
import 'api_exception.dart';
import 'models.dart';

/// HTTP 客户端：统一解包响应信封、附加 Access Token，并在令牌过期时自动刷新后重试一次。
///
/// 并发请求同时遇到 401 时只发起一次刷新（single-flight）；刷新被服务端拒绝时清空令牌并回调
/// [onSessionExpired]，网络失败时保留令牌（离线状态不应把用户踢出登录）。
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this._tokenStore,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(_options(baseUrl)),
       _refreshDio = Dio(_options(baseUrl)) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _attachToken, onError: _onError),
    );
  }

  static BaseOptions _options(String baseUrl) => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
  );

  final TokenStore _tokenStore;
  final Dio _dio;
  final Dio _refreshDio;
  TokenPair? _tokens;
  Future<TokenPair?>? _refreshing;

  /// 会话失效（Refresh Token 被拒绝）时调用。
  void Function()? onSessionExpired;

  static const _retriedKey = 'jk.retried';

  /// 登录态代次：每次保存或清除令牌都会递增。刷新请求返回时若代次已变（如期间退出登录），丢弃结果。
  int _generation = 0;

  /// 从安全存储加载令牌，返回是否存在登录态。
  Future<bool> restore() async {
    _tokens = await _tokenStore.read();
    return _tokens != null;
  }

  bool get hasTokens => _tokens != null;

  Future<void> saveTokens(TokenPair tokens) async {
    _generation++;
    _tokens = tokens;
    await _tokenStore.write(tokens);
  }

  Future<void> clearTokens() async {
    _generation++;
    _tokens = null;
    await _tokenStore.clear();
  }

  Future<dynamic> get(String path, {Map<String, String>? headers}) =>
      _send('GET', path, null, headers);
  Future<dynamic> post(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) => _send('POST', path, body, headers);
  Future<dynamic> put(String path, Object? body) => _send('PUT', path, body);
  Future<dynamic> patch(String path, Object? body) =>
      _send('PATCH', path, body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// 当前 Access Token（WebSocket 握手时使用）；未登录时为 null。
  String? get accessToken => _tokens?.accessToken;

  /// 立即刷新令牌（WebSocket 因令牌过期被拒绝后调用），返回是否成功。
  Future<bool> refreshNow() async => await _refreshOnce() != null;

  /// API 地址（用于拼接 WebSocket 地址）。
  String get baseUrl => _dio.options.baseUrl;

  /// 发送请求并返回信封中的 data；失败时抛出 [ApiException]。
  Future<dynamic> _send(
    String method,
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) async {
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        options: Options(method: method, headers: headers),
      );
      final data = res.data;
      if (data is Map<String, dynamic> && data['success'] == true) {
        return data['data'];
      }
      throw ApiException(
        code: ApiErrorCode.unexpected,
        message: '服务器响应格式不正确',
        status: res.statusCode,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  void _attachToken(RequestOptions options, RequestInterceptorHandler handler) {
    final t = _tokens;
    if (t != null) {
      options.headers['Authorization'] = 'Bearer ${t.accessToken}';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler handler) async {
    final req = e.requestOptions;
    final sent = req.headers['Authorization'];
    if (e.response?.statusCode != 401 ||
        sent == null ||
        req.extra[_retriedKey] == true) {
      return handler.next(e);
    }
    // 该请求带的是旧令牌、而其他请求已经刷新过：直接用当前令牌重试，不再轮换
    final current = _tokens;
    final fresh = current != null && sent != 'Bearer ${current.accessToken}'
        ? current
        : await _refreshOnce();
    if (fresh == null) {
      return handler.next(e);
    }
    try {
      req.extra[_retriedKey] = true;
      req.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
      handler.resolve(await _dio.fetch<dynamic>(req));
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  /// 合并并发的刷新请求，返回新令牌；失败返回 null。
  Future<TokenPair?> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<TokenPair?> _doRefresh() async {
    final current = _tokens;
    if (current == null) return null;
    final generation = _generation;
    final TokenPair pair;
    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': current.refreshToken},
      );
      pair = TokenPair.fromJson(res.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if ((status == 401 || status == 400) && generation == _generation) {
        await clearTokens();
        onSessionExpired?.call();
      }
      return null; // 网络失败、5xx、429：保留令牌，稍后再试
    } on Object catch (e) {
      debugPrint('刷新令牌响应异常: $e');
      return null;
    }
    if (generation != _generation) return null; // 期间已退出或重新登录
    try {
      await saveTokens(pair);
    } on Object catch (e) {
      // 服务端已轮换，旧令牌失效：至少在内存中保留新令牌，本次运行期间可继续使用
      _tokens = pair;
      debugPrint('保存新令牌失败: $e');
    }
    return pair;
  }
}
