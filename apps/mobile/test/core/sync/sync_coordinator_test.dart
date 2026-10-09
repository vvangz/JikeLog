import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/api/models.dart';
import 'package:jikelog/core/storage/stores.dart';
import 'package:jikelog/core/sync/sync_providers.dart';
import 'package:jikelog/features/auth/auth_controller.dart';

import '../../support/fake_backend.dart';
import '../../support/fake_sync_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('登录后同步并保持实时连接；切换账号或退出时清空本机数据', () async {
    final server = FakeSyncServer();
    final db = testDatabase();
    final backend = FakeBackend()
      ..on('GET', '/api/v1/me', (_) => FakeResponse.ok(userJson()))
      ..on('POST', '/api/v1/auth/logout', (_) => FakeResponse.ok({'ok': true}))
      ..on(
        'GET',
        '/api/v1/me/settings',
        (_) => FakeResponse.ok(const UserSettings().toJson()),
      );
    final c = ProviderContainer(
      overrides: testOverrides(
        backend: backend,
        store: MemoryStore({'consent.version': '1'}),
        tokens: MemoryTokenStore(testTokens),
        db: db,
        syncServer: server,
      ),
    );
    addTearDown(c.dispose);
    c.read(syncCoordinatorProvider);
    await eventually(() => c.read(authControllerProvider) is SignedIn);
    final realtime = c.read(realtimeClientProvider) as FakeRealtime;
    await eventually(() => realtime.running, reason: '登录后应建立实时连接');
    expect(await db.meta('sync.userId'), userJson()['id']);

    // 本机数据属于当前账号
    await c.read(recordStoreProvider).write(
      'worklog',
      '0192a000-0000-7000-8000-0000000000c1',
      {'date': '2026-10-09'},
    );
    await c.read(syncEngineProvider).sync();
    expect(server.records, hasLength(1));

    // 另一个账号登录：清空上一个账号的本地数据
    await c
        .read(syncCoordinatorProvider)
        .onAuth(
          SignedIn(
            User.fromJson(
              userJson(username: 'lisi')
                ..['id'] = '0192a000-0000-7000-8000-000000000099',
            ),
          ),
        );
    expect(
      await c
          .read(recordStoreProvider)
          .get('0192a000-0000-7000-8000-0000000000c1'),
      isNull,
    );

    // 退出登录：停止实时连接并清空
    await c.read(recordStoreProvider).write(
      'worklog',
      '0192a000-0000-7000-8000-0000000000c2',
      {'date': '2026-10-09'},
    );
    await c.read(authControllerProvider.notifier).logout();
    await eventually(() => !realtime.running, reason: '退出后应断开实时连接');
    await eventually(() => true);
    expect(
      await c
          .read(recordStoreProvider)
          .get('0192a000-0000-7000-8000-0000000000c2'),
      isNull,
    );
  });
}
