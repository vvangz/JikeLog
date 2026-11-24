import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_models.dart';

/// 调起系统安装器覆盖安装本地已校验的安装包。
typedef InstallPackageFn = Future<InstallOutcome> Function(File file);

const _androidUpdaterChannel = MethodChannel('jikelog/updater');

/// Android：通过原生 MethodChannel + FileProvider 调起系统安装器覆盖安装 APK。
Future<InstallOutcome> installAndroidApk(
  File file, {
  MethodChannel channel = _androidUpdaterChannel,
}) async {
  try {
    final res = await channel.invokeMethod<String>('installApk', {
      'path': file.path,
    });
    return switch (res) {
      'launched' => InstallOutcome.launched,
      'permission_required' => InstallOutcome.permissionRequired,
      _ => InstallOutcome.failed,
    };
  } on MissingPluginException {
    return InstallOutcome.unsupported;
  } on PlatformException catch (e) {
    debugPrint('调起 Android 安装器失败: $e');
    return InstallOutcome.failed;
  }
}

/// Windows：通过系统默认关联调起 Windows 应用安装程序打开已校验的 MSIX 覆盖更新。
Future<InstallOutcome> installWindowsMsix(
  File file, {
  Future<bool> Function(Uri uri)? launch,
}) async {
  try {
    final ok = await (launch ?? launchUrl)(Uri.file(file.path));
    return ok ? InstallOutcome.launched : InstallOutcome.failed;
  } on PlatformException catch (e) {
    debugPrint('调起 Windows 应用安装程序失败: $e');
    return InstallOutcome.failed;
  }
}
