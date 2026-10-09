import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';

/// 按钮样式：主要 / 次要 / 文字 / 危险。
enum JkButtonVariant { primary, secondary, text, danger }

/// 统一按钮：高度 48（满足触控目标），加载中显示进度并禁用点击，防止重复提交。
class JkButton extends StatelessWidget {
  const JkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = JkButtonVariant.primary,
    this.loading = false,
    this.expand = true,
  });

  final String label;

  /// 为 null 时按钮禁用。
  final VoidCallback? onPressed;
  final JkButtonVariant variant;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final onTap = loading ? null : onPressed;
    final fg = switch (variant) {
      JkButtonVariant.primary => c.onPrimary,
      JkButtonVariant.danger => c.onError,
      _ => c.primary,
    };
    final child = loading
        ? Semantics(
            label: '$label，处理中',
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
          )
        : Text(label);
    var style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(expand ? double.infinity : 64, 48),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(JkTokens.radiusMd)),
        ),
      ),
    );
    if (variant == JkButtonVariant.danger) {
      style = style.copyWith(
        backgroundColor: WidgetStatePropertyAll(c.error),
        foregroundColor: WidgetStatePropertyAll(c.onError),
      );
    }
    return switch (variant) {
      JkButtonVariant.primary || JkButtonVariant.danger => FilledButton(
        onPressed: onTap,
        style: style,
        child: child,
      ),
      JkButtonVariant.secondary => OutlinedButton(
        onPressed: onTap,
        style: style,
        child: child,
      ),
      JkButtonVariant.text => TextButton(
        onPressed: onTap,
        style: style,
        child: child,
      ),
    };
  }
}
