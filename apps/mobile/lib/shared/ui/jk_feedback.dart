import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';

/// 轻提示类型。
enum JkToastKind { info, success, error }

/// 底部轻提示（SnackBar），按类型使用状态色。
void showJkToast(
  BuildContext context,
  String message, {
  JkToastKind kind = JkToastKind.info,
}) {
  final c = context.jkColors;
  final (bg, fg, icon) = switch (kind) {
    JkToastKind.success => (
      c.successContainer,
      c.onSuccessContainer,
      Icons.check_circle_outline,
    ),
    JkToastKind.error => (
      c.errorContainer,
      c.onErrorContainer,
      Icons.error_outline,
    ),
    JkToastKind.info => (
      c.infoContainer,
      c.onInfoContainer,
      Icons.info_outline,
    ),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        ),
        content: Row(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: JkTokens.spacingSm),
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ),
    );
}

/// 确认弹窗。[destructive] 为 true 时确认按钮使用危险色。返回用户是否确认。
Future<bool> showJkConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final c = context.jkColors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: c.error,
                  foregroundColor: c.onError,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
