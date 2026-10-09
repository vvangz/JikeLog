import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/endpoints.dart';
import '../core/config.dart';
import '../core/device/device_identity.dart';
import '../core/storage/stores.dart';

/// 键值存储，启动时在 ProviderScope 中覆盖。
final keyValueStoreProvider = Provider<KeyValueStore>(
  (_) => throw UnimplementedError('keyValueStoreProvider 需在启动时覆盖'),
);

/// 本机信息，启动时在 ProviderScope 中覆盖。
final deviceIdentityProvider = Provider<DeviceIdentity>(
  (_) => throw UnimplementedError('deviceIdentityProvider 需在启动时覆盖'),
);

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenStore: ref.watch(tokenStoreProvider),
  ),
);

final authApiProvider = Provider<AuthApi>(
  (ref) =>
      AuthApi(ref.watch(apiClientProvider), ref.watch(deviceIdentityProvider)),
);

final accountApiProvider = Provider<AccountApi>(
  (ref) => AccountApi(ref.watch(apiClientProvider)),
);
