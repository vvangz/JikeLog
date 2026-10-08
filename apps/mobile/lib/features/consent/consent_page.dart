import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_button.dart';
import '../../shared/ui/jk_logo.dart';
import '../../shared/ui/jk_page.dart';
import 'consent_controller.dart';
import 'policy_text.dart';

/// 首次启动的隐私政策与用户协议确认。同意前不收集任何信息、不初始化第三方 SDK。
class ConsentPage extends ConsumerWidget {
  const ConsentPage({super.key});

  void _showPolicy(BuildContext context, String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
            JkTokens.spacingXl,
            0,
            JkTokens.spacingXl,
            JkTokens.spacingXl,
          ),
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: JkTokens.spacingLg),
            Text(
              body,
              style: const TextStyle(height: JkTokens.fontLineHeightRelaxed),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: JkFillScroll(
              padding: const EdgeInsets.all(JkTokens.spacingXl),
              child: Column(
                children: [
                  const Spacer(),
                  const JkLogo(size: 64),
                  const SizedBox(height: JkTokens.spacingLg),
                  Text('欢迎使用即刻日志', style: text.headlineSmall),
                  const SizedBox(height: JkTokens.spacingLg),
                  Text(
                    consentSummary,
                    style: text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: JkTokens.spacingMd),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _showPolicy(context, '隐私政策', privacyPolicy),
                        child: const Text('《隐私政策》'),
                      ),
                      TextButton(
                        onPressed: () =>
                            _showPolicy(context, '用户协议', userAgreement),
                        child: const Text('《用户协议》'),
                      ),
                    ],
                  ),
                  const Spacer(),
                  JkButton(
                    key: const Key('consent-accept'),
                    label: '同意并继续',
                    onPressed: () =>
                        ref.read(consentControllerProvider.notifier).accept(),
                  ),
                  const SizedBox(height: JkTokens.spacingSm),
                  JkButton(
                    label: '不同意并退出',
                    variant: JkButtonVariant.text,
                    onPressed: () => SystemNavigator.pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
