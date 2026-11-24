import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/models.dart';

/// 头像最大字节数（与服务端 2 MiB 限制对齐）。
const maxAvatarBytes = 2 * 1024 * 1024;

/// 归一化输出的目标边长（居中裁切为正方形，兼顾高清屏清晰度与体积）。
const _targetAvatarSize = 512;

/// 归一化后的头像字节与 MIME 类型。
@immutable
class PreparedAvatar {
  const PreparedAvatar(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// 选择一张本地图片并返回其原始字节（测试中可通过 [avatarPickerProvider] 替换）。
typedef AvatarPicker = Future<Uint8List?> Function();

/// 把原始图片字节归一化为适合上传的头像字节与 MIME。
typedef AvatarPreparer = Future<PreparedAvatar?> Function(Uint8List raw);

/// 头像服务：负责本地归一化（居中裁切、缩放、去除 EXIF）、上传/清除以及内存+磁盘离线缓存。
class AvatarService {
  AvatarService({
    required this.api,
    Future<Directory> Function()? cacheDir,
    AvatarPreparer? prepare,
  }) : _cacheDir = cacheDir ?? getTemporaryDirectory,
       _prepare = prepare ?? _defaultPrepare;

  final AccountApi api;
  final Future<Directory> Function() _cacheDir;
  final AvatarPreparer _prepare;

  final Map<String, Uint8List> _mem = {};
  final Map<String, Future<Uint8List?>> _inflight = {};

  static String _memKey(String userId, String version) => '$userId:$version';

  static String _safeToken(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

  Future<Directory> _avatarDir() async {
    final base = await _cacheDir();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}jikelog-avatars',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<File> _cacheFile(String userId, String version) async {
    final dir = await _avatarDir();
    final name = '${_safeToken(userId)}_${_safeToken(version)}.img';
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// 按 (userId, version) 加载头像：依次命中内存缓存 → 磁盘缓存 → 接口下载。
  /// 离线或服务端返回 404 时返回 null，由界面回退到默认首字母头像。
  Future<Uint8List?> load(String userId, String version) {
    if (version.isEmpty) return Future.value(null);
    final key = _memKey(userId, version);
    final cached = _mem[key];
    if (cached != null) return Future.value(cached);
    return _inflight[key] ??= _doLoad(userId, version, key).whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<Uint8List?> _doLoad(String userId, String version, String key) async {
    try {
      final file = await _cacheFile(userId, version);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        if (bytes.isNotEmpty) {
          _mem[key] = bytes;
          return bytes;
        }
      }
    } on Object catch (e) {
      debugPrint('读取头像本地缓存失败: $e');
    }

    try {
      final bytes = await api.downloadAvatar();
      if (bytes.isEmpty) return null;
      _mem[key] = bytes;
      await _writeDiskCache(userId, version, bytes);
      return bytes;
    } on ApiException catch (e) {
      if (e.code != ApiErrorCode.avatarNotFound && !e.isNetwork) {
        debugPrint('下载头像失败: $e');
      }
      return null;
    } on Object catch (e) {
      debugPrint('下载头像异常: $e');
      return null;
    }
  }

  /// 校验、缩放并上传头像；成功后立刻写入本地缓存并返回最新 [User]。
  Future<User> upload(Uint8List rawBytes) async {
    if (rawBytes.isEmpty) {
      throw const ApiException(
        code: ApiErrorCode.validationFailed,
        message: '所选图片内容为空，请重新选择',
      );
    }
    final prepared = await _prepare(rawBytes);
    if (prepared == null) {
      throw const ApiException(
        code: ApiErrorCode.validationFailed,
        message: '仅支持 JPEG、PNG 或 WebP 格式的图片',
      );
    }
    if (prepared.bytes.length > maxAvatarBytes) {
      throw const ApiException(
        code: ApiErrorCode.validationFailed,
        message: '头像图片超过 2 MiB，请选择更小的图片',
      );
    }
    final updated = await api.uploadAvatar(
      prepared.bytes,
      prepared.contentType,
    );
    _evictUserMemory(updated.id);
    final version = updated.avatarVersion;
    if (version != null && version.isNotEmpty) {
      _mem[_memKey(updated.id, version)] = prepared.bytes;
      await _writeDiskCache(updated.id, version, prepared.bytes);
    }
    return updated;
  }

  /// 清除自定义头像并清理本机缓存，返回恢复默认头像后的 [User]。
  Future<User> remove(String userId) async {
    final updated = await api.deleteAvatar();
    _evictUserMemory(userId);
    await _evictUserDisk(userId);
    return updated;
  }

  /// 清空内存缓存；[disk] 为 true 时同时删除磁盘缓存（退出登录或注销账号时调用）。
  Future<void> clearAll({bool disk = true}) async {
    _mem.clear();
    if (!disk) return;
    try {
      final base = await _cacheDir();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}jikelog-avatars',
      );
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } on Object catch (e) {
      debugPrint('清理头像磁盘缓存失败: $e');
    }
  }

  void _evictUserMemory(String userId) {
    final prefix = '$userId:';
    _mem.removeWhere((k, _) => k.startsWith(prefix));
  }

  Future<void> _evictUserDisk(String userId, {String? keepFileName}) async {
    try {
      final dir = await _avatarDir();
      final prefix = '${_safeToken(userId)}_';
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.isEmpty
            ? ''
            : entry.uri.pathSegments.last;
        if (name.startsWith(prefix) && name != keepFileName) {
          try {
            entry.deleteSync();
          } on Object {
            // 忽略并发清理错误
          }
        }
      }
    } on Object {
      // 忽略清理失败
    }
  }

  Future<void> _writeDiskCache(
    String userId,
    String version,
    Uint8List bytes,
  ) async {
    try {
      final file = await _cacheFile(userId, version);
      file.writeAsBytesSync(bytes, flush: true);
      final keep = '${_safeToken(userId)}_${_safeToken(version)}.img';
      await _evictUserDisk(userId, keepFileName: keep);
    } on Object catch (e) {
      debugPrint('写入头像本地缓存失败: $e');
    }
  }

  /// 默认归一化：优先通过 dart:ui 居中裁切为 ≤512×512 PNG（同时天然剥离 EXIF 隐私元数据）；
  /// 若运行环境不支持重绘或重绘体积反增，则回退为已校验魔数的原始图片字节。
  static Future<PreparedAvatar?> _defaultPrepare(Uint8List raw) async {
    final detected = sniffAvatarMime(raw);
    try {
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      try {
        final side = math.min(src.width, src.height);
        final outSize = math.min(side, _targetAvatarSize);
        if (outSize > 0) {
          final sx = (src.width - side) / 2.0;
          final sy = (src.height - side) / 2.0;
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawImageRect(
            src,
            ui.Rect.fromLTWH(sx, sy, side.toDouble(), side.toDouble()),
            ui.Rect.fromLTWH(0, 0, outSize.toDouble(), outSize.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.high,
          );
          final picture = recorder.endRecording();
          final out = await picture.toImage(outSize, outSize);
          try {
            final bd = await out.toByteData(format: ui.ImageByteFormat.png);
            if (bd != null) {
              final png = bd.buffer.asUint8List(
                bd.offsetInBytes,
                bd.lengthInBytes,
              );
              if (png.isNotEmpty && png.length <= maxAvatarBytes) {
                return PreparedAvatar(png, 'image/png');
              }
            }
          } finally {
            out.dispose();
            picture.dispose();
          }
        }
      } finally {
        src.dispose();
        codec.dispose();
      }
    } on Object {
      // 回退到已校验的原始字节
    }

    if (detected == null) return null;
    return PreparedAvatar(raw, detected);
  }
}

/// 根据文件头魔数识别 JPEG / PNG / WebP；不识别时返回 null。
String? sniffAvatarMime(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

final avatarServiceProvider = Provider<AvatarService>(
  (ref) => AvatarService(api: ref.watch(accountApiProvider)),
);

final avatarPickerProvider = Provider<AvatarPicker>(
  (_) => () async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final path = files.first.path;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  },
);

/// 按 `(userId, avatarVersion)` 缓存并加载当前用户的自定义头像字节。
final userAvatarProvider = FutureProvider.family<Uint8List?, (String, String)>((
  ref,
  key,
) {
  final (userId, version) = key;
  return ref.watch(avatarServiceProvider).load(userId, version);
});
