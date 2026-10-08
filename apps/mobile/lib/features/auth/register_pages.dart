import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/models.dart';
import '../../shared/ui/api_form.dart';
import '../../shared/ui/jk_button.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_form.dart';
import 'auth_controller.dart';
import 'auth_scaffold.dart';

/// 用户名、昵称、密码、确认密码四个字段，注册与完善注册共用。
class _AccountFields extends StatelessWidget {
  const _AccountFields({
    required this.username,
    required this.nickname,
    required this.password,
    required this.confirm,
    required this.errorOf,
  });

  final TextEditingController username;
  final TextEditingController nickname;
  final TextEditingController password;
  final TextEditingController confirm;
  final String? Function(String) errorOf;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      JkTextField(
        fieldKey: const Key('reg-username'),
        label: '用户名',
        hint: '4–20 位，以字母开头',
        controller: username,
        errorText: errorOf('username'),
        maxLength: 20,
        autofillHints: const [AutofillHints.newUsername],
        validator: JkValidators.username,
      ),
      JkTextField(
        label: '昵称（可选）',
        controller: nickname,
        errorText: errorOf('nickname'),
        maxLength: 20,
        autofillHints: const [AutofillHints.nickname],
        validator: JkValidators.nickname,
      ),
      JkPasswordField(
        fieldKey: const Key('reg-password'),
        controller: password,
        hint: '8 位以上，包含字母和数字',
        errorText: errorOf('password'),
        isNew: true,
        validator: JkValidators.password,
      ),
      JkPasswordField(
        fieldKey: const Key('reg-confirm'),
        label: '确认密码',
        controller: confirm,
        isNew: true,
        validator: (v) => v == password.text ? null : '两次输入的密码不一致',
      ),
    ],
  );
}

mixin _AccountControllers<T extends StatefulWidget> on State<T> {
  final username = TextEditingController();
  final nickname = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [username, nickname, password, confirm]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// 用户名密码注册。
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage>
    with ApiFormState, _AccountControllers {
  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: '注册账号',
    subtitle: '注册后可在"帐号"中绑定手机号，用于验证码登录和找回密码',
    showBack: true,
    child: Form(
      key: formKey,
      child: AutofillGroup(
        child: Column(
          children: [
            _AccountFields(
              username: username,
              nickname: nickname,
              password: password,
              confirm: confirm,
              errorOf: errorOf,
            ),
            JkButton(
              key: const Key('register-submit'),
              label: '注册并登录',
              loading: busy,
              onPressed: () => submit(
                () => ref
                    .read(authControllerProvider.notifier)
                    .register(
                      username: username.text.trim(),
                      password: password.text,
                      nickname: nickname.text.trim(),
                    ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 完善注册：短信登录的新手机号设置用户名和密码，账号自动绑定该手机号。
class CompleteRegistrationPage extends ConsumerStatefulWidget {
  const CompleteRegistrationPage({super.key, required this.pending});

  final SmsRegistrationRequired pending;

  @override
  ConsumerState<CompleteRegistrationPage> createState() =>
      _CompleteRegistrationPageState();
}

class _CompleteRegistrationPageState
    extends ConsumerState<CompleteRegistrationPage>
    with ApiFormState, _AccountControllers {
  Future<void> _submit() async {
    final ok = await submit(
      () => ref
          .read(authControllerProvider.notifier)
          .completeSmsRegistration(
            ticket: widget.pending.ticket,
            username: username.text.trim(),
            password: password.text,
            nickname: nickname.text.trim(),
          ),
    );
    // 凭证过期（10 分钟）或已使用：回到登录页重新获取验证码
    if (!ok && mounted && lastError?.code == ApiErrorCode.ticketInvalid) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: '完善注册',
    subtitle: '手机号 ${widget.pending.phoneMasked} 尚未注册，设置用户名和密码后即可使用',
    showBack: true,
    child: Form(
      key: formKey,
      child: AutofillGroup(
        child: Column(
          children: [
            _AccountFields(
              username: username,
              nickname: nickname,
              password: password,
              confirm: confirm,
              errorOf: errorOf,
            ),
            JkButton(
              key: const Key('complete-submit'),
              label: '完成注册',
              loading: busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    ),
  );
}

/// 通过手机号找回密码。
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage>
    with ApiFormState {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    for (final c in [_phone, _code, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await submit(
      () => ref
          .read(authApiProvider)
          .resetPassword(
            JkValidators.normalizePhone(_phone.text),
            _code.text,
            _password.text,
          ),
    );
    if (ok && mounted) {
      showJkToast(context, '密码已重置，请使用新密码登录', kind: JkToastKind.success);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: '找回密码',
    subtitle: '通过已绑定的手机号重置密码，重置后所有设备需重新登录',
    showBack: true,
    child: Form(
      key: formKey,
      child: Column(
        children: [
          JkTextField(
            label: '手机号',
            controller: _phone,
            keyboardType: TextInputType.phone,
            errorText: errorOf('phone'),
            validator: JkValidators.phone,
          ),
          JkSmsCodeField(
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
                    .read(authApiProvider)
                    .sendSms(
                      JkValidators.normalizePhone(_phone.text),
                      SmsPurpose.resetPassword,
                    ),
              );
            },
          ),
          JkPasswordField(
            label: '新密码',
            controller: _password,
            errorText: errorOf('newPassword'),
            isNew: true,
            validator: JkValidators.password,
          ),
          JkButton(label: '重置密码', loading: busy, onPressed: _submit),
        ],
      ),
    ),
  );
}
