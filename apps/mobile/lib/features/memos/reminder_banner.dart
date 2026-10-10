import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../reminders/reminder_coordinator.dart';

/// 缺少通知或精确闹钟权限时的提示条：提醒可能不弹出或延后。
class ReminderBanner extends ConsumerStatefulWidget {
  const ReminderBanner({super.key});

  @override
  ConsumerState<ReminderBanner> createState() => _ReminderBannerState();
}

class _ReminderBannerState extends ConsumerState<ReminderBanner> {
  @override
  void initState() {
    super.initState();
    // 首次显示时读取一次（之后由回到前台时的检查刷新）
    if (ref.read(reminderPermissionsProvider) == null) {
      Future.microtask(
        () => ref.read(reminderPermissionsProvider.notifier).refresh(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(reminderPermissionsProvider);
    if (p == null || p.canRemindLocally) return const SizedBox.shrink();
    final c = context.jkColors;
    final text = !p.notifications ? '未允许通知，备忘到时间不会弹出提醒' : '未允许精确闹钟，提醒可能延后几分钟';
    return Card(
      key: const Key('reminder-banner'),
      color: c.warningContainer,
      margin: const EdgeInsets.only(bottom: JkTokens.spacingMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: JkTokens.spacingLg,
          vertical: JkTokens.spacingSm,
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined, color: c.onWarningContainer),
            const SizedBox(width: JkTokens.spacingMd),
            Expanded(
              child: Text(text, style: TextStyle(color: c.onWarningContainer)),
            ),
            TextButton(
              key: const Key('reminder-banner-enable'),
              onPressed: () =>
                  ref.read(reminderPermissionsProvider.notifier).request(),
              child: const Text('去开启'),
            ),
          ],
        ),
      ),
    );
  }
}
