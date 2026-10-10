import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/api/api_client.dart';
import 'package:jikelog/core/api/api_exception.dart';
import 'package:jikelog/core/db/database.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/core/sync/hlc.dart';
import 'package:jikelog/core/sync/record_store.dart';
import 'package:jikelog/core/sync/sync_api.dart';
import 'package:jikelog/core/sync/sync_engine.dart';
import 'package:jikelog/features/attachments/attachment_service.dart';

import '../support/fake_backend.dart';
import '../support/fake_sync_server.dart';

/// 模拟对象存储：记录上传的内容，下载时返回。
class FakeStorage implements HttpClientAdapter {
  final objects = <String, List<int>>{};
  final putHeaders = <String, Map<String, dynamic>>{};
  bool corrupt = false;

  /// 不为空时上传返回该状态码（模拟预签名链接过期等）。
  int? putStatus;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = options.uri.path;
    if (options.method == 'PUT') {
      if (putStatus != null) return ResponseBody.fromString('', putStatus!);
      final bytes = <int>[];
      await requestStream?.forEach(bytes.addAll);
      objects[key] = bytes;
      putHeaders[key] = options.headers;
      return ResponseBody.fromString('', 200);
    }
    final data = objects[key];
    if (data == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromBytes(
      corrupt ? [...data, 0] : data,
      200,
      headers: {
        Headers.contentLengthHeader: ['${data.length + (corrupt ? 1 : 0)}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late RecordStore store;
  late SyncEngine engine;
  late FakeSyncServer server;
  late FakeBackend backend;
  late FakeStorage storage;
  late AttachmentService service;
  const owner = '0192a000-0000-7000-8000-0000000000aa';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('jk-att');
    db = testDatabase();
    store = RecordStore(db, HybridClock(installationId: 'att-test'));
    server = FakeSyncServer();
    engine = SyncEngine(
      transport: FakeTransport(server),
      store: store,
      db: db,
      debounce: Duration.zero,
    );
    storage = FakeStorage();
    backend = FakeBackend()
      ..on(
        'POST',
        '/api/v1/sync/e2e/session',
        (_) => FakeResponse.ok({
          'sessionId': 's1',
          'expiresAt': '2100-01-01T00:00:00Z',
        }, status: 201),
      )
      ..on('POST', '/api/v1/attachments', (req) {
        final id = req.body!['id'] as String;
        return FakeResponse.ok({
          'uploadUrl': 'http://oss/u/$id',
          'method': 'PUT',
          'headers': {
            'Content-Type': req.body!['mime'],
            'Content-Length': '${req.body!['size']}',
          },
          'expiresAt': '2100-01-01T00:00:00Z',
        }, status: 201);
      });
    final client = ApiClient(
      baseUrl: 'http://t',
      tokenStore: MemoryTokenStore(testTokens),
      adapter: backend,
    );
    await client.restore();
    service = AttachmentService(
      api: SyncApi(client),
      db: db,
      store: store,
      engine: engine,
      baseDir: () async => tmp,
      storageDio: Dio()..httpClientAdapter = storage,
    );
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<File> source(String content) async {
    final f = File('${tmp.path}/src-${content.length}.txt');
    await f.writeAsString(content);
    return f;
  }

  test('所属日志同步之前不上传；同步后直传并确认完成', () async {
    final src = await source('会议纪要');
    await store.write('worklog', owner, {'date': '2026-10-09'});
    final id = await service.add(
      ownerEntity: 'worklog',
      ownerId: owner,
      source: src,
      fileName: '纪要.txt',
    );
    await service.uploadPending();
    expect(backend.count('POST', '/api/v1/attachments'), 0);
    var views = await service.watch(owner).first;
    expect(views.single.state, AttachmentState.uploading);
    expect(views.single.mime, 'text/plain');

    await engine.sync();
    backend.on('POST', '/api/v1/attachments/$id/complete', (_) {
      server.records[id] = ServerRecord('attachment', id)
        ..fields = {
          'ownerEntity': 'worklog',
          'ownerId': owner,
          'fileName': '纪要.txt',
          'mime': 'text/plain',
          'size': utf8.encode('会议纪要').length,
          'sha256': backend.last('POST', '/api/v1/attachments').body!['sha256'],
        }
        ..clocks = {'fileName': '1791553544000-0000-0000000000000000'}
        ..version = 1
        ..serverSeq = ++server.seq;
      return FakeResponse.ok({'serverSeq': server.seq});
    });
    await service.uploadPending();
    await engine.sync();

    final sent = backend.last('POST', '/api/v1/attachments').body!;
    expect(sent['ownerId'], owner);
    expect(sent['fileName'], isNot('纪要.txt'), reason: '文件名必须加密传输');
    expect(utf8.decode(storage.objects['/u/$id']!), '会议纪要');
    expect(storage.putHeaders['/u/$id']!['Content-Type'], 'text/plain');

    views = await service.watch(owner).first;
    expect(views.single.state, AttachmentState.ready);
    expect(views.single.fileName, '纪要.txt');

    backend.on(
      'GET',
      '/api/v1/attachments/$id/download',
      (_) => FakeResponse.ok({
        'url': 'http://oss/u/$id',
        'expiresAt': '2100-01-01T00:00:00Z',
      }),
    );
    // 本机已有文件时直接打开，不下载
    expect(await (await service.open(id)).readAsString(), '会议纪要');

    // 本机没有文件时下载并校验
    await (db.delete(db.localFiles)).go();
    expect(await (await service.open(id)).readAsString(), '会议纪要');
    await (db.delete(db.localFiles)).go();
    storage.corrupt = true;
    await expectLater(service.open(id), throwsA(anything));
  });

  test('超出配额标记为失败，可重试；删除未上传的附件', () async {
    backend.on(
      'POST',
      '/api/v1/attachments',
      (_) => FakeResponse.error(413, 'QUOTA_EXCEEDED', message: '附件空间已用完'),
    );
    await store.write('worklog', owner, {'date': '2026-10-09'});
    await engine.sync();
    final id = await service.add(
      ownerEntity: 'worklog',
      ownerId: owner,
      source: await source('x'),
      fileName: 'a.bin',
    );
    await service.uploadPending();
    var v = (await service.watch(owner).first).single;
    expect(v.state, AttachmentState.failed);
    expect(v.error, '附件空间已用完');

    await service.retry(id);
    v = (await service.watch(owner).first).single;
    expect(v.state, AttachmentState.failed);

    await service.remove(id);
    expect(await service.watch(owner).first, isEmpty);
  });

  test('删除日志时删除其全部附件', () async {
    await store.write('worklog', owner, {'date': '2026-10-09'});
    await service.add(
      ownerEntity: 'worklog',
      ownerId: owner,
      source: await source('y'),
      fileName: 'b.txt',
    );
    await store.applyRemote(
      const RemoteRecord(
        entity: 'attachment',
        id: '0192a000-0000-7000-8000-0000000000bb',
        version: 1,
        serverSeq: 9,
        deleted: false,
        fields: {'ownerId': owner, 'fileName': 'c.txt'},
        clocks: {'fileName': '1791553544000-0000-0000000000000000'},
      ),
    );
    expect((await service.watch(owner).first).length, 2);
    await service.removeAll(owner);
    expect(await service.watch(owner).first, isEmpty);
    final tomb = await store.get('0192a000-0000-7000-8000-0000000000bb');
    expect(tomb!.deleted, isTrue);
  });

  test('服务端暂时不可用、存储链接过期时保持待上传；本地文件丢失时标记失败', () async {
    await store.write('worklog', owner, {'date': '2026-10-09'});
    await engine.sync();
    backend.on(
      'POST',
      '/api/v1/attachments',
      (_) => FakeResponse.error(503, 'UNAVAILABLE', message: '服务暂时不可用'),
    );
    final id = await service.add(
      ownerEntity: 'worklog',
      ownerId: owner,
      source: await source('内容'),
      fileName: 'a.txt',
    );
    await service.uploadPending();
    expect(
      (await service.watch(owner).first).single.state,
      AttachmentState.uploading,
    );

    backend.on('POST', '/api/v1/attachments', (req) {
      return FakeResponse.ok({
        'uploadUrl': 'http://oss/u/$id',
        'method': 'PUT',
        'headers': {'Content-Type': 'text/plain'},
        'expiresAt': '2100-01-01T00:00:00Z',
      }, status: 201);
    });
    storage.putStatus = 403;
    await service.uploadPending();
    expect(
      (await service.watch(owner).first).single.state,
      AttachmentState.uploading,
    );

    storage.putStatus = null;
    await File('${tmp.path}/attachments/$id').delete();
    await service.uploadPending();
    final v = (await service.watch(owner).first).single;
    expect(v.state, AttachmentState.failed);
    expect(v.error, '本地文件已丢失，请重新添加');
  });

  test('上传时带 Content-Length（预签名 PUT 不接受分块传输）', () async {
    await store.write('worklog', owner, {'date': '2026-10-09'});
    await engine.sync();
    backend.on('POST', '/api/v1/attachments', (req) {
      final id = req.body!['id'] as String;
      return FakeResponse.ok({
        'uploadUrl': 'http://oss/u/$id',
        'method': 'PUT',
        'headers': {'Content-Type': 'text/plain'},
        'expiresAt': '2100-01-01T00:00:00Z',
      }, status: 201);
    });
    final id = await service.add(
      ownerEntity: 'worklog',
      ownerId: owner,
      source: await source('12345'),
      fileName: 'a.txt',
    );
    await service.uploadPending();
    expect(storage.putHeaders['/u/$id']![Headers.contentLengthHeader], '5');
  });

  test('超过大小上限的文件不复制、直接报错', () async {
    final small = AttachmentService(
      api: service.api,
      db: db,
      store: store,
      engine: engine,
      baseDir: () async => tmp,
      maxSize: 3,
    );
    await expectLater(
      small.add(
        ownerEntity: 'worklog',
        ownerId: owner,
        source: await source('超过三个字节'),
        fileName: 'big.txt',
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.attachmentTooLarge,
        ),
      ),
    );
    expect(await db.select(db.localFiles).get(), isEmpty);
    expect(Directory('${tmp.path}/attachments').existsSync(), isFalse);
  });

  test('下载失败不留下不完整的文件；清除本机附件文件', () async {
    const id = '0192a000-0000-7000-8000-0000000000cc';
    await store.applyRemote(
      const RemoteRecord(
        entity: 'attachment',
        id: id,
        version: 1,
        serverSeq: 9,
        deleted: false,
        fields: {'ownerId': owner, 'fileName': 'c.txt', 'sha256': 'x'},
        clocks: {'fileName': '1791553544000-0000-0000000000000000'},
      ),
    );
    backend.on(
      'GET',
      '/api/v1/attachments/$id/download',
      (_) => FakeResponse.ok({
        'url': 'http://oss/u/missing',
        'expiresAt': '2100-01-01T00:00:00Z',
      }),
    );
    await expectLater(service.open(id), throwsA(anything));
    final dir = Directory('${tmp.path}/attachments');
    expect(
      dir.existsSync() ? dir.listSync() : const <FileSystemEntity>[],
      isEmpty,
    );

    await service.add(
      ownerEntity: 'worklog',
      ownerId: owner,
      source: await source('z'),
      fileName: 'z.txt',
    );
    expect(dir.listSync(), isNotEmpty);
    await service.deleteLocalFiles();
    expect(dir.existsSync(), isFalse);
  });

  test('由扩展名推断类型', () {
    expect(mimeOf('照片.JPG'), 'image/jpeg');
    expect(mimeOf('报告.pdf'), 'application/pdf');
    expect(mimeOf('无扩展名'), 'application/octet-stream');
  });
}
