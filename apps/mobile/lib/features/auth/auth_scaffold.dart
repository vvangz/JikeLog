import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_logo.dart';

/// 登录、注册等页面的公共布局：标志 + 标题 + 居中的表单区域。
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(JkTokens.spacingXl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!showBack) ...[
                    const Center(child: JkLogo(size: 56)),
                    const SizedBox(height: JkTokens.spacingLg),
                  ],
                  Text(
                    title,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: JkTokens.spacingSm),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: context.jkColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: JkTokens.spacingXl),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
