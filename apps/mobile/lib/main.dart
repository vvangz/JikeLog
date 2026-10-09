import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config.dart';
import 'core/device/device_identity.dart';
import 'core/storage/stores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 正式构建只允许 HTTPS（网络安全配置会拦截明文请求），漏传 --dart-define 时尽早暴露
  if (kReleaseMode && !AppConfig.apiBaseUrl.startsWith('https://')) {
    throw StateError(
      '正式构建必须通过 --dart-define=JIKELOG_API_BASE=https://… 指定 API 地址',
    );
  }
  if (kReleaseMode && AppConfig.e2ePublicKey == AppConfig.devE2EPublicKey) {
    throw StateError(
      '正式构建必须通过 --dart-define=JIKELOG_E2E_PUBLIC_KEY=… 指定生产环境的传输加密公钥',
    );
  }
  final store = await PrefsStore.open();
  final device = await DeviceIdentity.load(store);
  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        deviceIdentityProvider.overrideWithValue(device),
      ],
      child: const JikeLogApp(),
    ),
  );
}
