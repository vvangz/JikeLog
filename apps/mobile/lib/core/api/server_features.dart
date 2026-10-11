/// 服务端已开通的可选功能（系统信息接口返回），App 据此隐藏尚不可用的入口（ADR-012）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

@immutable
class ServerFeatures {
  const ServerFeatures({this.sms = true, this.push = false});

  factory ServerFeatures.fromJson(Map<String, dynamic> j) => ServerFeatures(
    sms: j['sms'] as bool? ?? true,
    push: j['push'] as bool? ?? false,
  );

  /// 短信：为 false 时手机号登录、注册、绑定与找回密码都不可用。
  final bool sms;

  /// 服务端推送：为 false 时提醒只依赖本地闹钟。
  final bool push;
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

/// 是否开通了短信（查询完成前按开通处理）。
bool smsEnabled(WidgetRef ref) =>
    ref.watch(serverFeaturesProvider).value?.sms ?? true;

/// 短信未开通时的统一说明。
const smsUnavailableHint = '短信功能暂未开放';
