import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';

/// 建立 WebSocket 连接（测试中替换）。
typedef ChannelFactory = WebSocketChannel Function(
  Uri uri,
  Map<String, String> headers,
);

/// 实时连接（[RealtimeClient] 实现；测试中替换为不联网的实现）。
abstract interface class RealtimeLink {
  void start();
  Future<void> stop();
}

/// 实时通知客户端（ADR-005 第 5 节）：服务端只提醒"有新数据"，收到后由同步引擎拉取。
///
/// 断线后按 1、2、4…60 秒退避重连；握手失败时先刷新一次令牌（Access Token 可能已过期）。
/// 服务端以 4401 关闭表示设备已下线，此时停止重连并回调 [onRevoked]。
class RealtimeClient implements RealtimeLink {
  RealtimeClient({
    required this.client,
    required this.onChange,
    this.onRevoked,
    this.deviceId,
    ChannelFactory? connect,
    this.maxBackoff = const Duration(seconds: 60),
  }) : _connect = connect ?? _defaultConnect;

  final ApiClient client;

  /// 有其他设备的新数据（或刚连上，可能错过了通知）时调用。
  final void Function() onChange;
  final void Function()? onRevoked;

  /// 本设备 ID：忽略自己产生的通知。
  final String? Function()? deviceId;
  final ChannelFactory _connect;
  final Duration maxBackoff;

  static const closeRevoked = 4401;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _running = false;
  int _failures = 0;

  /// 每次启停加一：握手完成时代数已变（期间停止过）的连接直接关闭，避免同时存在两个连接。
  int _generation = 0;

  bool get connected => _channel != null && _sub != null;

  static WebSocketChannel _defaultConnect(
    Uri uri,
    Map<String, String> headers,
  ) => IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: const Duration(seconds: 30),
  );

  /// WebSocket 地址：与 API 同源，http → ws，https → wss。
  static Uri wsUri(String baseUrl) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/v1/sync/ws',
    );
  }

  @override
  void start() {
    if (_running) return;
    _running = true;
    _generation++;
    unawaited(_open(_generation));
  }

  @override
  Future<void> stop() async {
    _running = false;
    _generation++;
    _retry?.cancel();
    _retry = null;
    await _close();
  }

  Future<void> _close() async {
    final sub = _sub;
    final ch = _channel;
    _sub = null;
    _channel = null;
    await sub?.cancel();
    await ch?.sink.close();
  }

  Future<void> _open(int generation) async {
    final token = client.accessToken;
    if (!_running || generation != _generation) return;
    if (token == null) return _scheduleRetry();
    final ch = _connect(wsUri(client.baseUrl), {
      'Authorization': 'Bearer $token',
    });
    try {
      await ch.ready;
    } on Object catch (e) {
      debugPrint('实时通知连接失败: $e');
      _failures++;
      // 握手被拒绝多半是令牌过期：刷新后重试（刷新失败由 ApiClient 处理登录态）
      if (_failures.isOdd) await client.refreshNow();
      return _scheduleRetry();
    }
    if (!_running || generation != _generation) {
      await ch.sink.close();
      return;
    }
    _failures = 0;
    _channel = ch;
    _sub = ch.stream.listen(
      _onMessage,
      onDone: () => _onDone(ch),
      onError: (Object e) => debugPrint('实时通知连接异常: $e'),
      cancelOnError: false,
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'hello':
          onChange();
        case 'changed' when msg['origin'] != deviceId?.call():
          onChange();
      }
    } on FormatException {
      // 忽略无法解析的消息
    }
  }

  void _onDone(WebSocketChannel ch) {
    if (!identical(ch, _channel)) return;
    _sub = null;
    _channel = null;
    if (ch.closeCode == closeRevoked) {
      _running = false;
      onRevoked?.call();
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running) return;
    final secs = min(maxBackoff.inSeconds, 1 << min(_failures, 6));
    _retry?.cancel();
    final generation = _generation;
    _retry = Timer(
      Duration(seconds: max(secs, 1)),
      () => unawaited(_open(generation)),
    );
  }
}
