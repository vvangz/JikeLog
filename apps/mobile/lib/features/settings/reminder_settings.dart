import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/ui/jk_feedback.dart';
import '../reminders/reminder_coordinator.dart';

/// 本设备是否把备忘录写入系统日历（按设备保存，ADR-008）。
final calendarExportEnabledProvider =
    NotifierProvider<CalendarExportController, bool>(
      CalendarExportController.new,
    );

class CalendarExportController extends Notifier<bool> {
  @override
  bool build() => ref.read(calendarExporterProvider).enabled;

  /// 开启需要日历权限；没有获得权限时返回 false。
  Future<bool> set(bool on) async {
    final exporter = ref.read(calendarExporterProvider);
    if (on) {
      if (!await exporter.enable()) return false;
      state = true;
      ref.read(reminderCoordinatorProvider).refresh();
    } else {
      await exporter.disable();
      state = false;
    }
    return true;
  }
}

/// 提醒权限状态：缺少权限时可以一键去开启。
class ReminderPermissionTile extends ConsumerStatefulWidget {
  const ReminderPermissionTile({super.key});

  @override
  ConsumerState<ReminderPermissionTile> createState() =>
      _ReminderPermissionTileState();
}

class _ReminderPermissionTileState
    extends ConsumerState<ReminderPermissionTile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(reminderPermissionsProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(reminderPermissionsProvider);
    final c = context.jkColors;
    final (text, ok) = switch (p) {
      null => ('正在检查…', true),
      _ when !p.notifications => ('未允许通知，备忘到时间不会弹出提醒', false),
      _ when !p.exact => ('未允许精确闹钟，提醒可能延后几分钟', false),
      _ => ('已开启，备忘会按时提醒', true),
    };
    return ListTile(
      key: const Key('reminder-permission'),
      leading: Icon(
        ok
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
      ),
      title: const Text('提醒通知'),
      subtitle: Text(text, style: TextStyle(color: ok ? null : c.warning)),
      trailing: ok
          ? null
          : TextButton(
              key: const Key('reminder-permission-enable'),
              onPressed: () =>
                  ref.read(reminderPermissionsProvider.notifier).request(),
              child: const Text('去开启'),
            ),
    );
  }
}

/// 同步到系统日历的开关。
class CalendarExportTile extends ConsumerWidget {
  const CalendarExportTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    key: const Key('calendar-export'),
    secondary: const Icon(Icons.event_available_outlined),
    title: const Text('备忘录同步到系统日历'),
    subtitle: const Text('备忘的第一行与时间写入本机的"即刻日志"日历，不随系统账户同步到云端'),
    value: ref.watch(calendarExportEnabledProvider),
    onChanged: (on) async {
      if (on) {
        // 写入系统日历后不再受 App 的加密保护，先说明清楚
        final ok = await showJkConfirm(
          context,
          title: '同步到系统日历',
          message:
              '每条备忘的第一行和时间会以明文写入本机的"即刻日志"日历，'
              '手机上获得日历权限的其他应用可以读取。关闭后该日历会被删除。',
          confirmLabel: '开启',
        );
        if (!ok) return;
      }
      final granted = await ref
          .read(calendarExportEnabledProvider.notifier)
          .set(on);
      if (!granted && context.mounted) {
        showJkToast(context, '没有获得日历权限，可在系统设置中允许后重试');
      }
    },
  );
}
