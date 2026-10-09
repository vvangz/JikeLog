import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import 'attachment_service.dart';

/// 附件文件目录，测试中可覆盖为临时目录。
final attachmentDirProvider = Provider<Future<Directory> Function()>(
  (_) => getApplicationSupportDirectory,
);

final attachmentServiceProvider = Provider<AttachmentService>((ref) {
  final service = AttachmentService(
    api: ref.watch(syncApiProvider),
    db: ref.watch(appDatabaseProvider),
    store: ref.watch(recordStoreProvider),
    engine: ref.watch(syncEngineProvider),
    baseDir: ref.watch(attachmentDirProvider),
  );
  // 每次同步完成后重试待上传的附件（所属日志可能刚同步到服务端）
  ref.listen(syncStatusProvider, (_, next) {
    if (next.value?.phase == SyncPhase.idle) {
      unawaited(service.uploadPending());
    }
  });
  return service;
});

final attachmentsProvider = StreamProvider.family<List<AttachmentView>, String>(
  (ref, ownerId) => ref.watch(attachmentServiceProvider).watch(ownerId),
);
