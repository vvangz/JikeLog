/// 服务端已开通的可选功能（系统信息接口返回），App 据此隐藏尚不可用的入口（ADR-012）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../platform/platform_features.dart';

@immutable
class ServerFeatures {
  const ServerFeatures({this.sms = true, this.push = false, this.captcha});

  factory ServerFeatures.fromJson(Map<String, dynamic> j) => ServerFeatures(
    sms: j['sms'] as bool? ?? true,
    push: j['push'] as bool? ?? false,
    captcha: switch (j['captcha']) {
      final Map<String, dynamic> c => CaptchaConfig.fromJson(c),
      _ => null,
    },
  );

  /// 短信：为 false 时手机号登录、注册、绑定与找回密码都不可用。
  final bool sms;

  /// 服务端推送：为 false 时提醒只依赖本地闹钟。
  final bool push;

  /// 发送登录、找回密码验证码前的人机验证；为 null 时不需要。
  final CaptchaConfig? captcha;
}

/// 阿里云验证码 2.0 的初始化参数（由服务端下发，均非密钥）。
@immutable
class CaptchaConfig {
  const CaptchaConfig({
    required this.region,
    required this.prefix,
    required this.sceneId,
  });

  /// 字段缺失或类型不对时返回 null（发送验证码时由服务端给出明确的错误）。
  static CaptchaConfig? fromJson(Map<String, dynamic> j) => switch (j) {
    {
      'region': final String region,
      'prefix': final String prefix,
      'sceneId': final String sceneId,
    } =>
      CaptchaConfig(region: region, prefix: prefix, sceneId: sceneId),
    _ => null,
  };

  final String region;
  final String prefix;
  final String sceneId;
}

/// 服务端功能。查询失败（离线、旧版服务端）时按全部可用处理：
/// 不可用的功能由服务端返回明确的错误（如 SMS_DISABLED），界面照常提示。
final serverFeaturesProvider = FutureProvider<ServerFeatures>((ref) async {
  try {
    final info =
        await ref.watch(apiClientProvider).get('/api/v1/system/info')
            as Map<String, dynamic>;
    final f = info['features'];
    return f is Map<String, dynamic>
        ? ServerFeatures.fromJson(f)
        : const ServerFeatures();
  } on Object catch (e) {
    debugPrint('读取服务端功能失败: $e');
    return const ServerFeatures();
  }
});

/// 本机能否使用短信验证码（查询完成前按能用处理）：服务端未开通短信，
/// 或发送验证码需要人机验证而本机没有 WebView（Windows）时不能。
bool smsEnabled(WidgetRef ref) {
  final f = ref.watch(serverFeaturesProvider).value;
  if (f == null) return true;
  return f.sms &&
      (f.captcha == null || ref.watch(platformFeaturesProvider).webView);
}

/// 不能使用短信验证码的原因。
String smsUnavailableReason(WidgetRef ref) =>
    ref.watch(serverFeaturesProvider).value?.sms ?? true
    ? '电脑端暂不支持短信验证，请在手机上操作'
    : smsUnavailableHint;

/// 短信未开通时的统一说明。
const smsUnavailableHint = '短信功能暂未开放';
