/// 数据导出（ADR-010）：在服务端生成 zip，完成后下载并分享或保存。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';

/// 可以导出的模块（与接口中的 ExportModule 一致）。
enum ExportModule {
  worklog('工作日志'),
  note('笔记'),
  memo('备忘录'),
  ledger('记账');

  const ExportModule(this.label);
  final String label;

  static ExportModule? parse(Object? v) {
    for (final m in values) {
      if (m.name == v) return m;
    }
    return null;
  }
}

enum ExportStatus {
  pending('排队中'),
  running('正在生成'),
  done('已完成'),
  failed('失败'),
  expired('已过期');

  const ExportStatus(this.label);
  final String label;

  bool get active => this == pending || this == running;

  static ExportStatus parse(Object? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => ExportStatus.failed);
}

/// 一次导出。
@immutable
class ExportJob {
  const ExportJob({
    required this.id,
    required this.modules,
    required this.attachments,
    required this.status,
    required this.createdAt,
    this.size,
    this.error,
    this.finishedAt,
    this.expiresAt,
  });

  factory ExportJob.fromJson(Map<String, dynamic> j) => ExportJob(
    id: j['id'] as String,
    modules: [
      for (final m in (j['modules'] as List? ?? const []))
        ?ExportModule.parse(m),
    ],
    attachments: j['attachments'] as bool? ?? false,
    status: ExportStatus.parse(j['status']),
    size: (j['size'] as num?)?.toInt(),
    error: j['error'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    finishedAt: _time(j['finishedAt']),
    expiresAt: _time(j['expiresAt']),
  );

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.parse(v).toLocal() : null;

  final String id;
  final List<ExportModule> modules;
  final bool attachments;
  final ExportStatus status;
  final int? size;
  final String? error;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final DateTime? expiresAt;

  /// 可以下载：已完成且未到删除时刻。
  bool canDownload(DateTime now) =>
      status == ExportStatus.done &&
      (expiresAt == null || now.isBefore(expiresAt!));
}

class ExportApi {
  ExportApi(this._c);

  final ApiClient _c;

  Future<List<ExportJob>> list() async => [
    for (final j in (await _c.get('/api/v1/exports') as List))
      ExportJob.fromJson(j as Map<String, dynamic>),
  ];

  Future<ExportJob> create(
    Set<ExportModule> modules, {
    required bool attachments,
  }) async => ExportJob.fromJson(
    await _c.post('/api/v1/exports', {
      'modules': [
        for (final m in ExportModule.values)
          if (modules.contains(m)) m.name,
      ],
      'attachments': attachments,
    }) as Map<String, dynamic>,
  );

  Future<void> delete(String id) => _c.delete('/api/v1/exports/$id');

  /// 预签名下载地址（10 分钟内有效）。
  Future<String> downloadUrl(String id) async =>
      (await _c.get('/api/v1/exports/$id/download')
              as Map<String, dynamic>)['url']
          as String;
}

final exportApiProvider = Provider<ExportApi>(
  (ref) => ExportApi(ref.watch(apiClientProvider)),
);

/// 把下载好的导出文件交给用户：系统分享面板（可保存到文件、发给电脑等）。
abstract class ExportFiles {
  /// 下载 [url] 到本机临时目录并打开分享面板。
  Future<void> downloadAndShare(String url, String fileName);

  /// 删除本机留下的导出文件（退出登录时）。
  Future<void> clear();
}

class ShareExportFiles implements ExportFiles {
  ShareExportFiles({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              // 两次收到数据的最长间隔，不限制整个下载的时长
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  Future<Directory> _dir() async =>
      Directory('${(await getTemporaryDirectory()).path}/exports');

  @override
  Future<void> clear() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<void> downloadAndShare(String url, String fileName) async {
    // 导出内容是明文：正式版只从 HTTPS 地址下载
    if (kReleaseMode && Uri.parse(url).scheme != 'https') {
      throw StateError('下载地址不安全');
    }
    // 只保留最近一次下载的文件（分享面板需要在之后读取它，不能立即删除）；退出登录时清空
    await clear();
    final dir = await _dir();
    await dir.create(recursive: true);
    final file = File('${dir.path}/$fileName');
    await _dio.download(url, file.path);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        title: fileName,
      ),
    );
  }
}

final exportFilesProvider = Provider<ExportFiles>((_) => ShareExportFiles());

/// 最近的导出（新的在前）。
final exportsProvider = FutureProvider.autoDispose<List<ExportJob>>(
  (ref) => ref.watch(exportApiProvider).list(),
);

/// 导出文件名：即刻日志导出-20261011-0930.zip。
String exportFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '即刻日志导出-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}.zip';
}

/// 文件大小：1.2 MB。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}
