import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前平台能用哪些功能（ADR-013）。Android 与 Windows 共用一套代码，
/// 依赖只有 Android 实现的插件（系统日历、极光推送等）的功能在 Windows 上关闭。
@immutable
class PlatformFeatures {
  const PlatformFeatures({
    required this.isDesktop,
    required this.systemCalendar,
    required this.pushChannel,
    required this.richTextEditor,
    required this.shareSheet,
    required this.exactAlarmPermission,
  });

  static const android = PlatformFeatures(
    isDesktop: false,
    systemCalendar: true,
    pushChannel: true,
    richTextEditor: true,
    shareSheet: true,
    exactAlarmPermission: true,
  );

  static const windows = PlatformFeatures(
    isDesktop: true,
    systemCalendar: false,
    pushChannel: false,
    richTextEditor: false,
    shareSheet: false,
    exactAlarmPermission: false,
  );

  /// 运行平台对应的功能集。`flutter test` 中固定为 Android，
  /// 使本机（Windows）与 CI（Linux）上的测试行为一致；测试 Windows 行为时覆盖 [platformFeaturesProvider]。
  static PlatformFeatures get current {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return android;
    }
    return Platform.isWindows ? windows : android;
  }

  /// 桌面端：键盘快捷键、窗口较宽时的布局、导出时另存为文件等。
  final bool isDesktop;

  /// 备忘录写入系统日历（device_calendar_plus 只支持 Android 与 iOS）。
  final bool systemCalendar;

  /// 极光推送（只支持 Android 与 iOS）。
  final bool pushChannel;

  /// 笔记的富文本编辑器（打包进 App 的 Tiptap 页面，需要 WebView）。
  final bool richTextEditor;

  /// 系统分享面板。没有时导出文件改为"另存为"。
  final bool shareSheet;

  /// 精确闹钟权限（Android 12 起需要用户授权）。
  final bool exactAlarmPermission;
}

final platformFeaturesProvider = Provider<PlatformFeatures>(
  (_) => PlatformFeatures.current,
);
