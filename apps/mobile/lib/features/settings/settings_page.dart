import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/api/models.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_page.dart';
import 'reminder_settings.dart';
import 'settings_controller.dart';

/// 可选的默认提前提醒（分钟）。
const reminderOptions = <int, String>{
  0: '准时',
  5: '5 分钟',
  15: '15 分钟',
  60: '1 小时',
  1440: '1 天',
};

/// 设置页：外观（主题、字号）、日历、提醒，以及关于。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    UserSettings next,
  ) async {
    final synced = await ref
        .read(settingsControllerProvider.notifier)
        .update(next);
    if (!synced && context.mounted) {
      showJkToast(context, '已保存在本机，联网登录后自动同步');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    return JkPage(
      children: [
        const JkSectionTitle('外观'),
        JkCard(
          children: [
            ListTile(
              title: const Text('主题'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: JkTokens.spacingSm),
                child: SegmentedButton<String>(
                  key: const Key('theme-mode'),
                  // 手机宽度下保证"跟随系统"不换行
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('跟随系统')),
                    ButtonSegment(value: 'light', label: Text('浅色')),
                    ButtonSegment(value: 'dark', label: Text('深色')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) =>
                      _save(context, ref, s.copyWith(themeMode: v.first)),
                ),
              ),
            ),
            const Divider(height: 1),
            _FontScaleTile(
              value: s.fontScale,
              onChanged: (v) => _save(context, ref, s.copyWith(fontScale: v)),
            ),
          ],
        ),
        const JkSectionTitle('日历与提醒'),
        JkCard(
          children: [
            ListTile(
              title: const Text('一周的第一天'),
              trailing: SegmentedButton<int>(
                key: const Key('week-start'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('周一')),
                  ButtonSegment(value: 7, label: Text('周日')),
                ],
                selected: {s.weekStart},
                onSelectionChanged: (v) =>
                    _save(context, ref, s.copyWith(weekStart: v.first)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('新建备忘录的默认提醒'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: JkTokens.spacingSm),
                child: Wrap(
                  spacing: JkTokens.spacingSm,
                  runSpacing: JkTokens.spacingSm,
                  children: [
                    for (final e in reminderOptions.entries)
                      FilterChip(
                        key: Key('reminder-${e.key}'),
                        label: Text(e.value),
                        selected: s.defaultReminders.contains(e.key),
                        onSelected: (on) {
                          final next = {...s.defaultReminders};
                          on ? next.add(e.key) : next.remove(e.key);
                          _save(
                            context,
                            ref,
                            s.copyWith(defaultReminders: next.toList()..sort()),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const ReminderPermissionTile(),
            const Divider(height: 1),
            const CalendarExportTile(),
          ],
        ),
        const JkSectionTitle('其他'),
        JkCard(
          children: [
            ListTile(
              key: const Key('settings-export'),
              leading: const Icon(Icons.archive_outlined),
              title: const Text('数据导出'),
              subtitle: const Text('导出为表格、Markdown 和日历文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/export'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于即刻日志'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/about'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 字号滑块：拖动时实时预览，松手后保存。
class _FontScaleTile extends StatefulWidget {
  const _FontScaleTile({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_FontScaleTile> createState() => _FontScaleTileState();
}

class _FontScaleTileState extends State<_FontScaleTile> {
  late double _v = widget.value;

  @override
  void didUpdateWidget(_FontScaleTile old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value;
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Row(
      children: [
        const Text('字号'),
        const Spacer(),
        Text(
          '${(_v * 100).round()}%',
          style: TextStyle(color: context.jkColors.textSecondary),
        ),
      ],
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Slider(
          key: const Key('font-scale'),
          value: _v,
          min: 0.8,
          max: 1.4,
          divisions: 6,
          label: '${(_v * 100).round()}%',
          onChanged: (v) => setState(() => _v = v),
          onChangeEnd: widget.onChanged,
        ),
        Text('预览：即刻记录，Space Grotesk 123', textScaler: TextScaler.linear(_v)),
      ],
    ),
  );
}
