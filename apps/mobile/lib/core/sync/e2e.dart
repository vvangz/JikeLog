import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// 工作日志应用层传输加密（ADR-006）：X25519 临时密钥 + HKDF-SHA256 + AES-256-GCM。
///
/// 与服务端 `internal/platform/crypto`、`internal/e2e` 一致，两端共用 `testdata/crypto/e2e.json` 测试向量。
abstract final class E2ECrypto {
  static const info = 'jikelog-e2e-v1';
  static const _nonceLength = 12;
  static const _macLength = 16;

  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// 服务端公钥标识：SHA-256 前 8 字节的十六进制。
  static String keyId(List<int> serverPublicKey) => hash.sha256
      .convert(serverPublicKey)
      .bytes
      .take(8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) =>
      _x25519.newKeyPairFromSeed(seed);

  /// 派生会话密钥：HKDF-SHA256(X25519(客户端私钥, 服务端公钥), salt = 客户端公钥 ‖ 服务端公钥)。
  static Future<SecretKey> deriveSessionKey(
    SimpleKeyPair client,
    List<int> serverPublicKey,
  ) async {
    final clientPub = await client.extractPublicKey();
    final shared = await _x25519.sharedSecretKey(
      keyPair: client,
      remotePublicKey: SimplePublicKey(
        serverPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: [...clientPub.bytes, ...serverPublicKey],
      info: utf8.encode(info),
    );
  }

  /// 加密，输出 base64(nonce ‖ 密文 ‖ 标签)。
  static Future<String> seal(SecretKey key, String aad, String plain) async {
    final box = await _aes.encrypt(
      utf8.encode(plain),
      secretKey: key,
      nonce: _aes.newNonce(),
      aad: utf8.encode(aad),
    );
    return base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// 解密 [seal] 的输出；密文被篡改或 AAD 不符时抛出 [SecretBoxAuthenticationError]。
  static Future<String> open(SecretKey key, String aad, String sealed) async {
    final raw = base64.decode(sealed);
    if (raw.length < _nonceLength + _macLength) {
      throw const FormatException('密文过短');
    }
    final box = SecretBox(
      Uint8List.sublistView(raw, _nonceLength, raw.length - _macLength),
      nonce: Uint8List.sublistView(raw, 0, _nonceLength),
      mac: Mac(Uint8List.sublistView(raw, raw.length - _macLength)),
    );
    final plain = await _aes.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode(aad),
    );
    return utf8.decode(plain);
  }

  /// 字段密文的附加数据，与服务端 `e2e.AAD` 相同。[kind] 为 `v`（值）或 `p`（补丁）。
  static String aad(String entity, String id, String field, String kind) =>
      '$info|$entity|$id|$field|$kind';
}

/// 已建立的传输加密会话。
class E2ESession {
  const E2ESession({
    required this.id,
    required this.key,
    required this.expiresAt,
  });

  final String id;
  final SecretKey key;
  final DateTime expiresAt;

  Future<String> sealValue(String entity, String id, String field, String v) =>
      E2ECrypto.seal(key, E2ECrypto.aad(entity, id, field, 'v'), v);

  Future<String> sealPatch(String entity, String id, String field, String p) =>
      E2ECrypto.seal(key, E2ECrypto.aad(entity, id, field, 'p'), p);

  Future<String> openValue(String entity, String id, String field, String v) =>
      E2ECrypto.open(key, E2ECrypto.aad(entity, id, field, 'v'), v);
}
