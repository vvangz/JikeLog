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
    this.maxSize = defaultMaxSize,
    Dio? storageDio,
  }) : _dio = storageDio ?? Dio();

  /// 单个附件的大小上限（与服务端默认配置一致）。
  static const defaultMaxSize = 100 * 1024 * 1024;

  final SyncApi api;
  final AppDatabase db;
  final RecordStore store;
  final SyncEngine engine;

  /// 本地文件目录（待上传的副本与下载缓存）。
  final Future<Directory> Function() baseDir;
  final int maxSize;

  /// 访问对象存储的客户端：不经过 API，不带登录令牌。
  final Dio _dio;
  Future<void>? _uploading;

  static const _pending = 'pending';
  static const _uploaded = 'uploaded';
  static const _cached = 'cached';
  static const _failed = 'failed';

  Future<Directory> _dir() async =>
      Directory(p.join((await baseDir()).path, 'attachments'));

  Future<File> _fileFor(String id) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    return File(p.join(dir.path, id));
  }

  /// 删除本机全部附件文件（退出登录或切换账号时，与清空本地数据库一起调用）。
  Future<void> deleteLocalFiles() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 为记录添加附件：复制到应用目录后在后台上传。
  Future<String> add({
    required String ownerEntity,
    required String ownerId,
    required File source,
    required String fileName,
  }) async {
    if (await source.length() > maxSize) {
      throw ApiException(
        code: ApiErrorCode.attachmentTooLarge,
        message: '单个附件不能超过 ${maxSize ~/ (1024 * 1024)}MB',
      );
    }
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
      final error = await _tryUpload(f);
      if (error is _Retry) break; // 暂时性错误：停止本轮，下次同步后再试
      if (error is _Fail) {
        await _markFailed(f.id, error.message);
        continue;
      }
      uploaded = true;
    }
    if (uploaded) unawaited(engine.sync()); // 拉取服务端生成的附件记录
  }

  /// 上传一个附件，返回 null（成功）、[_Retry]（网络、服务端暂时不可用、链接过期）或 [_Fail]（需要用户处理）。
  /// 在后台调用，任何异常都不能抛出。
  Future<_UploadError?> _tryUpload(LocalFileRow f) async {
    try {
      await _upload(f);
      return null;
    } on ApiException catch (e) {
      final s = e.status;
      if (e.isNetwork || s == null || s >= 500 || s == 401 || s == 429) {
        debugPrint('附件上传暂时失败（稍后重试）: $e');
        return const _Retry();
      }
      return _Fail(e.message);
    } on DioException catch (e) {
      final s = e.response?.statusCode;
      // 没有响应（网络）、5xx、403（预签名链接过期，下次重新申请）：稍后重试
      if (s == null || s >= 500 || s == 403) {
        debugPrint('附件上传到存储服务失败（稍后重试）: $e');
        return const _Retry();
      }
      return _Fail('上传到存储服务失败（$s），请重试');
    } on FileSystemException catch (e) {
      debugPrint('附件本地文件不可读: $e');
      return const _Fail('本地文件已丢失，请重新添加');
    } on Object catch (e, st) {
      debugPrint('附件上传失败: $e\n$st');
      return const _Fail('上传失败，请重试');
    }
  }

  Future<void> _upload(LocalFileRow f) async {
    // 先确认本地文件可读，再向服务端申请上传（否则服务端会留下一条未完成的上传）
    final file = File(f.path);
    final length = await file.length(); // 文件不存在时抛出 FileSystemException
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
      data: file.openRead(),
      // 预签名 PUT 不接受分块传输，必须带 Content-Length
      options: Options(
        headers: {...ticket.headers, Headers.contentLengthHeader: '$length'},
      ),
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
    if (row != null) {
      final cached = File(row.path);
      if (await cached.exists() && await cached.length() == row.size) {
        return cached;
      }
    }
    final rec = await store.get(id);
    if (rec == null) throw StateError('附件不存在');
    final expected = rec.fields['sha256'];
    if (expected is! String) {
      throw const ApiException(
        code: ApiErrorCode.unexpected,
        message: '附件信息不完整，请稍后重试',
      );
    }
    final file = await _fileFor(id);
    // 先下载到临时文件，校验通过后再改名：下载中断或内容不符时不留下不完整的文件
    final part = File('${file.path}.part');
    try {
      await _dio.download(await api.downloadUrl(id), part.path);
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != expected) {
        throw const ApiException(
          code: ApiErrorCode.unexpected,
          message: '附件下载不完整，请重试',
        );
      }
      await part.rename(file.path);
    } finally {
      if (await part.exists()) await part.delete();
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

sealed class _UploadError {
  const _UploadError();
}

final class _Retry extends _UploadError {
  const _Retry();
}

final class _Fail extends _UploadError {
  const _Fail(this.message);

  final String message;
}
