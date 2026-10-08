import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import 'jk_feedback.dart';

/// 表单页面的公共提交逻辑：提交中禁用按钮，服务端字段错误显示到对应输入框，其他错误以轻提示展示。
mixin ApiFormState<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  Map<String, String> fieldErrors = const {};

  /// 最近一次提交失败的错误，便于按错误码做特殊处理。
  ApiException? lastError;

  /// 服务端对某字段的错误。
  String? errorOf(String field) => fieldErrors[field];

  /// 本地校验通过后执行 [action]，返回是否成功。
  Future<bool> submit(
    Future<void> Function() action, {
    bool validate = true,
  }) async {
    if (busy) return false;
    if (validate && !(formKey.currentState?.validate() ?? true)) return false;
    setState(() {
      busy = true;
      fieldErrors = const {};
      lastError = null;
    });
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      lastError = e;
      if (!mounted) return false;
      setState(() => fieldErrors = e.fields);
      if (e.fields.isEmpty) {
        showJkToast(context, e.message, kind: JkToastKind.error);
      }
      return false;
    } on Object catch (e) {
      // 响应格式异常等非接口错误：给出通用提示，不让异常逃逸
      debugPrint('提交失败: $e');
      lastError = const ApiException(
        code: ApiErrorCode.unexpected,
        message: '出现异常，请稍后重试',
      );
      if (mounted) showJkToast(context, '出现异常，请稍后重试', kind: JkToastKind.error);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 发送验证码的公共处理：成功返回冷却秒数，失败提示原因并返回 null（被限流时仍按服务端给出的剩余时间倒计时）。
  Future<int?> sendCode(Future<int> Function() send) async {
    try {
      final cooldown = await send();
      if (mounted) showJkToast(context, '验证码已发送', kind: JkToastKind.success);
      return cooldown;
    } on ApiException catch (e) {
      if (mounted) {
        showJkToast(
          context,
          e.fields.values.firstOrNull ?? e.message,
          kind: JkToastKind.error,
        );
      }
      return e.retryAfter?.inSeconds;
    } on Object catch (e) {
      debugPrint('发送验证码失败: $e');
      if (mounted) showJkToast(context, '发送失败，请稍后重试', kind: JkToastKind.error);
      return null;
    }
  }
}
