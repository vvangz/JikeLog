import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'isrg_roots.dart';

/// 传输层信任策略（ADR-012 第 5 节）。
///
/// 正式版连接 HTTPS 服务器时只信任 Let's Encrypt 的两个根证书（锁定 CA）：
/// 即使设备上被装了别的根证书（企业代理、恶意软件），也无法冒充服务器。
/// 调试构建与本地 HTTP 联调使用系统信任库。
/// API、对象存储（附件）、导出下载与实时连接都经由同一个域名，统一使用这里的客户端。
class TlsPolicy {
  TlsPolicy._(this._context);

  /// 使用系统信任库。
  static final system = TlsPolicy._(null);

  /// 只信任 [rootPems] 中的根证书（PEM）。
  factory TlsPolicy.pinnedTo(List<String> rootPems) {
    final ctx = SecurityContext(withTrustedRoots: false);
    for (final pem in rootPems) {
      ctx.setTrustedCertificatesBytes(utf8.encode(pem));
    }
    return TlsPolicy._(ctx);
  }

  /// 按构建类型决定：正式版 + HTTPS 地址 + 未显式关闭时锁定到 Let's Encrypt。
  factory TlsPolicy.forBuild({
    required bool release,
    required String baseUrl,
    bool pinning = true,
  }) {
    final https = Uri.tryParse(baseUrl)?.scheme == 'https';
    return release && https && pinning
        ? TlsPolicy.pinnedTo(isrgRootPems)
        : system;
  }

  /// 当前构建使用的策略。只应由 tlsPolicyProvider 读取，其他地方经由 provider 获得，测试才能统一替换。
  static final current = TlsPolicy.forBuild(
    release: kReleaseMode,
    baseUrl: AppConfig.apiBaseUrl,
    pinning: AppConfig.pinCa,
  );

  final SecurityContext? _context;

  bool get pinned => _context != null;

  /// 新建一个遵循本策略的 [HttpClient]。
  HttpClient httpClient() => HttpClient(context: _context);

  /// Dio 的连接适配器；使用系统信任库时返回 null（保持 Dio 默认）。
  HttpClientAdapter? adapter() =>
      pinned ? IOHttpClientAdapter(createHttpClient: httpClient) : null;

  /// 新建一个遵循本策略的 Dio。
  Dio dio([BaseOptions? options]) {
    final dio = Dio(options);
    final a = adapter();
    if (a != null) dio.httpClientAdapter = a;
    return dio;
  }

  /// WebSocket 握手用的客户端（各次重连共用，随进程存在，不需要关闭）；使用系统信任库时为 null。
  late final HttpClient? webSocketClient = pinned ? httpClient() : null;
}
