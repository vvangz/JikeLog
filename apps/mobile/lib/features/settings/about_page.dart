import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../app/version.dart';
import '../../shared/ui/jk_logo.dart';
import '../../shared/ui/jk_page.dart';
import '../consent/policy_text.dart';
import '../update/update_dialog.dart';
import '../update/update_service.dart';

/// 关于：版本、应用内检查更新、字体说明、隐私政策与开源许可。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  void _show(BuildContext context, String title, String body) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => JkPage(
            title: title,
            children: [Text(body, style: const TextStyle(height: 1.7))],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;
    final update = ref.watch(appUpdateControllerProvider);
    return JkPage(
      title: '关于',
      children: [
        const SizedBox(height: JkTokens.spacingXl),
        const Center(child: JkLogo(size: 64)),
        const SizedBox(height: JkTokens.spacingMd),
        Center(child: Text('即刻日志', style: text.headlineSmall)),
        Center(
          child: Text(
            '版本 $appVersion',
            style: text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ),
        const SizedBox(height: JkTokens.spacingXl),
        JkCard(
          children: [
            ListTile(
              key: const Key('about-check-update'),
              title: const Text('检查更新'),
              subtitle: update.candidate != null
                  ? Text(
                      '发现新版本 v${update.candidate!.version}',
                      style: TextStyle(color: c.primary),
                    )
                  : null,
              trailing: update.phase == UpdatePhase.checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: update.phase == UpdatePhase.checking
                  ? null
                  : () => triggerManualUpdateCheck(context, ref),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('隐私政策'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _show(context, '隐私政策', privacyPolicy),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('用户协议'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _show(context, '用户协议', userAgreement),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('开源许可'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: '即刻日志',
                applicationVersion: appVersion,
              ),
            ),
          ],
        ),
        const JkSectionTitle('字体'),
        Text(
          '英文与数字使用 Space Grotesk（SIL Open Font License 1.1）；'
          '中文使用 MiSans，由小米公司提供并授权免费商用。',
          style: text.bodyMedium?.copyWith(color: c.textSecondary, height: 1.7),
        ),
      ],
    );
  }
}
