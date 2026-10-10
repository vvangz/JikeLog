import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attachment_providers.dart';

/// 附件图片在本机的文件（必要时下载），同一附件同时只下载一次。
final attachmentFileProvider = FutureProvider.autoDispose.family<File, String>(
  (ref, id) => ref.watch(attachmentServiceProvider).open(id),
);

/// 直接传给编辑器的图片大小上限；更大的图片缩小后再传。
const maxInlineImageBytes = 1536 * 1024;

/// 超过这个大小的文件不当作图片读取（正文可能引用了 PDF、音频等大文件）。
const maxImageFileBytes = 20 * 1024 * 1024;

/// 缩小后的最大宽度（像素）。
const inlineImageWidth = 1280;

/// 按文件头识别编辑器（WebView）能直接显示的图片格式。
String? sniffImageMime(Uint8List b) {
  bool at(int offset, List<int> sig) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
      at(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

/// 把图片文件转为编辑器可显示的 data: 地址（ADR-007）。
///
/// 常见格式且不太大时直接编码；否则解码后缩小为 PNG。无法解码（不是图片）时返回 null。
Future<String?> imageDataUrl(File file) async {
  if (await file.length() > maxImageFileBytes) return null;
  final bytes = await file.readAsBytes();
  final mime = sniffImageMime(bytes);
  if (mime != null && bytes.length <= maxInlineImageBytes) {
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }
  final png = await _downscale(bytes);
  return png == null ? null : 'data:image/png;base64,${base64Encode(png)}';
}

Future<Uint8List?> _downscale(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width > inlineImageWidth
        ? inlineImageWidth
        : descriptor.width;
    final codec = await descriptor.instantiateCodec(targetWidth: width);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return data?.buffer.asUint8List();
  } on Object catch (e) {
    debugPrint('图片无法解码: $e');
    return null;
  }
}
