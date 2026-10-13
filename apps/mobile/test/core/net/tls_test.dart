import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/net/isrg_roots.dart';
import 'package:jikelog/core/net/tls.dart';
import 'package:jikelog/core/sync/realtime.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 测试用证书：fixtures/tls 下的测试 CA 签发了 localhost 与 127.0.0.1 的证书（CA 私钥已删除）。
String _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsStringSync();

Future<HttpServer> _secureServer() async {
  final ctx = SecurityContext()
    ..useCertificateChainBytes(_fixture('server.pem').codeUnits)
    ..usePrivateKeyBytes(_fixture('server.key').codeUnits);
  final server = await HttpServer.bindSecure('127.0.0.1', 0, ctx);
  server.listen((req) async {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.add('hello');
      await ws.close();
      return;
    }
    req.response.write('ok');
    await req.response.close();
  });
  return server;
}

/// 本机连接不走开发机上的 HTTP(S)_PROXY 代理。
class _Direct extends HttpOverrides {
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      'DIRECT';
}

void main() {
  setUpAll(() => HttpOverrides.global = _Direct());
  tearDownAll(() => HttpOverrides.global = null);

  group('TlsPolicy.forBuild', () {
    const https = 'https://www.pingvv.top';

    test('正式版 + HTTPS 地址时锁定 CA', () {
      expect(TlsPolicy.forBuild(release: true, baseUrl: https).pinned, isTrue);
    });

    test('调试构建、HTTP 地址或显式关闭时使用系统信任库', () {
      expect(
        TlsPolicy.forBuild(release: false, baseUrl: https).pinned,
        isFalse,
      );
      expect(
        TlsPolicy.forBuild(
          release: true,
          baseUrl: 'http://10.0.2.2:8080',
        ).pinned,
        isFalse,
      );
      expect(
        TlsPolicy.forBuild(
          release: true,
          baseUrl: https,
          pinning: false,
        ).pinned,
        isFalse,
      );
    });

    test('内置的两个 Let\'s Encrypt 根证书可以解析，指纹与官方一致', () {
      expect(TlsPolicy.pinnedTo(isrgRootPems).pinned, isTrue);
      String fingerprint(String pem) {
        final body = pem
            .split('\n')
            .where((l) => l.isNotEmpty && !l.startsWith('-----'))
            .join();
        return sha256.convert(base64.decode(body)).toString();
      }

      expect(isrgRootPems.map(fingerprint), [
        '96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6',
        '69729b8e15a86efc177a57afb7171dfc64add28c2fca8cf1507e34453ccb1470',
      ]);
    });
  });

  group('锁定后的连接', () {
    late HttpServer server;
    late Uri url;

    setUp(() async {
      server = await _secureServer();
      url = Uri.parse('https://127.0.0.1:${server.port}/');
    });
    tearDown(() => server.close(force: true));

    test('信任的根证书签发的服务器证书可以连接', () async {
      final tls = TlsPolicy.pinnedTo([_fixture('ca.pem')]);
      final res = await tls.dio().getUri<String>(url);
      expect(res.data, 'ok');
    });

    test('只信任 Let\'s Encrypt 时拒绝其他 CA 签发的证书（HTTP）', () async {
      final tls = TlsPolicy.pinnedTo(isrgRootPems);
      await expectLater(
        tls.dio().getUri<String>(url),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<HandshakeException>(),
          ),
        ),
      );
    });

    test('WebSocket 同样受锁定约束', () async {
      final wsUrl = url.replace(scheme: 'wss');

      final ok = RealtimeClient.ioConnect(
        TlsPolicy.pinnedTo([_fixture('ca.pem')]),
      )(wsUrl, const {});
      addTearDown(ok.sink.close);
      await ok.ready;
      expect(await ok.stream.first, 'hello');

      final pinned = RealtimeClient.ioConnect(TlsPolicy.pinnedTo(isrgRootPems))(
        wsUrl,
        const {},
      );
      // 握手失败时 stream 也会报错：订阅并忽略，避免未处理的异步错误
      pinned.stream.listen(null, onError: (_) {});
      await expectLater(
        pinned.ready,
        throwsA(
          isA<WebSocketChannelException>().having(
            (e) => e.inner,
            'inner',
            isA<HandshakeException>(),
          ),
        ),
      );
    });
  });
}
