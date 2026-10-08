// 接口数据模型，字段与 server/api/openapi.yaml 一致（由 test/core/api/contract_test.dart 校验）。

import 'package:flutter/foundation.dart';

T _req<T>(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! T) {
    throw FormatException('字段 $key 缺失或类型错误: $v');
  }
  return v;
}

DateTime _time(Map<String, dynamic> j, String key) =>
    DateTime.parse(_req<String>(j, key));

/// 当前账号。
@immutable
class User {
  const User({
    required this.id,
    required this.username,
    required this.nickname,
    required this.hasPhone,
    required this.createdAt,
    this.phoneMasked,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: _req(j, 'id'),
    username: _req(j, 'username'),
    nickname: _req(j, 'nickname'),
    hasPhone: _req(j, 'hasPhone'),
    phoneMasked: j['phoneMasked'] as String?,
    createdAt: _time(j, 'createdAt'),
  );

  final String id;
  final String username;
  final String nickname;
  final bool hasPhone;
  final String? phoneMasked;
  final DateTime createdAt;

  /// 界面上显示的名字：有昵称用昵称，否则用用户名。
  String get displayName => nickname.isNotEmpty ? nickname : username;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'nickname': nickname,
    'hasPhone': hasPhone,
    if (phoneMasked != null) 'phoneMasked': phoneMasked,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

/// 令牌对。
@immutable
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
    accessToken: _req(j, 'accessToken'),
    accessExpiresAt: _time(j, 'accessExpiresAt'),
    refreshToken: _req(j, 'refreshToken'),
    refreshExpiresAt: _time(j, 'refreshExpiresAt'),
  );

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'accessExpiresAt': accessExpiresAt.toUtc().toIso8601String(),
    'refreshToken': refreshToken,
    'refreshExpiresAt': refreshExpiresAt.toUtc().toIso8601String(),
  };
}

/// 登录会话。
@immutable
class AuthSession {
  const AuthSession({
    required this.user,
    required this.tokens,
    required this.deviceId,
  });

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
    user: User.fromJson(_req(j, 'user')),
    tokens: TokenPair.fromJson(_req(j, 'tokens')),
    deviceId: _req(j, 'deviceId'),
  );

  final User user;
  final TokenPair tokens;
  final String deviceId;
}

/// 短信登录结果：已登录，或需要完善注册。
sealed class SmsLoginResult {
  const SmsLoginResult();

  factory SmsLoginResult.fromJson(Map<String, dynamic> j) =>
      switch (_req<String>(j, 'status')) {
        'authenticated' => SmsAuthenticated(
          AuthSession.fromJson(_req(j, 'session')),
        ),
        'registration_required' => SmsRegistrationRequired(
          ticket: _req(j, 'registrationTicket'),
          phoneMasked: _req(j, 'phoneMasked'),
        ),
        final s => throw FormatException('未知的短信登录状态: $s'),
      };
}

class SmsAuthenticated extends SmsLoginResult {
  const SmsAuthenticated(this.session);

  final AuthSession session;
}

class SmsRegistrationRequired extends SmsLoginResult {
  const SmsRegistrationRequired({
    required this.ticket,
    required this.phoneMasked,
  });

  final String ticket;
  final String phoneMasked;
}

/// 已登录设备。
@immutable
class Device {
  const Device({
    required this.id,
    required this.platform,
    required this.model,
    required this.osVersion,
    required this.appVersion,
    required this.lastActiveAt,
    required this.createdAt,
    required this.current,
  });

  factory Device.fromJson(Map<String, dynamic> j) => Device(
    id: _req(j, 'id'),
    platform: _req(j, 'platform'),
    model: _req(j, 'model'),
    osVersion: _req(j, 'osVersion'),
    appVersion: _req(j, 'appVersion'),
    lastActiveAt: _time(j, 'lastActiveAt'),
    createdAt: _time(j, 'createdAt'),
    current: _req(j, 'current'),
  );

  final String id;
  final String platform;
  final String model;
  final String osVersion;
  final String appVersion;
  final DateTime lastActiveAt;
  final DateTime createdAt;
  final bool current;
}

/// 用户设置（多设备同步）。
@immutable
class UserSettings {
  const UserSettings({
    this.themeMode = 'system',
    this.fontScale = 1.0,
    this.defaultReminders = const [0],
    this.weekStart = 1,
  });

  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
    themeMode: _req(j, 'themeMode'),
    fontScale: _req<num>(j, 'fontScale').toDouble(),
    defaultReminders: List<int>.unmodifiable(
      _req<List<dynamic>>(j, 'defaultReminders').map((e) => (e as num).toInt()),
    ),
    weekStart: _req<num>(j, 'weekStart').toInt(),
  );

  /// system / light / dark
  final String themeMode;
  final double fontScale;

  /// 新建备忘录时默认的提前提醒（分钟）。
  final List<int> defaultReminders;

  /// 1 = 周一，7 = 周日。
  final int weekStart;

  UserSettings copyWith({
    String? themeMode,
    double? fontScale,
    List<int>? defaultReminders,
    int? weekStart,
  }) => UserSettings(
    themeMode: themeMode ?? this.themeMode,
    fontScale: fontScale ?? this.fontScale,
    defaultReminders: defaultReminders ?? this.defaultReminders,
    weekStart: weekStart ?? this.weekStart,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'fontScale': fontScale,
    'defaultReminders': defaultReminders,
    'weekStart': weekStart,
  };

  @override
  bool operator ==(Object other) =>
      other is UserSettings &&
      other.themeMode == themeMode &&
      other.fontScale == fontScale &&
      listEquals(other.defaultReminders, defaultReminders) &&
      other.weekStart == weekStart;

  @override
  int get hashCode => Object.hash(
    themeMode,
    fontScale,
    Object.hashAll(defaultReminders),
    weekStart,
  );
}
