import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/models.dart';
import '../auth/auth_controller.dart';

/// 本地设置有未同步修改的标记键（退出登录时清除，避免上传到下一个账号）。
const settingsDirtyKey = 'settings.dirty';

final settingsControllerProvider =
    NotifierProvider<SettingsController, UserSettings>(SettingsController.new);

/// 用户设置：本地立即生效并持久化，登录后与服务端同步。
///
/// - 登录（或启动恢复登录态）时：本地有未同步的修改则上传，否则以服务端为准。
/// - 修改时：先保存在本机，再尝试上传；失败（如离线）时标记为待同步，下次登录态恢复时补传。
class SettingsController extends Notifier<UserSettings> {
  static const _key = 'settings.local';

  @override
  UserSettings build() {
    ref.listen(authControllerProvider, (prev, next) {
      if (next is SignedIn && prev is! SignedIn) unawaited(sync());
    });
    return _load();
  }

  UserSettings _load() {
    final raw = ref.read(keyValueStoreProvider).getString(_key);
    if (raw == null) return const UserSettings();
    try {
      return UserSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const UserSettings();
    }
  }

  bool get _dirty =>
      ref.read(keyValueStoreProvider).getString(settingsDirtyKey) == '1';

  Future<void> _persist(UserSettings s, {required bool dirty}) async {
    final store = ref.read(keyValueStoreProvider);
    await store.setString(_key, jsonEncode(s.toJson()));
    if (dirty) {
      await store.setString(settingsDirtyKey, '1');
    } else {
      await store.remove(settingsDirtyKey);
    }
  }

  /// 本地修改计数：同步响应返回时若本地又有新修改，就不用旧结果覆盖。
  int _version = 0;
  Future<bool>? _inflight;

  /// 与服务端同步，返回是否成功。多次调用按顺序执行，不会交错。
  Future<bool> sync() {
    final previous = _inflight;
    final run = () async {
      if (previous != null) await previous;
      return _syncOnce();
    }();
    _inflight = run;
    return run;
  }

  Future<bool> _syncOnce() async {
    final api = ref.read(accountApiProvider);
    final startVersion = _version;
    try {
      final remote = _dirty
          ? await api.saveSettings(state)
          : await api.settings();
      if (_version != startVersion) return true; // 期间有新修改，由其后续的同步上传
      state = remote;
      await _persist(remote, dirty: false);
      return true;
    } on Object catch (e) {
      debugPrint('同步设置失败: $e');
      return false;
    }
  }

  /// 修改设置。返回 false 表示已保存在本机但尚未同步到服务端。
  Future<bool> update(UserSettings next) async {
    if (next == state) return true;
    _version++;
    state = next;
    await _persist(next, dirty: true);
    if (ref.read(authControllerProvider) is! SignedIn) return false;
    return sync();
  }
}

/// 把设置中的主题字符串转换为 Flutter ThemeMode。
ThemeMode themeModeOf(UserSettings s) => switch (s.themeMode) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};
