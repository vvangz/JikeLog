import '../device/device_identity.dart';
import 'api_client.dart';
import 'models.dart';

/// 验证码用途。
enum SmsPurpose {
  login('login'),
  resetPassword('reset_password'),
  bindPhone('bind_phone'),
  verifyCurrent('verify_current');

  const SmsPurpose(this.wire);

  final String wire;
}

/// 认证接口（/api/v1/auth/*）。
class AuthApi {
  const AuthApi(this._c, this._device);

  final ApiClient _c;
  final DeviceIdentity _device;

  Future<AuthSession> register({
    required String username,
    required String password,
    String nickname = '',
  }) async => AuthSession.fromJson(
    await _c.post('/api/v1/auth/register', {
      'username': username,
      'password': password,
      if (nickname.isNotEmpty) 'nickname': nickname,
      'device': _device.toJson(),
    }) as Map<String, dynamic>,
  );

  Future<AuthSession> loginWithPassword(
    String username,
    String password,
  ) async => AuthSession.fromJson(
    await _c.post('/api/v1/auth/login/password', {
      'username': username,
      'password': password,
      'device': _device.toJson(),
    }) as Map<String, dynamic>,
  );

  /// 发送登录或找回密码验证码，返回冷却秒数。
  Future<int> sendSms(String phone, SmsPurpose purpose) async {
    final data = await _c.post('/api/v1/auth/sms/send', {
      'phone': phone,
      'purpose': purpose.wire,
    }) as Map<String, dynamic>;
    return (data['cooldownSeconds'] as num).toInt();
  }

  Future<SmsLoginResult> loginWithSms(String phone, String code) async =>
      SmsLoginResult.fromJson(
        await _c.post('/api/v1/auth/login/sms', {
          'phone': phone,
          'code': code,
          'device': _device.toJson(),
        }) as Map<String, dynamic>,
      );

  Future<AuthSession> completeSmsRegistration({
    required String ticket,
    required String username,
    required String password,
    String nickname = '',
  }) async => AuthSession.fromJson(
    await _c.post('/api/v1/auth/register/sms', {
      'registrationTicket': ticket,
      'username': username,
      'password': password,
      if (nickname.isNotEmpty) 'nickname': nickname,
      'device': _device.toJson(),
    }) as Map<String, dynamic>,
  );

  Future<void> resetPassword(String phone, String code, String newPassword) =>
      _c.post('/api/v1/auth/password/reset', {
        'phone': phone,
        'code': code,
        'newPassword': newPassword,
      });

  Future<void> logout() => _c.post('/api/v1/auth/logout');
}

/// 当前账号接口（/api/v1/me/*）。
class AccountApi {
  const AccountApi(this._c);

  final ApiClient _c;

  Future<User> me() async =>
      User.fromJson(await _c.get('/api/v1/me') as Map<String, dynamic>);

  Future<User> updateNickname(String nickname) async => User.fromJson(
    await _c.patch('/api/v1/me', {'nickname': nickname})
        as Map<String, dynamic>,
  );

  /// 发送绑定新号码（[phone] 必填）或验证当前号码的验证码，返回冷却秒数。
  Future<int> sendSms(SmsPurpose purpose, {String? phone}) async {
    final data = await _c.post('/api/v1/me/sms/send', {
      'purpose': purpose.wire,
      'phone': ?phone,
    }) as Map<String, dynamic>;
    return (data['cooldownSeconds'] as num).toInt();
  }

  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
    String? smsCode,
  }) => _c.put('/api/v1/me/password', {
    'newPassword': newPassword,
    'currentPassword': ?currentPassword,
    'smsCode': ?smsCode,
  });

  /// 绑定或换绑手机号：需要当前密码；换绑时还需当前号码的验证码 [currentCode]。
  Future<User> bindPhone({
    required String phone,
    required String code,
    required String currentPassword,
    String? currentCode,
  }) async => User.fromJson(
    await _c.put('/api/v1/me/phone', {
      'phone': phone,
      'code': code,
      'currentPassword': currentPassword,
      'currentCode': ?currentCode,
    }) as Map<String, dynamic>,
  );

  Future<void> deleteAccount({String? currentPassword, String? smsCode}) =>
      _c.post('/api/v1/me/deletion', {
        'currentPassword': ?currentPassword,
        'smsCode': ?smsCode,
      });

  Future<List<Device>> devices() async {
    final list = await _c.get('/api/v1/me/devices') as List<dynamic>;
    return [for (final d in list) Device.fromJson(d as Map<String, dynamic>)];
  }

  Future<void> revokeDevice(String id) => _c.delete('/api/v1/me/devices/$id');

  Future<UserSettings> settings() async => UserSettings.fromJson(
    await _c.get('/api/v1/me/settings') as Map<String, dynamic>,
  );

  Future<UserSettings> saveSettings(UserSettings s) async =>
      UserSettings.fromJson(
        await _c.put('/api/v1/me/settings', s.toJson()) as Map<String, dynamic>,
      );
}
