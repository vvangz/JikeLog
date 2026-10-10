import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/api/api_client.dart';
import 'package:jikelog/core/api/api_exception.dart';
import 'package:jikelog/core/config.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/core/sync/e2e.dart';
import 'package:jikelog/core/sync/realtime.dart';
import 'package:jikelog/core/sync/sync_api.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../support/fake_backend.dart';

Future<ApiClient> _client(FakeBackend b) async {
  final c = ApiClient(
    baseUrl: 'http://api.test',
    tokenStore: MemoryTokenStore(testTokens),
    adapter: b,
  );
  await c.restore();
  return c;
}

FakeResponse _session(String id) => FakeResponse.ok({
  'sessionId': id,
  'expiresAt': '2100-01-01T00:00:00Z',
}, status: 201);

/// 可控的 WebSocket：测试中向客户端发送消息、关闭连接。
class FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  FakeChannel({this.fail = false, this.gate});

  final bool fail;

  /// 不为空时握手等它完成（模拟握手较慢）。
  final Completer<void>? gate;
  final incoming = StreamController<dynamic>();
  final sent = <dynamic>[];
  int? _closeCode;

  @override
  Future<void> get ready =>
      fail ? Future.error(Exception('401')) : (gate?.future ?? Future.value());

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _Sink(this);

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  void serverClose(int code) {
    _closeCode = code;
    unawaited(incoming.close());
  }
}

class _Sink implements WebSocketSink {
  _Sink(this.ch);

  final FakeChannel ch;

  @override
  void add(dynamic data) => ch.sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!ch.incoming.isClosed) await ch.incoming.close();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> get done => Future.value();
}

void main() {
  group('SyncApi', () {
    test('握手上传临时公钥与内置公钥标识；会话复用', () async {
      final b = FakeBackend()
        ..on('POST', '/api/v1/sync/e2e/session', (_) => _session('s1'));
      final api = SyncApi(await _client(b));
      final s1 = await api.session();
      final s2 = await api.session();
      expect(identical(s1, s2), isTrue);
      expect(b.count('POST', '/api/v1/sync/e2e/session'), 1);
      final body = b.last('POST', '/api/v1/sync/e2e/session').body!;
      expect(base64.decode(body['clientPublicKey'] as String).length, 32);
      expect(
        body['serverKeyId'],
        E2ECrypto.keyId(base64.decode(AppConfig.e2ePublicKey)),
      );
      api.reset();
      await api.session();
      expect(b.count('POST', '/api/v1/sync/e2e/session'), 2);
    });

    test('会话失效时重新握手并只重试一次', () async {
      var sessions = 0;
      var pushes = 0;
      final b = FakeBackend()
        ..on(
          'POST',
          '/api/v1/sync/e2e/session',
          (_) => _session('s${++sessions}'),
        )
        ..on('POST', '/api/v1/sync/push', (req) {
          pushes++;
          return pushes == 1
              ? FakeResponse.error(409, ApiErrorCode.e2eSessionInvalid)
              : FakeResponse.ok({'results': <dynamic>[], 'cursor': 3});
        });
      final api = SyncApi(await _client(b));
      final res = await api.withSession((s) => api.push(s, const []));
      expect(res.cursor, 3);
      expect(sessions, 2);

      b.on(
        'POST',
        '/api/v1/sync/push',
        (_) => FakeResponse.error(409, ApiErrorCode.e2eSessionInvalid),
      );
      await expectLater(
        api.withSession((s) => api.push(s, const [])),
        throwsA(isA<ApiException>()),
      );
      expect(sessions, 3, reason: '只重新握手一次');
    });

    test('拉取、修订、用量解析', () async {
      final b = FakeBackend()
        ..on('POST', '/api/v1/sync/e2e/session', (_) => _session('s'))
        ..on(
          'GET',
          '/api/v1/sync/pull?since=0&limit=200',
          (_) => FakeResponse.ok({
            'records': <dynamic>[],
            'nextSince': 7,
            'hasMore': false,
          }),
        )
        ..on(
          'GET',
          '/api/v1/records/r1/revisions',
          (_) => FakeResponse.ok([
            {
              'id': 'v1',
              'version': 2,
              'reason': 'conflict',
              'createdAt': '2026-10-09T08:00:00Z',
              'deviceModel': 'Pixel 9',
            },
          ]),
        )
        ..on(
          'GET',
          '/api/v1/attachments/usage',
          (_) => FakeResponse.ok({'used': 1, 'quota': 2, 'maxSize': 3}),
        );
      final api = SyncApi(await _client(b));
      final page = await api.withSession((s) => api.pull(s, 0));
      expect(page.nextSince, 7);
      final revs = await api.revisions('r1');
      expect(revs.single.reason, 'conflict');
      expect(revs.single.deviceModel, 'Pixel 9');
      final u = await api.usage();
      expect((u.used, u.quota, u.maxSize), (1, 2, 3));
    });
  });

  group('RealtimeClient', () {
    test('WebSocket 地址与 API 同源', () {
      expect(
        RealtimeClient.wsUri('https://api.example.com').toString(),
        'wss://api.example.com/api/v1/sync/ws',
      );
      expect(
        RealtimeClient.wsUri('http://10.0.2.2:8080').toString(),
        'ws://10.0.2.2:8080/api/v1/sync/ws',
      );
    });

    test('收到 hello 与其他设备的通知时同步，忽略本设备的通知；断线重连；4401 停止', () {
      fakeAsync((async) {
        final channels = <FakeChannel>[];
        final headers = <Map<String, String>>[];
        var changes = 0;
        var revoked = 0;
        late ApiClient client;
        _client(FakeBackend()).then((c) => client = c);
        async.flushMicrotasks();
        final rt = RealtimeClient(
          client: client,
          onChange: () => changes++,
          onRevoked: () => revoked++,
          deviceId: () => 'me',
          connect: (uri, h) {
            headers.add(h);
            final ch = FakeChannel();
            channels.add(ch);
            return ch;
          },
        );
        rt.start();
        async.flushMicrotasks();
        expect(headers.single['Authorization'], 'Bearer access-1');

        channels.last.incoming.add(jsonEncode({'type': 'hello', 'seq': 1}));
        channels.last.incoming.add(
          jsonEncode({'type': 'changed', 'seq': 2, 'origin': 'me'}),
        );
        channels.last.incoming.add(
          jsonEncode({'type': 'changed', 'seq': 3, 'origin': 'other'}),
        );
        channels.last.incoming.add('not json');
        async.flushMicrotasks();
        expect(changes, 2);

        channels.last.serverClose(1006);
        async.elapse(const Duration(seconds: 2));
        expect(channels.length, 2, reason: '断线后重连');

        channels.last.serverClose(RealtimeClient.closeRevoked);
        async.elapse(const Duration(minutes: 2));
        expect(revoked, 1);
        expect(channels.length, 2, reason: '设备下线后不再重连');
        rt.stop();
      });
    });

    test('握手期间停止又启动：只保留最新的连接，旧连接关闭', () {
      fakeAsync((async) {
        late ApiClient client;
        _client(FakeBackend()).then((c) => client = c);
        async.flushMicrotasks();
        final channels = <FakeChannel>[];
        var changes = 0;
        final rt = RealtimeClient(
          client: client,
          onChange: () => changes++,
          connect: (uri, h) {
            final ch = FakeChannel(gate: Completer<void>());
            channels.add(ch);
            return ch;
          },
        );
        rt.start();
        async.flushMicrotasks();
        rt.stop();
        rt.start();
        async.flushMicrotasks();
        expect(channels, hasLength(2));
        channels[1].gate!.complete();
        channels[0].gate!.complete();
        async.flushMicrotasks();
        expect(channels[0].incoming.isClosed, isTrue, reason: '旧连接应关闭');
        channels[1].incoming.add(jsonEncode({'type': 'hello', 'seq': 1}));
        async.flushMicrotasks();
        expect(changes, 1);
        expect(rt.connected, isTrue);
        rt.stop();
        async.flushMicrotasks();
      });
    });

    test('握手失败时刷新令牌后重试', () {
      fakeAsync((async) {
        var refreshes = 0;
        final b = FakeBackend()
          ..on('POST', '/api/v1/auth/refresh', (_) {
            refreshes++;
            return FakeResponse.ok(tokensJson(access: 'access-2'));
          });
        late ApiClient client;
        _client(b).then((c) => client = c);
        async.flushMicrotasks();
        var attempt = 0;
        final tokens = <String?>[];
        final rt = RealtimeClient(
          client: client,
          onChange: () {},
          connect: (uri, h) {
            tokens.add(h['Authorization']);
            return FakeChannel(fail: attempt++ == 0);
          },
        );
        rt.start();
        async.elapse(const Duration(seconds: 3));
        expect(refreshes, 1);
        expect(tokens, ['Bearer access-1', 'Bearer access-2']);
        expect(rt.connected, isTrue);
        rt.stop();
        async.flushMicrotasks();
        expect(rt.connected, isFalse);
      });
    });
  });
}
