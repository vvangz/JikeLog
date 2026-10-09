import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/providers.dart';
import 'package:jikelog/core/api/api_client.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/device/device_identity.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/realtime.dart';
import 'package:jikelog/core/sync/sync_providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';

import 'fake_sync_server.dart';

/// 一次被记录的请求。
class RecordedRequest {
  RecordedRequest(this.method, this.path, this.body, this.authorization);

  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final String? authorization;
}

/// 测试用响应。
class FakeResponse {
  const FakeResponse(this.status, [this.json]);

  /// 成功信封。
  factory FakeResponse.ok(Object? data, {int status = 200}) => FakeResponse(
    status,
    {'success': true, 'requestId': 'test', 'data': data},
  );

  /// 错误信封。
  factory FakeResponse.error(
    int status,
    String code, {
    String message = '出错了',
    Map<String, dynamic>? details,
  }) => FakeResponse(status, {
    'success': false,
    'requestId': 'test',
    'error': {'code': code, 'message': message, 'details': ?details},
  });

  final int status;
  final Object? json;
}

typedef FakeHandler = FutureOr<FakeResponse> Function(RecordedRequest req);

/// 按 "METHOD 路径" 匹配处理器的假后端；未注册的路由返回 404。设置 [offline] 模拟网络不可达。
class FakeBackend implements HttpClientAdapter {
  final Map<String, FakeHandler> _routes = {};
  final List<RecordedRequest> requests = [];
  bool offline = false;

  void on(String method, String path, FakeHandler handler) =>
      _routes['$method $path'] = handler;

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).length;

  RecordedRequest last(String method, String path) =>
      requests.lastWhere((r) => r.method == method && r.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final data = options.data;
    final body = data is Map<String, dynamic>
        ? data
        : (data is String && data.isNotEmpty
              ? jsonDecode(data) as Map<String, dynamic>
              : null);
    final req = RecordedRequest(
      options.method,
      options.path,
      body,
      options.headers['Authorization'] as String?,
    );
    requests.add(req);
    final handler = _routes['${options.method} ${options.path}'];
    final res = handler == null
        ? FakeResponse.error(404, 'NOT_FOUND')
        : await handler(req);
    return ResponseBody.fromString(
      res.json == null ? '' : jsonEncode(res.json),
      res.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const testDevice = DeviceIdentity(
  installationId: 'test-installation-0001',
  platform: 'android',
  model: 'Pixel 9',
  osVersion: 'Android 16',
  appVersion: '0.2.0',
);

Map<String, dynamic> userJson({
  String username = 'zhangsan',
  String nickname = '张三',
  String? phoneMasked,
}) => {
  'id': '0192a000-0000-7000-8000-000000000001',
  'username': username,
  'nickname': nickname,
  'hasPhone': phoneMasked != null,
  'phoneMasked': ?phoneMasked,
  'createdAt': '2026-10-09T08:00:00Z',
};

Map<String, dynamic> tokensJson({
  String access = 'access-1',
  String refresh = 'refresh-1',
}) => {
  'tokenType': 'Bearer',
  'accessToken': access,
  'accessExpiresAt': '2026-10-09T08:15:00Z',
  'refreshToken': refresh,
  'refreshExpiresAt': '2026-11-08T08:00:00Z',
};

Map<String, dynamic> sessionJson({
  Map<String, dynamic>? user,
  String access = 'access-1',
}) => {
  'user': user ?? userJson(),
  'tokens': tokensJson(access: access),
  'deviceId': '0192a000-0000-7000-8000-0000000000d1',
};

final testTokens = TokenPair.fromJson(tokensJson());

/// 测试用 ProviderContainer 覆盖项：内存存储 + 假后端。
List<Override> testOverrides({
  required FakeBackend backend,
  KeyValueStore? store,
  TokenStore? tokens,
  AppDatabase? db,
  FakeSyncServer? syncServer,
}) => [
  keyValueStoreProvider.overrideWithValue(store ?? MemoryStore()),
  deviceIdentityProvider.overrideWithValue(testDevice),
  tokenStoreProvider.overrideWithValue(tokens ?? MemoryTokenStore()),
  apiClientProvider.overrideWith(
    (ref) => ApiClient(
      baseUrl: 'http://test',
      tokenStore: ref.watch(tokenStoreProvider),
      adapter: backend,
    ),
  ),
  appDatabaseProvider.overrideWithValue(db ?? testDatabase()),
  hybridClockProvider.overrideWithValue(
    HybridClock(installationId: testDevice.installationId),
  ),
  syncTransportProvider.overrideWithValue(
    FakeTransport(syncServer ?? FakeSyncServer()),
  ),
  realtimeClientProvider.overrideWithValue(FakeRealtime()),
];

/// 组件测试用的内存数据库：同步关闭流查询，避免组件树销毁后残留清理定时器。
AppDatabase testDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// 不联网的实时连接，只记录启停。
class FakeRealtime implements RealtimeLink {
  bool running = false;

  @override
  void start() => running = true;

  @override
  Future<void> stop() async => running = false;
}

/// 轮询直到条件成立（最多 2 秒），用于等待异步状态变化（如启动时的登录态恢复）。
Future<void> eventually(bool Function() condition, {String reason = ''}) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('等待超时 $reason');
}

void expectRequestCount(FakeBackend b, String method, String path, int n) =>
    expect(b.count(method, path), n, reason: '$method $path 请求次数');
