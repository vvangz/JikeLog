import 'package:flutter/foundation.dart';

final _semverRe = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$');
final _safeNameRe = RegExp(r'^[A-Za-z0-9._-]+$');
final _sha256Re = RegExp(r'^[0-9a-fA-F]{64}$');

/// 单个安装包上限：512 MiB（防止异常清单诱发无限下载）。
const maxUpdatePackageBytes = 512 * 1024 * 1024;

/// 单个平台安装包元数据（来自官网 `/download/latest.json`）。
@immutable
class UpdateFile {
  const UpdateFile({
    required this.name,
    required this.size,
    required this.sha256,
  });

  final String name;
  final int size;
  final String sha256;

  static UpdateFile? tryParse(Object? raw, {required String requiredExt}) {
    if (raw is! Map<String, dynamic>) return null;
    final name = raw['name'];
    final size = raw['size'];
    final sha256 = raw['sha256'];
    if (name is! String ||
        !_safeNameRe.hasMatch(name) ||
        name == '.' ||
        name == '..' ||
        !name.toLowerCase().endsWith(requiredExt)) {
      return null;
    }
    if (size is! int || size <= 0 || size > maxUpdatePackageBytes) return null;
    if (sha256 is! String || !_sha256Re.hasMatch(sha256)) return null;
    return UpdateFile(name: name, size: size, sha256: sha256.toLowerCase());
  }
}

/// 官网 `/download/latest.json` 清单。
@immutable
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    this.publishedAt,
    this.releaseUrl,
    this.android,
    this.windows,
  });

  final String version;
  final DateTime? publishedAt;
  final String? releaseUrl;
  final UpdateFile? android;
  final UpdateFile? windows;

  static UpdateManifest? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final version = raw['version'];
    if (version is! String || !_semverRe.hasMatch(version)) return null;
    final files = raw['files'];
    if (files is! Map<String, dynamic>) return null;
    final android = UpdateFile.tryParse(files['android'], requiredExt: '.apk');
    final windows = UpdateFile.tryParse(files['windows'], requiredExt: '.msix');
    if (android == null && windows == null) return null;

    final publishedRaw = raw['publishedAt'];
    final publishedAt = publishedRaw is String
        ? DateTime.tryParse(publishedRaw)
        : null;
    final releaseRaw = raw['releaseUrl'];
    final releaseUrl = releaseRaw is String && releaseRaw.startsWith('https://')
        ? releaseRaw
        : null;

    return UpdateManifest(
      version: version,
      publishedAt: publishedAt,
      releaseUrl: releaseUrl,
      android: android,
      windows: windows,
    );
  }
}

/// 当前平台可下载安装的新版本信息。
@immutable
class UpdateCandidate {
  const UpdateCandidate({
    required this.version,
    required this.file,
    required this.downloadUrl,
    required this.changelogUrl,
    this.releaseUrl,
    this.publishedAt,
  });

  final String version;
  final UpdateFile file;
  final String downloadUrl;
  final String changelogUrl;
  final String? releaseUrl;
  final DateTime? publishedAt;
}

/// 安装器拉起结果。
enum InstallOutcome {
  /// 已成功拉起系统安装界面（Android 安装器或 Windows 应用安装程序）。
  launched,

  /// Android 尚未开启「安装未知应用」权限，已跳转到系统授权页。
  permissionRequired,

  /// 当前平台不支持直接安装。
  unsupported,

  /// 拉起安装失败。
  failed,
}

/// 比较两个 SemVer 版本号：a > b 返回正数，相等返回 0，a < b 返回负数。
int compareSemVer(String a, String b) {
  final ma = _semverRe.firstMatch(a.trim());
  final mb = _semverRe.firstMatch(b.trim());
  if (ma == null || mb == null) return a.compareTo(b);

  for (var i = 1; i <= 3; i++) {
    final diff = int.parse(ma.group(i)!) - int.parse(mb.group(i)!);
    if (diff != 0) return diff;
  }

  final preA = ma.group(4);
  final preB = mb.group(4);
  if (preA == null && preB == null) return 0;
  if (preA == null) return 1; // 正式版 > 预发布版
  if (preB == null) return -1;

  final partsA = preA.split('.');
  final partsB = preB.split('.');
  final len = partsA.length < partsB.length ? partsA.length : partsB.length;
  for (var i = 0; i < len; i++) {
    final na = int.tryParse(partsA[i]);
    final nb = int.tryParse(partsB[i]);
    final diff = na != null && nb != null
        ? na - nb
        : partsA[i].compareTo(partsB[i]);
    if (diff != 0) return diff;
  }
  return partsA.length - partsB.length;
}

/// [latest] 是否严格高于 [current]。
bool isNewerVersion(String latest, String current) =>
    compareSemVer(latest, current) > 0;

/// 格式化文件大小（MB / KB）。
String formatByteSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).round()} KB';
  }
  return '$bytes B';
}
