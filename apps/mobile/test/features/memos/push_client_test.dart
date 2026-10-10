import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/reminders/device_time_zone.dart';
import 'package:jikelog/features/reminders/local_notifier.dart';
import 'package:jikelog/features/reminders/push_client.dart';
import 'package:jpush_flutter/jpush_interface.dart';

/// 记录调用的极光插件。
class FakeJPush extends JPushFlutterInterface {
  final calls = <String>[];
  List<String> ids = ['', '', 'reg-1'];
  EventHandler? onOpen;
  bool fail = false;

  @override
  void setAuth({bool enable = true}) => calls.add('setAuth:$enable');

  @override
  void setGeofenceEnable({bool enable = true}) => calls.add('geofence:$enable');

  @override
  void setSmartPushEnable({bool enable = true}) => calls.add('smart:$enable');

  @override
  void setDataInsightsEnable({bool enable = true}) =>
      calls.add('insights:$enable');

  @override
  void setLinkMergeEnable({bool enable = true}) => calls.add('link:$enable');

  @override
  void enableAutoWakeup({bool enable = false}) => calls.add('wakeup:$enable');

  @override
  void addEventHandler({
    EventHandler? onReceiveNotification,
    EventHandler? onOpenNotification,
    EventHandler? onReceiveMessage,
    EventHandler? onReceiveNotificationAuthorization,
    EventHandler? onNotifyMessageUnShow,
    EventHandler? onConnected,
    EventHandler? onInAppMessageClick,
    EventHandler? onInAppMessageShow,
    EventHandler? onNotifyButtonClick,
    EventHandler? onCommandResult,
    EventHandler? onReceiveDeviceToken,
    EventHandler? onVoipMessage,
  }) {
    calls.add('handlers');
    onOpen = onOpenNotification;
  }

  @override
  void setup({
    String appKey = '',
    bool production = false,
    String channel = '',
    bool debug = false,
  }) {
    if (fail) throw PlatformException(code: 'boom');
    calls.add('setup:$appKey');
  }

  @override
  Future<String> getRegistrationID() async =>
      ids.length > 1 ? ids.removeAt(0) : ids.first;
}

void main() {
  test('同意后才授权并启动：关闭与推送无关的功能，等到注册标识', () async {
    final j = FakeJPush();
    final client = JPushClient(appKey: 'key', jpush: j);
    final opened = <String>[];
    expect(client.provider, 'jpush');
    expect(await client.start(onOpen: opened.add), 'reg-1');
    expect(j.calls.first, 'setAuth:true');
    expect(j.calls.last, 'setup:key');
    expect(
      j.calls,
      containsAll([
        'geofence:false',
        'smart:false',
        'insights:false',
        'link:false',
        'wakeup:false',
      ]),
    );
    // 再次启动不重复初始化
    expect(await client.start(onOpen: opened.add), 'reg-1');
    expect(j.calls.where((c) => c.startsWith('setup')), hasLength(1));

    await j.onOpen!({
      'extras': {'cn.jpush.android.EXTRA': '{"memoId":"m-1","type":"memo"}'},
    });
    expect(opened, ['m-1']);
  });

  test('启动失败时返回 null；未配置推送时不启动', () async {
    final client = JPushClient(appKey: 'key', jpush: FakeJPush()..fail = true);
    expect(await client.start(onOpen: (_) {}), isNull);
    const none = NoPushClient();
    expect(none.provider, isNull);
    expect(await none.start(onOpen: (_) {}), isNull);
  });

  test('从推送事件中取出备忘 ID', () {
    expect(
      memoIdOfJPushMessage({
        'extras': {'cn.jpush.android.EXTRA': '{"memoId":"a"}'},
      }),
      'a',
    );
    expect(
      memoIdOfJPushMessage({
        'extras': {'memoId': 'b'},
      }),
      'b',
    );
    expect(memoIdOfJPushMessage({'extras': 'x'}), isNull);
    expect(
      memoIdOfJPushMessage({
        'extras': {'cn.jpush.android.EXTRA': 'not json'},
      }),
      isNull,
    );
    expect(
      memoIdOfJPushMessage({
        'extras': {'cn.jpush.android.EXTRA': '[1]'},
      }),
      isNull,
    );
    expect(
      memoIdOfJPushMessage({
        'extras': {'memoId': ''},
      }),
      isNull,
    );
  });

  group('设备时区', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('jikelog/device');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('读取平台通道，失败或为空时使用默认时区', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'timeZone' ? 'Europe/Berlin' : null,
      );
      expect(await const DeviceTimeZone().current(), 'Europe/Berlin');
      messenger.setMockMethodCallHandler(channel, (_) async => '');
      expect(await const DeviceTimeZone().current(), fallbackTimeZone);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'x'),
      );
      expect(await const DeviceTimeZone().current(), fallbackTimeZone);
    });
  });

  test('权限：两项都允许才能本地按时提醒', () {
    const ok = ReminderPermissions(notifications: true, exact: true);
    expect(ok.canRemindLocally, isTrue);
    expect(
      const ReminderPermissions(
        notifications: true,
        exact: false,
      ).canRemindLocally,
      isFalse,
    );
    expect(ReminderPermissions.none.canRemindLocally, isFalse);
    expect(ok, const ReminderPermissions(notifications: true, exact: true));
    expect(ok.hashCode, isNot(ReminderPermissions.none.hashCode));
  });
}
