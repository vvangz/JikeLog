import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/jk_tokens.g.dart';

/// 表单字段：标签在输入框上方，错误信息（含服务端字段级错误）显示在下方。
class JkTextField extends StatelessWidget {
  const JkTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.errorText,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.maxLength,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.suffix,
    this.onSubmitted,
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  /// 服务端返回的错误，优先于本地校验显示。
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: JkTokens.spacingLg),
      child: TextFormField(
        key: fieldKey,
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscure,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          errorMaxLines: 2,
          counterText: '',
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(JkTokens.radiusMd),
          ),
        ),
      ),
    );
  }
}

/// 密码字段：带显示/隐藏切换。
class JkPasswordField extends StatefulWidget {
  const JkPasswordField({
    super.key,
    required this.controller,
    this.label = '密码',
    this.hint,
    this.errorText,
    this.validator,
    this.isNew = false,
    this.onSubmitted,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final FormFieldValidator<String>? validator;

  /// 是否为新设置的密码（影响系统自动填充提示）。
  final bool isNew;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  @override
  State<JkPasswordField> createState() => _JkPasswordFieldState();
}

class _JkPasswordFieldState extends State<JkPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => JkTextField(
    fieldKey: widget.fieldKey,
    label: widget.label,
    hint: widget.hint,
    controller: widget.controller,
    errorText: widget.errorText,
    validator: widget.validator,
    obscure: !_visible,
    maxLength: 128,
    onSubmitted: widget.onSubmitted,
    autofillHints: [
      widget.isNew ? AutofillHints.newPassword : AutofillHints.password,
    ],
    suffix: IconButton(
      tooltip: _visible ? '隐藏密码' : '显示密码',
      icon: Icon(
        _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      onPressed: () => setState(() => _visible = !_visible),
    ),
  );
}

/// 验证码字段：右侧"获取验证码"按钮，发送成功后倒计时。
class JkSmsCodeField extends StatefulWidget {
  const JkSmsCodeField({
    super.key,
    required this.controller,
    required this.onSend,
    this.label = '验证码',
    this.errorText,
    this.validator,
    this.fieldKey,
  });

  final TextEditingController controller;

  /// 发送验证码，返回冷却秒数；返回 null 表示发送失败（由调用方提示原因）。
  final Future<int?> Function() onSend;
  final String label;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final Key? fieldKey;

  @override
  State<JkSmsCodeField> createState() => _JkSmsCodeFieldState();
}

class _JkSmsCodeFieldState extends State<JkSmsCodeField> {
  Timer? _timer;
  int _remaining = 0;
  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    int? cooldown;
    try {
      cooldown = await widget.onSend();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _remaining = cooldown ?? 0;
    });
    if (_remaining > 0) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _remaining--);
        if (_remaining <= 0) t.cancel();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _remaining > 0 ? '$_remaining 秒后重发' : '获取验证码';
    return JkTextField(
      fieldKey: widget.fieldKey,
      label: widget.label,
      controller: widget.controller,
      errorText: widget.errorText,
      validator: widget.validator,
      keyboardType: TextInputType.number,
      maxLength: 6,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      suffix: Padding(
        padding: const EdgeInsets.only(right: JkTokens.spacingXs),
        child: TextButton(
          onPressed: _sending || _remaining > 0 ? null : _send,
          child: _sending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }
}

/// 本地校验规则，与服务端一致（server/internal/auth/validate.go）。
abstract final class JkValidators {
  static final _username = RegExp(r'^[A-Za-z][A-Za-z0-9_]{3,19}$');
  static final _phone = RegExp(r'^1[3-9]\d{9}$');
  static final _code = RegExp(r'^\d{6}$');

  static String? username(String? v) =>
      _username.hasMatch(v ?? '') ? null : '4–20 位，以字母开头，只能包含字母、数字和下划线';

  static String? password(String? v) {
    final s = v ?? '';
    if (s.runes.length < 8 || s.runes.length > 128) return '密码长度为 8–128 位';
    if (!s.contains(RegExp(r'\p{L}', unicode: true)) ||
        !s.contains(RegExp(r'\d'))) {
      return '密码需同时包含字母和数字';
    }
    return null;
  }

  static String? required(String? v, String what) =>
      (v ?? '').trim().isEmpty ? '请输入$what' : null;

  /// 去掉空格、连字符和 +86 前缀后的 11 位手机号。
  static String normalizePhone(String v) =>
      v.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+86'), '');

  static String? phone(String? v) =>
      _phone.hasMatch(normalizePhone(v ?? '')) ? null : '请输入正确的中国大陆手机号';

  static String? smsCode(String? v) =>
      _code.hasMatch(v ?? '') ? null : '验证码为 6 位数字';

  static String? nickname(String? v) =>
      (v ?? '').trim().runes.length > 20 ? '昵称最多 20 个字符' : null;
}
