import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../config.dart';
import 'e2e.dart';
import 'sync_engine.dart';

/// 推送结果。
@immutable
class PushResult {
  const PushResult({
    required this.id,
    required this.status,
    this.version,
    this.serverSeq,
    this.record,
    this.errorCode,
  });

  factory PushResult.fromJson(Map<String, dynamic> j) => PushResult(
    id: j['id'] as String,
    status: j['status'] as String,
    version: (j['version'] as num?)?.toInt(),
    serverSeq: (j['serverSeq'] as num?)?.toInt(),
    record: j['record'] as Map<String, dynamic>?,
    errorCode: (j['error'] as Map<String, dynamic>?)?['code'] as String?,
  );

  final String id;

  /// applied / merged / conflict / rejected
  final String status;
  final int? version;
  final int? serverSeq;

  /// merged 或 conflict 时服务端的最终记录（敏感字段为密文）。
  final Map<String, dynamic>? record;
  final String? errorCode;
}

@immutable
class PullPage {
  const PullPage({
    required this.records,
    required this.nextSince,
    required this.hasMore,
  });

  final List<Map<String, dynamic>> records;
  final int nextSince;
  final bool hasMore;
}

@immutable
class RevisionInfo {
  const RevisionInfo({
    required this.id,
    required this.version,
    required this.reason,
    required this.createdAt,
    required this.deviceModel,
  });

  factory RevisionInfo.fromJson(Map<String, dynamic> j) => RevisionInfo(
    id: j['id'] as String,
    version: (j['version'] as num).toInt(),
    reason: j['reason'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    deviceModel: j['deviceModel'] as String? ?? '',
  );

  final String id;
  final int version;

  /// edit / conflict / delete
  final String reason;
  final DateTime createdAt;
  final String deviceModel;
}

/// 附件上传地址。
@immutable
class UploadTicket {
  const UploadTicket({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;
}

@immutable
class AttachmentUsage {
  const AttachmentUsage({
    required this.used,
    required this.quota,
    required this.maxSize,
  });

  final int used;
  final int quota;
  final int maxSize;
}

/// 同步与附件接口（/api/v1/sync/*、/api/v1/records、/api/v1/revisions、/api/v1/attachments）。
class SyncApi implements SyncTransport {
  SyncApi(this._c, {List<int>? serverPublicKey})
    : _serverPub = serverPublicKey ?? base64.decode(AppConfig.e2ePublicKey);

  final ApiClient _c;
  final List<int> _serverPub;
  E2ESession? _session;
  Future<E2ESession>? _handshaking;

  static const _header = 'X-JikeLog-E2E';

  /// 当前传输加密会话；没有或即将过期时重新握手（并发调用只握手一次）。
  Future<E2ESession> session() {
    final s = _session;
    if (s != null &&
        s.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return Future.value(s);
    }
    return _handshaking ??= _handshake().whenComplete(
      () => _handshaking = null,
    );
  }

  Future<E2ESession> _handshake() async {
    final kp = await E2ECrypto.newKeyPair();
    final pub = await kp.extractPublicKey();
    final data = await _c.post('/api/v1/sync/e2e/session', {
      'clientPublicKey': base64.encode(pub.bytes),
      'serverKeyId': E2ECrypto.keyId(_serverPub),
    }) as Map<String, dynamic>;
    final s = E2ESession(
      id: data['sessionId'] as String,
      key: await E2ECrypto.deriveSessionKey(kp, _serverPub),
      expiresAt: DateTime.parse(data['expiresAt'] as String),
    );
    _session = s;
    return s;
  }

  /// 使用加密会话调用接口；会话失效（如服务端重启后 Redis 被清空）时重新握手并重试一次。
  @override
  Future<T> withSession<T>(Future<T> Function(E2ESession s) call) async {
    try {
      return await call(await session());
    } on ApiException catch (e) {
      if (e.code != ApiErrorCode.e2eSessionInvalid) rethrow;
      _session = null;
      return call(await session());
    }
  }

  /// 退出登录时丢弃会话。
  void reset() => _session = null;

  @override
  Future<({List<PushResult> results, int cursor})> push(
    E2ESession s,
    List<Map<String, dynamic>> changes,
  ) async {
    final data = await _c.post(
      '/api/v1/sync/push',
      {'changes': changes},
      {_header: s.id},
    ) as Map<String, dynamic>;
    return (
      results: [
        for (final r in data['results'] as List<dynamic>)
          PushResult.fromJson(r as Map<String, dynamic>),
      ],
      cursor: (data['cursor'] as num).toInt(),
    );
  }

  @override
  Future<PullPage> pull(E2ESession s, int since, {int limit = 200}) async {
    final data = await _c.get(
      '/api/v1/sync/pull?since=$since&limit=$limit',
      headers: {_header: s.id},
    ) as Map<String, dynamic>;
    return PullPage(
      records: (data['records'] as List<dynamic>).cast<Map<String, dynamic>>(),
      nextSince: (data['nextSince'] as num).toInt(),
      hasMore: data['hasMore'] as bool,
    );
  }

  @override
  Future<void> ack(int seq) => _c.post('/api/v1/sync/ack', {'seq': seq});

  Future<List<RevisionInfo>> revisions(String recordId) async => [
    for (final r
        in await _c.get('/api/v1/records/$recordId/revisions') as List<dynamic>)
      RevisionInfo.fromJson(r as Map<String, dynamic>),
  ];

  /// 修订内容（敏感字段为密文）。
  Future<Map<String, dynamic>> revision(E2ESession s, String id) async =>
      await _c.get('/api/v1/revisions/$id', headers: {_header: s.id})
          as Map<String, dynamic>;

  Future<UploadTicket> requestUpload(
    E2ESession s, {
    required String id,
    required String ownerEntity,
    required String ownerId,
    required String fileName,
    required String mime,
    required int size,
    required String sha256,
  }) async {
    final data = await _c.post(
      '/api/v1/attachments',
      {
        'id': id,
        'ownerEntity': ownerEntity,
        'ownerId': ownerId,
        'fileName': await s.sealValue('attachment', id, 'fileName', fileName),
        'mime': mime,
        'size': size,
        'sha256': sha256,
      },
      {_header: s.id},
    ) as Map<String, dynamic>;
    return UploadTicket(
      url: data['uploadUrl'] as String,
      headers: (data['headers'] as Map<String, dynamic>).cast<String, String>(),
    );
  }

  Future<int> completeUpload(String id) async {
    final data = await _c.post(
      '/api/v1/attachments/$id/complete',
    ) as Map<String, dynamic>;
    return (data['serverSeq'] as num).toInt();
  }

  Future<String> downloadUrl(String id) async =>
      (await _c.get('/api/v1/attachments/$id/download')
              as Map<String, dynamic>)['url']
          as String;

  Future<AttachmentUsage> usage() async {
    final d = await _c.get('/api/v1/attachments/usage') as Map<String, dynamic>;
    return AttachmentUsage(
      used: (d['used'] as num).toInt(),
      quota: (d['quota'] as num).toInt(),
      maxSize: (d['maxSize'] as num).toInt(),
    );
  }
}
