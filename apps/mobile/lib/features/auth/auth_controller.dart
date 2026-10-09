import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../consent/consent_controller.dart';
import '../settings/settings_controller.dart';

/// 登录状态。
sealed class AuthState {
  const AuthState();
}

/// 启动时正在恢复登录态。
class AuthLoading extends AuthState {
  const AuthLoading();
}

class SignedOut extends AuthState {
  const SignedOut({this.reason});

  /// 被动退出的原因（如在其他设备修改了密码），用于在登录页提示。
  final String? reason;
}

class SignedIn extends AuthState {
  const SignedIn(this.user);

  final User user;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// 本设备在服务端的设备 ID（登录时保存；实时通知据此忽略本设备产生的修改）。
const deviceIdKey = 'auth.deviceId';

/// 管理登录态：恢复会话、登录、注册、退出，以及会话失效时回到登录页。
///
/// 离线优先：有令牌但网络不可用时使用本地缓存的账号信息进入应用，而不是退回登录页。
class AuthController extends Notifier<AuthState> {
  static const _userCacheKey = 'auth.user';

  @override
  AuthState build() {
    final client = ref.read(apiClientProvider);
    client.onSessionExpired = () => _signOutLocally(reason: '登录已失效，请重新登录');
    // 同意隐私政策之前不发起任何网络请求（包括恢复登录态）
    if (ref.read(consentControllerProvider)) {
      unawaited(Future.microtask(_restore));
    } else {
      ref.listen(consentControllerProvider, (_, consented) {
        if (consented) unawaited(_restore());
      });
    }
    return const AuthLoading();
  }

  /// 恢复登录态。任何失败都必须落到确定的状态，否则会一直停在启动页。
  Future<void> _restore() async {
    final client = ref.read(apiClientProvider);
    bool hasTokens;
    try {
      hasTokens = await client.restore();
    } on Object catch (e) {
      debugPrint('读取令牌失败，按未登录处理: $e');
      hasTokens = false;
    }
    if (!hasTokens) {
      state = const SignedOut();
      return;
    }
    final cached = _cachedUser();
    try {
      await _setUser(await ref.read(accountApiProvider).me());
    } on Object catch (e) {
      debugPrint('刷新账号信息失败: $e');
      // 刷新令牌被服务端拒绝时 onSessionExpired 已切换到未登录；其余失败（离线、服务端暂时不可用、
      // 响应格式异常）都使用缓存的账号信息继续使用
      if (state is SignedOut) return;
      if (cached != null) {
        state = SignedIn(cached);
      } else {
        await _signOutLocally();
      }
    }
  }

  User? _cachedUser() {
    final raw = ref.read(keyValueStoreProvider).getString(_userCacheKey);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<void> _setUser(User user) async {
    state = SignedIn(user);
    await ref
        .read(keyValueStoreProvider)
        .setString(_userCacheKey, jsonEncode(user.toJson()));
  }

  /// 保存会话并进入应用。
  Future<void> acceptSession(AuthSession session) async {
    await ref.read(apiClientProvider).saveTokens(session.tokens);
    // 实时通知据此忽略本设备产生的修改
    await ref
        .read(keyValueStoreProvider)
        .setString(deviceIdKey, session.deviceId);
    await _setUser(session.user);
  }

  /// 账号信息在其他页面更新后（改昵称、绑定手机号）同步到登录态。
  Future<void> updateUser(User user) => _setUser(user);

  Future<void> loginWithPassword(String username, String password) async =>
      acceptSession(
        await ref.read(authApiProvider).loginWithPassword(username, password),
      );

  Future<void> register({
    required String username,
    required String password,
    String nickname = '',
  }) async => acceptSession(
    await ref
        .read(authApiProvider)
        .register(username: username, password: password, nickname: nickname),
  );

  /// 短信登录；需要完善注册时返回注册凭证，由页面跳转到完善注册。
  Future<SmsRegistrationRequired?> loginWithSms(
    String phone,
    String code,
  ) async {
    final result = await ref.read(authApiProvider).loginWithSms(phone, code);
    switch (result) {
      case SmsAuthenticated(:final session):
        await acceptSession(session);
        return null;
      case SmsRegistrationRequired():
        return result;
    }
  }

  Future<void> completeSmsRegistration({
    required String ticket,
    required String username,
    required String password,
    String nickname = '',
  }) async => acceptSession(
    await ref
        .read(authApiProvider)
        .completeSmsRegistration(
          ticket: ticket,
          username: username,
          password: password,
          nickname: nickname,
        ),
  );

  /// 退出登录：通知服务端注销本设备；网络失败也清除本地登录态。
  Future<void> logout() async {
    try {
      await ref.read(authApiProvider).logout();
    } on ApiException catch (e) {
      debugPrint('退出登录请求失败，仅清除本地登录态: $e');
    }
    await _signOutLocally();
  }

  /// 账号已注销或会话失效：只清除本地状态。
  Future<void> signOutLocally({String? reason}) =>
      _signOutLocally(reason: reason);

  Future<void> _signOutLocally({String? reason}) async {
    await ref.read(apiClientProvider).clearTokens();
    final store = ref.read(keyValueStoreProvider);
    await store.remove(_userCacheKey);
    await store.remove(deviceIdKey);
    // 未同步的设置属于上一个账号，不能在下一个账号登录时被上传
    await store.remove(settingsDirtyKey);
    state = SignedOut(reason: reason);
  }
}
