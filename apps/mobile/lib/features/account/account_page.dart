import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/api/server_features.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_form.dart';
import '../../shared/ui/jk_page.dart';
import '../../shared/ui/user_avatar.dart';
import '../auth/auth_controller.dart';
import 'avatar_service.dart';

/// 帐号页：资料（头像、昵称）、安全（手机号、密码、登录设备）、退出与注销。
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  bool _updatingAvatar = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! SignedIn) return const SizedBox.shrink();
    final user = auth.user;
    return JkPage(
      children: [
        _ProfileHeader(
          user: user,
          updatingAvatar: _updatingAvatar,
          onTapAvatar: () => _openAvatarActions(user),
        ),
        const JkSectionTitle('资料'),
        JkCard(
          children: [
            ListTile(
              key: const Key('account-avatar-tile'),
              title: const Text('头像'),
              subtitle: Text(user.hasAvatar ? '已设置自定义头像' : '使用默认首字母头像'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(user: user, size: 32, loading: _updatingAvatar),
                  const SizedBox(width: JkTokens.spacingXs),
                  const Icon(Icons.chevron_right),
                ],
              ),
              enabled: !_updatingAvatar,
              onTap: () => _openAvatarActions(user),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('昵称'),
              subtitle: Text(user.nickname.isEmpty ? '未设置' : user.nickname),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editNickname(user),
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
              subtitle: Text(
                smsEnabled(ref)
                    ? user.phoneMasked ?? '未绑定，绑定后可用验证码登录和找回密码'
                    : '${user.phoneMasked ?? '未绑定'}（${smsUnavailableReason(ref)}）',
              ),
              trailing: smsEnabled(ref)
                  ? Text(user.hasPhone ? '换绑' : '绑定')
                  : null,
              enabled: smsEnabled(ref),
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
              onTap: _logout,
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

  Future<void> _openAvatarActions(User user) async {
    if (_updatingAvatar) return;
    if (!user.hasAvatar) {
      await _pickAndUploadAvatar();
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('avatar-action-pick'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('选择新头像'),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.pick),
            ),
            ListTile(
              key: const Key('avatar-action-reset'),
              leading: Icon(Icons.restart_alt, color: ctx.jkColors.error),
              title: Text(
                '恢复默认头像',
                style: TextStyle(color: ctx.jkColors.error),
              ),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.reset),
            ),
            const SizedBox(height: JkTokens.spacingSm),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AvatarAction.pick:
        await _pickAndUploadAvatar();
      case _AvatarAction.reset:
        await _resetAvatar(user);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final bytes = await ref.read(avatarPickerProvider)();
    if (bytes == null || !mounted) return;
    if (bytes.isEmpty) {
      showJkToast(context, '无法读取所选图片，请重试', kind: JkToastKind.error);
      return;
    }
    setState(() => _updatingAvatar = true);
    try {
      final updated = await ref.read(avatarServiceProvider).upload(bytes);
      await ref.read(authControllerProvider.notifier).updateUser(updated);
      if (mounted) {
        showJkToast(context, '头像已更新', kind: JkToastKind.success);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showJkToast(context, e.message, kind: JkToastKind.error);
      }
    } on Object {
      if (mounted) {
        showJkToast(context, '头像上传失败，请稍后重试', kind: JkToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _updatingAvatar = false);
    }
  }

  Future<void> _resetAvatar(User user) async {
    setState(() => _updatingAvatar = true);
    try {
      final updated = await ref.read(avatarServiceProvider).remove(user.id);
      await ref.read(authControllerProvider.notifier).updateUser(updated);
      if (mounted) {
        showJkToast(context, '已恢复默认头像', kind: JkToastKind.success);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showJkToast(context, e.message, kind: JkToastKind.error);
      }
    } on Object {
      if (mounted) {
        showJkToast(context, '恢复默认头像失败，请稍后重试', kind: JkToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _updatingAvatar = false);
    }
  }

  Future<void> _logout() async {
    // 退出时清空本机数据：先尝试把未同步的修改推送上去
    final engine = ref.read(syncEngineProvider);
    await engine.sync();
    final pending = await ref.read(pendingChangesProvider.future);
    if (!mounted) return;
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

  Future<void> _editNickname(User user) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(initial: user.nickname),
    );
    if (value == null || value == user.nickname || !mounted) return;
    final err = JkValidators.nickname(value);
    if (err != null) return showJkToast(context, err, kind: JkToastKind.error);
    try {
      final updated = await ref.read(accountApiProvider).updateNickname(value);
      await ref.read(authControllerProvider.notifier).updateUser(updated);
      if (mounted) {
        showJkToast(context, '昵称已更新', kind: JkToastKind.success);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showJkToast(context, e.message, kind: JkToastKind.error);
      }
    }
  }
}

enum _AvatarAction { pick, reset }

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
  const _ProfileHeader({
    required this.user,
    required this.updatingAvatar,
    required this.onTapAvatar,
  });

  final User user;
  final bool updatingAvatar;
  final VoidCallback onTapAvatar;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        UserAvatar(
          key: const Key('account-avatar-header'),
          user: user,
          size: 64,
          editable: true,
          loading: updatingAvatar,
          onTap: onTapAvatar,
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
