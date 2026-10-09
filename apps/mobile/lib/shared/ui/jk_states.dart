import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import 'jk_button.dart';

/// 空状态：图标 + 标题 + 说明 + 可选操作，居中显示。
class JkEmptyState extends StatelessWidget {
  const JkEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final Widget icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(JkTokens.spacingXl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: IconTheme(
                  data: IconThemeData(color: c.onPrimaryContainer, size: 32),
                  child: icon,
                ),
              ),
              const SizedBox(height: JkTokens.spacingLg),
              Text(title, style: text.titleLarge, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: JkTokens.spacingSm),
                Text(
                  message!,
                  style: text.bodyMedium?.copyWith(color: c.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: JkTokens.spacingXl),
                JkButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  expand: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 错误状态：说明出了什么问题，并提供重试。
class JkErrorState extends StatelessWidget {
  const JkErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return JkEmptyState(
      icon: Icon(Icons.cloud_off_outlined, color: c.onErrorContainer),
      title: '加载失败',
      message: message,
      actionLabel: '重试',
      onAction: onRetry,
    );
  }
}

/// 骨架屏：加载中显示占位条，并带缓慢的明暗呼吸动画（系统开启"减少动态效果"时静止）。
class JkSkeleton extends StatefulWidget {
  const JkSkeleton({super.key, this.lines = 3});

  final int lines;

  @override
  State<JkSkeleton> createState() => _JkSkeletonState();
}

class _JkSkeletonState extends State<JkSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.45,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _ctrl.value = 0.7;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Semantics(
      label: '加载中',
      child: FadeTransition(
        opacity: _ctrl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.lines; i++)
              Container(
                margin: const EdgeInsets.symmetric(
                  vertical: JkTokens.spacingSm,
                ),
                height: i == 0 ? 20 : 14,
                width: i == widget.lines - 1 ? 160 : double.infinity,
                decoration: BoxDecoration(
                  color: c.surfaceVariant,
                  borderRadius: BorderRadius.circular(JkTokens.radiusSm),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
