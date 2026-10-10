import 'package:flutter/services.dart';

import 'local_notifier.dart';

/// 设备时区（IANA 名称），由 MainActivity 中的平台通道提供。
class DeviceTimeZone {
  const DeviceTimeZone([this._channel = const MethodChannel('jikelog/device')]);

  final MethodChannel _channel;

  /// 当前时区；读取失败时为 [fallbackTimeZone]。
  Future<String> current() async {
    try {
      final tz = await _channel.invokeMethod<String>('timeZone');
      return tz == null || tz.isEmpty ? fallbackTimeZone : tz;
    } on Object {
      return fallbackTimeZone;
    }
  }
}
