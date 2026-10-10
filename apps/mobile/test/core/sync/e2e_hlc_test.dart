import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/sync/e2e.dart';
import 'package:jikelog/core/sync/hlc.dart';

void main() {
  group('传输加密（与 Go 共用测试向量）', () {
    final v = jsonDecode(
      File('../../testdata/crypto/e2e.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final serverPub = base64.decode(v['serverPublicKey'] as String);

    test('派生的会话密钥、公钥标识与服务端一致，并能解开服务端的密文', () async {
      final client = await E2ECrypto.keyPairFromSeed(
        base64.decode(v['clientPrivateKey'] as String),
      );
      final pub = await client.extractPublicKey();
      expect(base64.encode(pub.bytes), v['clientPublicKey']);
      expect(E2ECrypto.keyId(serverPub), v['serverKeyId']);
      final key = await E2ECrypto.deriveSessionKey(client, serverPub);
      expect(base64.encode(await key.extractBytes()), v['sessionKey']);
      final plain = await E2ECrypto.open(
        key,
        v['aad'] as String,
        v['sealed'] as String,
      );
      expect(plain, v['plaintext']);
    });

    test('加解密往返；AAD 不符或被篡改时失败', () async {
      final key = SecretKey(List.filled(32, 7));
      final session = E2ESession(id: 's', key: key, expiresAt: DateTime.now());
      final sealed = await session.sealValue(
        'worklog',
        'id1',
        'content',
        '内容 ✅',
      );
      expect(
        await session.openValue('worklog', 'id1', 'content', sealed),
        '内容 ✅',
      );
      expect(
        () => session.openValue('worklog', 'id2', 'content', sealed),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final tampered = base64.decode(sealed)..last ^= 1;
      expect(
        () => session.openValue(
          'worklog',
          'id1',
          'content',
          base64.encode(tampered),
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      expect(
        () => E2ECrypto.open(key, 'a', base64.encode([1, 2, 3])),
        throwsFormatException,
      );
      final patch = await session.sealPatch('worklog', 'id1', 'content', '[]');
      expect(
        await E2ECrypto.open(
          key,
          E2ECrypto.aad('worklog', 'id1', 'content', 'p'),
          patch,
        ),
        '[]',
      );
    });
  });

  group('HybridClock', () {
    test('格式与服务端一致且严格递增', () {
      var now = 1791553544038;
      final c = HybridClock(installationId: 'install-1', nowMs: () => now);
      final a = c.now();
      final b = c.now(); // 同一毫秒内计数递增
      now += 1;
      final d = c.now();
      expect(HybridClock.isValid(a), isTrue);
      expect(a.compareTo(b) < 0 && b.compareTo(d) < 0, isTrue);
      expect(a, '1791553544038-0000-${c.node}');
      expect(b, '1791553544038-0001-${c.node}');
      expect(c.node.length, 16);
    });

    test('本机时间回拨时仍单调', () {
      var now = 2000;
      final c = HybridClock(installationId: 'x', nowMs: () => now);
      final a = c.now();
      now = 1000;
      expect(c.now().compareTo(a) > 0, isTrue);
    });

    test('收到更晚的远端时钟后，新时钟排在其后；过于超前的忽略', () {
      const now = 1000000;
      final c = HybridClock(installationId: 'x', nowMs: () => now);
      final remote = HybridClock.format(now + 60 * 1000, 5, 'aaaaaaaaaaaaaaaa');
      c.receive(remote);
      expect(c.now().compareTo(remote) > 0, isTrue);
      final far = HybridClock.format(
        now + 10 * 60 * 1000,
        0,
        'aaaaaaaaaaaaaaaa',
      );
      c.receive(far);
      expect(c.now().compareTo(far) < 0, isTrue);
      c.receive('garbage'); // 非法格式忽略
    });

    test('从持久化的时钟恢复后保持单调', () {
      final c1 = HybridClock(installationId: 'x', nowMs: () => 5000);
      c1.now();
      final saved = c1.now();
      final c2 = HybridClock(
        installationId: 'x',
        nowMs: () => 100,
        last: c1.last,
      );
      expect(c2.now().compareTo(saved) > 0, isTrue);
    });
  });
}
