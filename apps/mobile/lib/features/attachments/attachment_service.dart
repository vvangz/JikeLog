import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/api/api_exception.dart';
import '../../core/db/database.dart';
import '../../core/sync/record_store.dart';
import '../../core/sync/schema.dart';
import '../../core/sync/sync_api.dart';
import '../../core/sync/sync_engine.dart';

/// 附件状态。
enum AttachmentState { uploading, failed, ready }

/// 界面上展示的一个附件。
@immutable
class AttachmentView {
  const AttachmentView({
    required this.id,
    required this.fileName,
    required this.mime,
    required this.size,
    required this.state,
    this.error,
  });

  final String id;
  final String fileName;
  final String mime;
  final int size;
  final AttachmentState state;
  final String? error;

  bool get isImage => mime.startsWith('image/');
}

/// 附件：直传对象存储，上传完成后由服务端生成 attachment 同步记录（ADR-005、ADR-006）。
class AttachmentService {
  AttachmentService({
    required this.api,
    required this.db,
    required this.store,
    required this.engine,
    required this.baseDir,
    Dio? storageDio,
  }) : _dio = storageDio ?? Dio();

  final SyncApi api;
  final AppDatabase db;
  final RecordStore store;
  final SyncEngine engine;

  /// 本地文件目录（待上传的副本与下载缓存）。
  final Future<Directory> Function() baseDir;

  /// 访问对象存储的客户端：不经过 API，不带登录令牌。
  final Dio _dio;
  Future<void>? _uploading;

  static const _pending = 'pending';
  static const _uploaded = 'uploaded';
  static const _cached = 'cached';
  static const _failed = 'failed';

  Future<File> _fileFor(String id) async {
    final dir = Directory(p.join((await baseDir()).path, 'attachments'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, id));
  }

  /// 为记录添加附件：复制到应用目录后在后台上传。
  Future<String> add({
    required String ownerEntity,
    required String ownerId,
    required File source,
    required String fileName,
  }) async {
    final id = const Uuid().v7();
    final local = await source.copy((await _fileFor(id)).path);
    final digest = await sha256.bind(local.openRead()).first;
    await db
        .into(db.localFiles)
        .insert(
          LocalFilesCompanion.insert(
            id: id,
            path: local.path,
            state: _pending,
            ownerEntity: ownerEntity,
            ownerId: ownerId,
            fileName: fileName,
            mime: mimeOf(fileName),
            size: await local.length(),
            sha256: digest.toString(),
          ),
        );
    unawaited(uploadPending());
    return id;
  }

  /// 上传所有待上传的附件（并发调用只执行一次）。所属记录尚未同步到服务端时跳过，下次再试。
  Future<void> uploadPending() =>
      _uploading ??= _uploadAll().whenComplete(() => _uploading = null);

  Future<void> _uploadAll() async {
    final rows = await (db.select(
      db.localFiles,
    )..where((t) => t.state.equals(_pending))).get();
    var uploaded = false;
    for (final f in rows) {
      final owner = await store.get(f.ownerId);
      if (owner == null || owner.version == 0) continue; // 等所属日志先同步
      try {
        await _upload(f);
        uploaded = true;
      } on ApiException catch (e) {
        if (e.isNetwork) return; // 离线：稍后重试
        await _markFailed(f.id, e.message);
      } on DioException catch (e) {
        debugPrint('附件上传失败（稍后重试）: $e');
        return;
      }
    }
    if (uploaded) unawaited(engine.sync()); // 拉取服务端生成的附件记录
  }

  Future<void> _upload(LocalFileRow f) async {
    final ticket = await api.withSession(
      (s) => api.requestUpload(
        s,
        id: f.id,
        ownerEntity: f.ownerEntity,
        ownerId: f.ownerId,
        fileName: f.fileName,
        mime: f.mime,
        size: f.size,
        sha256: f.sha256,
      ),
    );
    await _dio.put<void>(
      ticket.url,
      data: File(f.path).openRead(),
      options: Options(headers: ticket.headers),
    );
    await api.completeUpload(f.id);
    await (db.update(db.localFiles)..where((t) => t.id.equals(f.id))).write(
      const LocalFilesCompanion(state: Value(_uploaded)),
    );
  }

  Future<void> _markFailed(String id, String message) =>
      (db.update(db.localFiles)..where((t) => t.id.equals(id))).write(
        LocalFilesCompanion(state: const Value(_failed), error: Value(message)),
      );

  /// 重新尝试上传失败的附件。
  Future<void> retry(String id) async {
    await (db.update(db.localFiles)..where((t) => t.id.equals(id))).write(
      const LocalFilesCompanion(state: Value(_pending), error: Value(null)),
    );
    await uploadPending();
  }

  /// 记录的全部附件：已同步的附件记录，加上本机尚未上传完成的文件。
  Stream<List<AttachmentView>> watch(String ownerId) {
    final records =
        (db.select(db.records)..where(
              (t) =>
                  t.entity.equals(Entities.attachment) &
                  t.ownerId.equals(ownerId) &
                  t.deleted.not(),
            ))
            .watch();
    final files = (db.select(
      db.localFiles,
    )..where((t) => t.ownerId.equals(ownerId))).watch();
    return _combine(records, files, (rs, fs) {
      final views = <String, AttachmentView>{};
      for (final f in fs) {
        if (f.state == _pending || f.state == _failed) {
          views[f.id] = AttachmentView(
            id: f.id,
            fileName: f.fileName,
            mime: f.mime,
            size: f.size,
            state: f.state == _failed
                ? AttachmentState.failed
                : AttachmentState.uploading,
            error: f.error,
          );
        }
      }
      for (final r in rs) {
        final fields = LocalRecord.fromRow(r).fields;
        views[r.id] = AttachmentView(
          id: r.id,
          fileName: fields['fileName'] as String? ?? '',
          mime: fields['mime'] as String? ?? 'application/octet-stream',
          size: (fields['size'] as num?)?.toInt() ?? 0,
          state: AttachmentState.ready,
        );
      }
      return views.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id)); // UUIDv7 即添加顺序
    });
  }

  /// 返回附件在本机的文件，没有时下载并校验内容。
  Future<File> open(String id) async {
    final row = await (db.select(
      db.localFiles,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row != null && await File(row.path).exists()) return File(row.path);
    final rec = await store.get(id);
    if (rec == null) throw StateError('附件不存在');
    final file = await _fileFor(id);
    final url = await api.downloadUrl(id);
    await _dio.download(url, file.path);
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != rec.fields['sha256']) {
      await file.delete();
      throw const ApiException(
        code: ApiErrorCode.unexpected,
        message: '附件下载不完整，请重试',
      );
    }
    await db
        .into(db.localFiles)
        .insertOnConflictUpdate(
          LocalFilesCompanion.insert(
            id: id,
            path: file.path,
            state: _cached,
            ownerEntity: rec.fields['ownerEntity'] as String? ?? '',
            ownerId: rec.fields['ownerId'] as String? ?? '',
            fileName: rec.fields['fileName'] as String? ?? '',
            mime: rec.fields['mime'] as String? ?? '',
            size: (rec.fields['size'] as num?)?.toInt() ?? 0,
            sha256: rec.fields['sha256'] as String? ?? '',
          ),
        );
    return file;
  }

  /// 删除附件：未上传完成的直接删除；已同步的留下墓碑，由同步引擎推送，服务端随后清理文件。
  Future<void> remove(String id) async {
    final row = await (db.select(
      db.localFiles,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row != null) {
      await (db.delete(db.localFiles)..where((t) => t.id.equals(id))).go();
      final f = File(row.path);
      if (await f.exists()) await f.delete();
    }
    if (await store.get(id) != null) {
      await store.remove(id);
      engine.schedule();
    }
  }

  /// 删除某条记录的全部附件（记录被删除时调用）。
  Future<void> removeAll(String ownerId) async {
    final ids = <String>{
      for (final r in await (db.select(
        db.records,
      )..where((t) => t.ownerId.equals(ownerId))).get())
        r.id,
      for (final f in await (db.select(
        db.localFiles,
      )..where((t) => t.ownerId.equals(ownerId))).get())
        f.id,
    };
    for (final id in ids) {
      await remove(id);
    }
  }

  static Stream<R> _combine<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) combine,
  ) {
    late StreamController<R> out;
    StreamSubscription<A>? sa;
    StreamSubscription<B>? sb;
    A? la;
    B? lb;
    var hasA = false;
    var hasB = false;
    void emit() {
      if (hasA && hasB) out.add(combine(la as A, lb as B));
    }

    out = StreamController<R>(
      onListen: () {
        sa = a.listen((v) {
          la = v;
          hasA = true;
          emit();
        }, onError: out.addError);
        sb = b.listen((v) {
          lb = v;
          hasB = true;
          emit();
        }, onError: out.addError);
      },
      onCancel: () async {
        await sa?.cancel();
        await sb?.cancel();
      },
    );
    return out.stream;
  }
}

/// 由文件扩展名推断类型（服务端只接受规范的 type/subtype）。
String mimeOf(String fileName) {
  final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  return const {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'heic': 'image/heic',
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'md': 'text/markdown',
        'csv': 'text/csv',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'zip': 'application/zip',
        'mp3': 'audio/mpeg',
        'm4a': 'audio/mp4',
        'wav': 'audio/wav',
        'mp4': 'video/mp4',
      }[ext] ??
      'application/octet-stream';
}
