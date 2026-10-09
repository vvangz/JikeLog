import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../storage/stores.dart';

/// 本机信息，登录时上报，用于"已登录设备"列表。
@immutable
class DeviceIdentity {
  const DeviceIdentity({
    required this.installationId,
    required this.platform,
    this.model = '',
    this.osVersion = '',
    this.appVersion = '',
  });

  /// 安装实例标识：首次启动生成并持久保存，卸载重装后会变化。
  final String installationId;
  final String platform;
  final String model;
  final String osVersion;
  final String appVersion;

  Map<String, dynamic> toJson() => {
    'installationId': installationId,
    'platform': platform,
    'model': model,
    'osVersion': osVersion,
    'appVersion': appVersion,
  };

  static const _installationKey = 'device.installationId';

  /// 读取（或首次生成）安装标识并收集设备信息。设备信息读取失败不影响使用。
  static Future<DeviceIdentity> load(KeyValueStore store) async {
    var id = store.getString(_installationKey);
    if (id == null) {
      id = const Uuid().v4();
      await store.setString(_installationKey, id);
    }
    var model = '';
    var os = '';
    var version = '';
    final platform = _platformName();
    try {
      if (platform == 'android') {
        final a = await DeviceInfoPlugin().androidInfo;
        model = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android ${a.version.release}';
      }
      version = (await PackageInfo.fromPlatform()).version;
    } on Exception catch (e) {
      debugPrint('读取设备信息失败: $e');
    }
    return DeviceIdentity(
      installationId: id,
      platform: platform,
      model: model,
      osVersion: os,
      appVersion: version,
    );
  }

  static String _platformName() {
    // Web 上不能访问 dart:io 的 Platform（仅用于本地联调与截图）
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }
}
