import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/api/endpoints.dart';
import '../../shared/ui/api_form.dart';
import '../../shared/ui/jk_button.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_form.dart';
import '../../shared/ui/jk_page.dart';
import '../auth/auth_controller.dart';

/// 身份验证方式：当前密码，或当前绑定手机号的验证码。
enum _Verify { password, sms }

/// 修改密码。
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage>
    with ApiFormState {
  _Verify _verify = _Verify.password;
  final _current = TextEditingController();
  final _code = TextEditingController();
  final _next = TextEditingController();

  @override
  void dispose() {
    for (final c in [_current, _code, _next]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await submit(
      () => ref
          .read(accountApiProvider)
          .changePassword(
            newPassword: _next.text,
            currentPassword: _verify == _Verify.password ? _current.text : null,
            smsCode: _verify == _Verify.sms ? _code.text : null,
          ),
    );
    if (ok && mounted) {
      showJkToast(context, '密码已修改，其他设备需重新登录', kind: JkToastKind.success);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final hasPhone = auth is SignedIn && auth.user.hasPhone;
    return JkPage(
      title: '修改密码',
      children: [
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasPhone) ...[
                SegmentedButton<_Verify>(
                  segments: const [
                    ButtonSegment(
                      value: _Verify.password,
                      label: Text('当前密码验证'),
                    ),
                    ButtonSegment(value: _Verify.sms, label: Text('手机验证码')),
                  ],
                  selected: {_verify},
                  onSelectionChanged: (s) => setState(() => _verify = s.first),
                ),
                const SizedBox(height: 24),
              ],
              if (_verify == _Verify.password)
                JkPasswordField(
                  label: '当前密码',
                  controller: _current,
                  errorText: errorOf('currentPassword'),
                  validator: (v) => JkValidators.required(v, '当前密码'),
                )
              else
                JkSmsCodeField(
                  label: '当前手机号验证码',
                  controller: _code,
                  errorText: errorOf('smsCode'),
                  validator: JkValidators.smsCode,
                  onSend: () => sendCode(
                    () => ref
                        .read(accountApiProvider)
                        .sendSms(SmsPurpose.verifyCurrent),
                  ),
                ),
              JkPasswordField(
                label: '新密码',
                controller: _next,
                hint: '8 位以上，包含字母和数字',
                errorText: errorOf('newPassword'),
                isNew: true,
                validator: JkValidators.password,
              ),
              JkButton(label: '确认修改', loading: busy, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }
}

/// 绑定或换绑手机号。
class PhonePage extends ConsumerStatefulWidget {
  const PhonePage({super.key});

  @override
  ConsumerState<PhonePage> createState() => _PhonePageState();
}

class _PhonePageState extends ConsumerState<PhonePage> with ApiFormState {
  final _password = TextEditingController();
  final _currentCode = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    for (final c in [_password, _currentCode, _phone, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(bool changing) async {
    final ok = await submit(() async {
      final user = await ref
          .read(accountApiProvider)
          .bindPhone(
            phone: JkValidators.normalizePhone(_phone.text),
            code: _code.text,
            currentPassword: _password.text,
            currentCode: changing ? _currentCode.text : null,
          );
      await ref.read(authControllerProvider.notifier).updateUser(user);
    });
    if (ok && mounted) {
      showJkToast(
        context,
        changing ? '手机号已换绑' : '手机号已绑定',
        kind: JkToastKind.success,
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final current = auth is SignedIn ? auth.user.phoneMasked : null;
    final changing = current != null;
    return JkPage(
      title: changing ? '换绑手机号' : '绑定手机号',
      children: [
        Text(
          changing
              ? '当前绑定 $current。换绑需要验证当前密码、当前手机号和新手机号。'
              : '绑定后可使用验证码登录、找回密码。一个手机号只能绑定一个账号。',
          style: TextStyle(color: context.jkColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JkPasswordField(
                label: '当前密码',
                controller: _password,
                errorText: errorOf('currentPassword'),
                validator: (v) => JkValidators.required(v, '当前密码'),
              ),
              if (changing)
                JkSmsCodeField(
                  label: '当前手机号验证码',
                  controller: _currentCode,
                  errorText: errorOf('currentCode'),
                  validator: JkValidators.smsCode,
                  onSend: () => sendCode(
                    () => ref
                        .read(accountApiProvider)
                        .sendSms(SmsPurpose.verifyCurrent),
                  ),
                ),
              JkTextField(
                label: changing ? '新手机号' : '手机号',
                controller: _phone,
                keyboardType: TextInputType.phone,
                errorText: errorOf('phone'),
                validator: JkValidators.phone,
              ),
              JkSmsCodeField(
                label: changing ? '新手机号验证码' : '验证码',
                controller: _code,
                errorText: errorOf('code'),
                validator: JkValidators.smsCode,
                onSend: () async {
                  if (JkValidators.phone(_phone.text) != null) {
                    setState(() => fieldErrors = {'phone': '请输入正确的中国大陆手机号'});
                    return null;
                  }
                  return sendCode(
                    () => ref
                        .read(accountApiProvider)
                        .sendSms(
                          SmsPurpose.bindPhone,
                          phone: JkValidators.normalizePhone(_phone.text),
                        ),
                  );
                },
              ),
              JkButton(
                label: changing ? '确认换绑' : '确认绑定',
                loading: busy,
                onPressed: () => _submit(changing),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 注销账号：永久删除账号及全部数据。
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage>
    with ApiFormState {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final confirmed = await showJkConfirm(
      context,
      title: '确认注销账号？',
      message: '账号及全部工作日志、笔记、备忘录、账目将被永久删除，无法恢复。',
      confirmLabel: '永久注销',
      destructive: true,
    );
    if (!confirmed) return;
    final ok = await submit(
      () => ref
          .read(accountApiProvider)
          .deleteAccount(currentPassword: _password.text),
      validate: false,
    );
    if (ok) {
      await ref
          .read(authControllerProvider.notifier)
          .signOutLocally(reason: '账号已注销');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return JkPage(
      title: '注销账号',
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '注销后，账号及其全部数据（工作日志、笔记、备忘录、账目、附件）都会被永久删除，所有设备立即下线，且无法恢复。'
            '如需保留数据，请先导出。',
            style: TextStyle(color: c.onErrorContainer),
          ),
        ),
        const SizedBox(height: 24),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JkPasswordField(
                label: '当前密码',
                controller: _password,
                errorText: errorOf('currentPassword'),
                validator: (v) => JkValidators.required(v, '当前密码'),
              ),
              JkButton(
                key: const Key('delete-submit'),
                label: '注销账号',
                variant: JkButtonVariant.danger,
                loading: busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
