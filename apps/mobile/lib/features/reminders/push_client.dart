import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';

/// 极光推送 AppKey，构建时通过 `--dart-define=JIKELOG_JPUSH_APPKEY=…` 注入；
/// Android 清单中的 AppKey 由环境变量 JPUSH_APPKEY 注入（见 android/app/build.gradle.kts）。
/// 为空时不初始化推送 SDK，提醒只靠本地闹钟（ADR-008）。
const jpushAppKey = String.fromEnvironment('JIKELOG_JPUSH_APPKEY');

/// 服务端推送通道。
abstract class PushClient {
  /// 推送通道标识（服务端 PushRegistration.provider），不可用时为 null。
  String? get provider;

  /// 启动推送 SDK（只能在用户同意隐私政策之后调用），返回本设备的推送标识。
  /// [onOpen] 在用户点按推送通知时调用，参数为备忘 ID。取不到标识时返回 null。
  Future<String?> start({required void Function(String memoId) onOpen});
}

/// 未配置推送时的实现：不启动任何 SDK。
class NoPushClient implements PushClient {
  const NoPushClient();

  @override
  String? get provider => null;

  @override
  Future<String?> start({required void Function(String memoId) onOpen}) async =>
      null;
}

/// 极光推送。
class JPushClient implements PushClient {
  JPushClient({required this.appKey, JPushFlutterInterface? jpush})
    : _jpush = jpush ?? JPush.newJPush();

  final String appKey;
  final JPushFlutterInterface _jpush;
  bool _started = false;

  /// 等待注册完成的最长时间（首次启动需要连上极光服务器）。
  static const _registerTimeout = Duration(seconds: 15);

  @override
  String? get provider => 'jpush';

  @override
  Future<String?> start({required void Function(String memoId) onOpen}) async {
    try {
      if (!_started) {
        _jpush.setAuth(enable: true); // 隐私合规：同意后才允许 SDK 采集与联网
        // 只用推送：关闭地理围栏、智能推送、数据洞察、应用间关联启动与自动唤醒
        _jpush.setGeofenceEnable(enable: false);
        _jpush.setSmartPushEnable(enable: false);
        _jpush.setDataInsightsEnable(enable: false);
        _jpush.setLinkMergeEnable(enable: false);
        _jpush.enableAutoWakeup(enable: false);
        _jpush.addEventHandler(
          onOpenNotification: (message) async {
            final id = memoIdOfJPushMessage(message);
            if (id != null) onOpen(id);
          },
        );
        _jpush.setup(
          appKey: appKey,
          channel: 'developer-default',
          production: kReleaseMode,
          debug: kDebugMode,
        );
        _started = true;
      }
      return await _registrationId();
    } on PlatformException catch (e) {
      debugPrint('极光推送启动失败: $e');
      return null;
    }
  }

  Future<String?> _registrationId() async {
    final deadline = DateTime.now().add(_registerTimeout);
    while (true) {
      final id = await _jpush.getRegistrationID();
      if (id.isNotEmpty) return id;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}

/// 从极光通知事件中取出备忘 ID。Android 上附加字段在 extras 的
/// `cn.jpush.android.EXTRA` 中，为 JSON 字符串。
String? memoIdOfJPushMessage(Map<String, dynamic> message) {
  final extras = message['extras'];
  if (extras is! Map) return null;
  Object? raw = extras['cn.jpush.android.EXTRA'] ?? extras;
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
  if (raw is! Map) return null;
  final id = raw['memoId'];
  return id is String && id.isNotEmpty ? id : null;
}
