import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/api/api_client.dart';
import 'package:jikelog/core/api/api_exception.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/storage/stores.dart';

import '../../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore store;
  late ApiClient client;

  setUp(() async {
    backend = FakeBackend();
    store = MemoryTokenStore(testTokens);
    client = ApiClient(
      baseUrl: 'http://test',
      tokenStore: store,
      adapter: backend,
    );
    expect(await client.restore(), isTrue);
  });

  test('解包成功信封并附加 Access Token', () async {
    backend.on('GET', '/api/v1/me', (_) => FakeResponse.ok({'a': 1}));
    expect(await client.get('/api/v1/me'), {'a': 1});
    expect(backend.last('GET', '/api/v1/me').authorization, 'Bearer access-1');
  });

  test('错误信封转换为 ApiException（字段错误、Retry-After）', () async {
    backend.on(
      'POST',
      '/x',
      (_) => FakeResponse.error(
        422,
        ApiErrorCode.validationFailed,
        message: '参数校验失败',
        details: {
          'fields': {'username': '已被占用'},
          'retryAfterSeconds': 30,
        },
      ),
    );
    final e = await client
        .post('/x', {})
        .then<ApiException?>(
          (_) => null,
          onError: (Object e) => e as ApiException,
        );
    expect(e!.code, ApiErrorCode.validationFailed);
    expect(e.status, 422);
    expect(e.fields, {'username': '已被占用'});
    expect(e.retryAfter, const Duration(seconds: 30));
    expect(e.toString(), contains('VALIDATION_FAILED'));
  });

  test('非信封响应与网络错误', () async {
    backend.on('GET', '/bad', (_) => const FakeResponse(502, 'gateway'));
    backend.on('GET', '/weird', (_) => const FakeResponse(200, {'hello': 1}));
    await expectLater(
      client.get('/bad'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.unexpected,
        ),
      ),
    );
    await expectLater(
      client.get('/weird'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.unexpected,
        ),
      ),
    );
    backend.offline = true;
    await expectLater(
      client.get('/bad'),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
      ),
    );
  });

  test('401 时刷新令牌并重试一次；并发请求只刷新一次', () async {
    backend.on('GET', '/api/v1/me', (req) {
      return req.authorization == 'Bearer access-2'
          ? FakeResponse.ok('me')
          : FakeResponse.error(401, ApiErrorCode.unauthorized);
    });
    final refreshGate = Completer<void>();
    backend.on('POST', '/api/v1/auth/refresh', (req) async {
      expect(req.body, {'refreshToken': 'refresh-1'});
      await refreshGate.future;
      return FakeResponse.ok(
        tokensJson(access: 'access-2', refresh: 'refresh-2'),
      );
    });
    final results = Future.wait([
      client.get('/api/v1/me'),
      client.get('/api/v1/me'),
      client.get('/api/v1/me'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    refreshGate.complete();
    expect(await results, ['me', 'me', 'me']);
    expectRequestCount(backend, 'POST', '/api/v1/auth/refresh', 1);
    expect((await store.read())!.refreshToken, 'refresh-2');
  });

  test('刷新被拒绝：清空令牌并通知会话失效', () async {
    var expired = 0;
    client.onSessionExpired = () => expired++;
    backend.on(
      'GET',
      '/api/v1/me',
      (_) => FakeResponse.error(401, ApiErrorCode.unauthorized),
    );
    backend.on(
      'POST',
      '/api/v1/auth/refresh',
      (_) => FakeResponse.error(401, ApiErrorCode.refreshInvalid),
    );
    await expectLater(client.get('/api/v1/me'), throwsA(isA<ApiException>()));
    expect(expired, 1);
    expect(client.hasTokens, isFalse);
    expect(await store.read(), isNull);
  });

  test('刷新时网络失败：保留令牌（离线不登出）', () async {
    backend.on('GET', '/api/v1/me', (_) {
      backend.offline = true; // 第一个请求返回 401 后网络断开
      return FakeResponse.error(401, ApiErrorCode.unauthorized);
    });
    await expectLater(client.get('/api/v1/me'), throwsA(isA<ApiException>()));
    expect(client.hasTokens, isTrue);
  });

  test('重试后仍 401 不再循环刷新', () async {
    backend.on(
      'GET',
      '/api/v1/me',
      (_) => FakeResponse.error(401, ApiErrorCode.unauthorized),
    );
    backend.on(
      'POST',
      '/api/v1/auth/refresh',
      (_) => FakeResponse.ok(tokensJson(access: 'access-2')),
    );
    await expectLater(
      client.get('/api/v1/me'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    expectRequestCount(backend, 'GET', '/api/v1/me', 2);
    expectRequestCount(backend, 'POST', '/api/v1/auth/refresh', 1);
  });

  test('未登录时不附加令牌、401 不触发刷新', () async {
    await client.clearTokens();
    backend.on('POST', '/api/v1/auth/login/password', (req) {
      expect(req.authorization, isNull);
      return FakeResponse.error(401, 'INVALID_CREDENTIALS');
    });
    await expectLater(
      client.post('/api/v1/auth/login/password', {}),
      throwsA(isA<ApiException>()),
    );
    expectRequestCount(backend, 'POST', '/api/v1/auth/refresh', 0);
  });

  test('刷新时服务端 5xx：保留令牌，不当作会话失效', () async {
    var expired = 0;
    client.onSessionExpired = () => expired++;
    backend.on(
      'GET',
      '/api/v1/me',
      (_) => FakeResponse.error(401, ApiErrorCode.unauthorized),
    );
    backend.on(
      'POST',
      '/api/v1/auth/refresh',
      (_) => FakeResponse.error(503, 'SERVICE_UNAVAILABLE'),
    );
    await expectLater(client.get('/api/v1/me'), throwsA(isA<ApiException>()));
    expect(expired, 0);
    expect(client.hasTokens, isTrue);
  });

  test('刷新响应格式异常时不抛出未处理异常', () async {
    backend.on(
      'GET',
      '/api/v1/me',
      (_) => FakeResponse.error(401, ApiErrorCode.unauthorized),
    );
    backend.on(
      'POST',
      '/api/v1/auth/refresh',
      (_) => FakeResponse.ok({'nope': 1}),
    );
    await expectLater(client.get('/api/v1/me'), throwsA(isA<ApiException>()));
    expect(client.hasTokens, isTrue);
  });

  test('刷新期间退出登录：丢弃刷新结果，不会把令牌写回', () async {
    final gate = Completer<void>();
    backend.on(
      'GET',
      '/api/v1/me',
      (_) => FakeResponse.error(401, ApiErrorCode.unauthorized),
    );
    backend.on('POST', '/api/v1/auth/refresh', (_) async {
      await gate.future;
      return FakeResponse.ok(tokensJson(access: 'access-2'));
    });
    final pending = client
        .get('/api/v1/me')
        .then<Object?>((v) => v, onError: (Object e) => e);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await client.clearTokens();
    gate.complete();
    await pending;
    expect(client.hasTokens, isFalse);
    expect(await store.read(), isNull);
  });

  test('带旧令牌的 401：其他请求已刷新时直接重试，不再轮换', () async {
    backend.on('GET', '/api/v1/me', (req) {
      return req.authorization == 'Bearer access-2'
          ? FakeResponse.ok('me')
          : FakeResponse.error(401, ApiErrorCode.unauthorized);
    });
    // 模拟：请求发出后、401 返回前，令牌已被另一请求刷新
    backend.on('GET', '/slow', (req) async {
      await client.saveTokens(
        TokenPair.fromJson(
          tokensJson(access: 'access-2', refresh: 'refresh-2'),
        ),
      );
      return FakeResponse.error(401, ApiErrorCode.unauthorized);
    });
    backend.on('GET', '/slow-retry', (_) => FakeResponse.ok('ok'));
    await expectLater(
      client.get('/slow'),
      throwsA(isA<ApiException>()),
    ); // 重试仍 401（路由不变）
    expectRequestCount(backend, 'POST', '/api/v1/auth/refresh', 0);
    expect(backend.last('GET', '/slow').authorization, 'Bearer access-2');
  });
}
