import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

/// Windows 上可以直接交给默认应用打开的附件类型。其余类型（可执行文件、脚本、快捷方式、
/// 含宏的 Office 文件、网页等）只打开所在文件夹，由用户自行决定（ADR-013）。
const desktopOpenableExtensions = {
  // 图片
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.tif', '.tiff', '.heic',
  // 文档
  '.pdf', '.txt', '.md', '.csv', '.log', '.rtf', '.epub',
  '.docx', '.xlsx', '.pptx', '.doc', '.xls', '.ppt', '.odt', '.ods', '.odp',
  // 压缩包
  '.zip', '.7z', '.rar',
  // 音视频
  '.mp3', '.m4a', '.wav', '.aac', '.flac', '.ogg', '.opus', '.wma',
  '.mp4', '.m4v', '.mov', '.mkv', '.avi', '.wmv', '.webm',
};

/// Windows 保留的设备名，不能作为文件名（带不带扩展名都不行）。
final _reserved = RegExp(
  r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
  caseSensitive: false,
);

/// 把附件的原文件名变成可以安全落盘的文件名：只取最后一段，去掉 Windows 不允许的字符与
/// 末尾的点和空格，避开设备名，限制长度。
@visibleForTesting
String safeFileName(String name) {
  var s = name.replaceAll(RegExp(r'[\\/]'), '_');
  s = s.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
  s = s.replaceAll(RegExp(r'[. ]+$'), '').trim();
  if (s.isEmpty || s == '..') s = 'attachment';
  if (_reserved.hasMatch(s)) s = '_$s';
  if (s.length > 120) {
    final ext = p.extension(s);
    final keep = ext.length <= 16 ? ext : '';
    s = s.substring(0, 120 - keep.length) + keep;
  }
  return s;
}

/// [safeFileName] 处理后的名字能否直接交给默认应用打开。
@visibleForTesting
bool isDesktopOpenable(String safeName) =>
    desktopOpenableExtensions.contains(p.extension(safeName).toLowerCase());

/// 桌面端（Windows）打开附件。附件在本机以 ID 命名、没有扩展名，系统无法据此选择应用，
/// 所以先复制一份以原文件名命名的副本，并标记为来自互联网（Mark-of-the-Web），
/// 使 Office 受保护视图与 SmartScreen 生效；不在允许列表中的类型只打开副本所在的文件夹。
Future<bool> openOnDesktop(
  File file,
  String fileName, {
  Future<bool> Function(Uri uri)? launch,
  Directory? root,
}) async {
  final base =
      root ?? Directory(p.join((await getTemporaryDirectory()).path, 'open'));
  await _pruneOld(base);
  final dir = Directory(p.join(base.path, const Uuid().v4()));
  await dir.create(recursive: true);
  final name = safeFileName(fileName);
  final copy = await file.copy(p.join(dir.path, name));
  await _markFromInternet(copy);
  final target = isDesktopOpenable(name) ? copy.path : dir.path;
  try {
    return await (launch ?? launchUrl)(Uri.file(target));
  } on PlatformException catch (e) {
    debugPrint('打开附件失败: $e');
    return false;
  }
}

/// 删除桌面端打开附件时留下的全部副本（退出登录时）。
Future<void> deleteDesktopOpenCopies() async {
  try {
    final base = Directory(
      p.join((await getTemporaryDirectory()).path, 'open'),
    );
    if (await base.exists()) await base.delete(recursive: true);
  } on Object catch (e) {
    // 测试中没有 path_provider；副本仍被其他应用占用时删除失败，一小时后打开附件时再清理
    debugPrint('删除附件副本失败: $e');
  }
}

/// NTFS 的 Zone.Identifier 备用数据流，ZoneId=3 表示"来自互联网"。不支持时忽略。
Future<void> _markFromInternet(File f) async {
  if (!Platform.isWindows) return;
  try {
    await File('${f.path}:Zone.Identifier')
        .writeAsString('[ZoneTransfer]\r\nZoneId=3\r\n');
  } on FileSystemException {
    // 非 NTFS 卷（如 FAT32 U 盘）没有备用数据流
  }
}

/// 删除一小时前打开过的副本（仍被其他应用占用的会删除失败，下次再试）。
Future<void> _pruneOld(Directory base) async {
  if (!await base.exists()) return;
  final cutoff = DateTime.now().subtract(const Duration(hours: 1));
  await for (final e in base.list()) {
    try {
      if ((await e.stat()).modified.isBefore(cutoff)) {
        await e.delete(recursive: true);
      }
    } on FileSystemException {
      // 文件仍在使用中
    }
  }
}
