import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_form.dart';
import '../../shared/ui/jk_page.dart';
import '../auth/auth_controller.dart';

/// 帐号页：资料、安全（手机号、密码、登录设备）、退出与注销。
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! SignedIn) return const SizedBox.shrink();
    final user = auth.user;
    return JkPage(
      children: [
        _ProfileHeader(user: user),
        const JkSectionTitle('资料'),
        JkCard(
          children: [
            ListTile(
              title: const Text('昵称'),
              subtitle: Text(user.nickname.isEmpty ? '未设置' : user.nickname),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editNickname(context, ref, user),
            ),
          ],
        ),
        const JkSectionTitle('安全'),
        JkCard(
          children: [
            ListTile(
              key: const Key('account-phone'),
              leading: const Icon(Icons.phone_iphone_outlined),
              title: const Text('手机号'),
              subtitle: Text(user.phoneMasked ?? '未绑定，绑定后可用验证码登录和找回密码'),
              trailing: Text(user.hasPhone ? '换绑' : '绑定'),
              onTap: () => context.push('/account/phone'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('修改密码'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/account/password'),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('account-devices'),
              leading: const Icon(Icons.devices_outlined),
              title: const Text('登录设备'),
              subtitle: const Text('查看已登录的设备，将不认识的设备下线'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/account/devices'),
            ),
          ],
        ),
        const SizedBox(height: JkTokens.spacingXl),
        JkCard(
          children: [
            ListTile(
              key: const Key('account-logout'),
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              onTap: () => _logout(context, ref),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: context.jkColors.error,
              ),
              title: Text(
                '注销账号',
                style: TextStyle(color: context.jkColors.error),
              ),
              onTap: () => context.push('/account/delete'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    // 退出时清空本机数据：先尝试把未同步的修改推送上去
    final engine = ref.read(syncEngineProvider);
    await engine.sync();
    final pending = await ref.read(pendingChangesProvider.future);
    if (!context.mounted) return;
    final ok = await showJkConfirm(
      context,
      title: '退出登录',
      message: pending > 0
          ? '还有 $pending 条修改没有同步到服务器，退出后这些修改将丢失。确定退出吗？'
          : '退出后本机数据会被清除，重新登录后自动从服务器恢复。',
      confirmLabel: '退出',
      destructive: pending > 0,
    );
    if (ok) await ref.read(authControllerProvider.notifier).logout();
  }

  Future<void> _editNickname(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(initial: user.nickname),
    );
    if (value == null || value == user.nickname || !context.mounted) return;
    final err = JkValidators.nickname(value);
    if (err != null) return showJkToast(context, err, kind: JkToastKind.error);
    try {
      final updated = await ref.read(accountApiProvider).updateNickname(value);
      await ref.read(authControllerProvider.notifier).updateUser(updated);
      if (context.mounted) {
        showJkToast(context, '昵称已更新', kind: JkToastKind.success);
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        showJkToast(context, e.message, kind: JkToastKind.error);
      }
    }
  }
}

/// 修改昵称弹窗；输入框控制器随弹窗销毁（弹窗关闭动画期间仍会使用它）。
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改昵称'),
    content: TextField(
      key: const Key('nickname-input'),
      controller: _controller,
      autofocus: true,
      maxLength: 20,
      decoration: const InputDecoration(hintText: '最多 20 个字符'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: c.primaryContainer,
          child: Text(
            user.displayName.characters.first.toUpperCase(),
            style: text.headlineSmall?.copyWith(color: c.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: JkTokens.spacingLg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, style: text.titleLarge),
              const SizedBox(height: JkTokens.spacingXs),
              Text(
                '@${user.username}',
                style: text.bodyMedium?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
