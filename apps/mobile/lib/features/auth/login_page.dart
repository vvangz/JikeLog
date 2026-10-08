import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/endpoints.dart';
import '../../shared/ui/api_form.dart';
import '../../shared/ui/jk_button.dart';
import '../../shared/ui/jk_form.dart';
import 'auth_controller.dart';
import 'auth_scaffold.dart';

/// 登录页：用户名密码登录与手机验证码登录两种方式。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

enum _Mode { password, sms }

class _LoginPageState extends ConsumerState<LoginPage> with ApiFormState {
  _Mode _mode = _Mode.password;
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    for (final c in [_username, _password, _phone, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider.notifier);
    if (_mode == _Mode.password) {
      await submit(
        () => auth.loginWithPassword(_username.text.trim(), _password.text),
      );
      return;
    }
    final phone = JkValidators.normalizePhone(_phone.text);
    await submit(() async {
      final pending = await auth.loginWithSms(phone, _code.text);
      if (pending != null && mounted) {
        unawaited(context.push('/register/complete', extra: pending));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final reason = state is SignedOut ? state.reason : null;
    return AuthScaffold(
      title: '登录即刻日志',
      subtitle: reason ?? '高效记录工作、笔记、备忘与账目',
      child: Form(
        key: formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(value: _Mode.password, label: Text('密码登录')),
                  ButtonSegment(value: _Mode.sms, label: Text('验证码登录')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  fieldErrors = const {};
                }),
              ),
              const SizedBox(height: 24),
              if (_mode == _Mode.password)
                ..._passwordFields()
              else
                ..._smsFields(),
              JkButton(
                key: const Key('login-submit'),
                label: '登录',
                loading: busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('注册新账号'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/password/reset'),
                    child: const Text('忘记密码'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _passwordFields() => [
    JkTextField(
      fieldKey: const Key('login-username'),
      label: '用户名',
      controller: _username,
      errorText: errorOf('username'),
      autofillHints: const [AutofillHints.username],
      validator: (v) => JkValidators.required(v, '用户名'),
    ),
    JkPasswordField(
      fieldKey: const Key('login-password'),
      controller: _password,
      errorText: errorOf('password'),
      validator: (v) => JkValidators.required(v, '密码'),
      onSubmitted: (_) => _submit(),
    ),
  ];

  List<Widget> _smsFields() => [
    JkTextField(
      fieldKey: const Key('login-phone'),
      label: '手机号',
      controller: _phone,
      keyboardType: TextInputType.phone,
      errorText: errorOf('phone'),
      autofillHints: const [AutofillHints.telephoneNumber],
      validator: JkValidators.phone,
    ),
    JkSmsCodeField(
      fieldKey: const Key('login-code'),
      controller: _code,
      errorText: errorOf('code'),
      validator: JkValidators.smsCode,
      onSend: () async {
        final err = JkValidators.phone(_phone.text);
        if (err != null) {
          setState(() => fieldErrors = {'phone': err});
          return null;
        }
        setState(() => fieldErrors = const {});
        return sendCode(
          () => ref
              .read(authApiProvider)
              .sendSms(
                JkValidators.normalizePhone(_phone.text),
                SmsPurpose.login,
              ),
        );
      },
    ),
    const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Text('未注册的手机号验证后将引导你设置用户名和密码。'),
    ),
  ];
}
