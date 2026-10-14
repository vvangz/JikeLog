import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/reminders/local_notifier.dart';

/// MSIX 清单中的通知激活器须与 App 初始化通知时的 GUID 一致，否则点击 Windows 通知无法唤起 App。
void main() {
  test('msix_config.toast_activator.clsid 与 windowsToastActivatorGuid 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final clsid = RegExp(r'toast_activator:\s*\n\s*clsid:\s*([0-9a-fA-F-]{36})')
        .firstMatch(pubspec)
        ?.group(1);
    expect(clsid, windowsToastActivatorGuid);
  });
}
