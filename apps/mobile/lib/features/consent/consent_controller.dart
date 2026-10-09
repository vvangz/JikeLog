import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config.dart';

final consentControllerProvider = NotifierProvider<ConsentController, bool>(
  ConsentController.new,
);

/// 隐私政策与用户协议同意状态。未同意前只展示同意页，不初始化任何第三方 SDK（v0.5.0 的推送 SDK 亦遵循）。
class ConsentController extends Notifier<bool> {
  static const _key = 'consent.version';

  @override
  bool build() =>
      ref.read(keyValueStoreProvider).getString(_key) ==
      '${AppConfig.privacyPolicyVersion}';

  Future<void> accept() async {
    await ref
        .read(keyValueStoreProvider)
        .setString(_key, '${AppConfig.privacyPolicyVersion}');
    state = true;
  }
}
