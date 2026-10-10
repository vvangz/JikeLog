import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_feedback.dart';
import 'memo_models.dart';

const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String two(int n) => n.toString().padLeft(2, '0');

String formatClock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// 日期的友好写法：今天、明天、昨天，同年省略年份。
String friendlyDate(DateTime day, DateTime now) {
  final d = dateOnly(day);
  final today = dateOnly(now);
  final diff = d.difference(today).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff == -1) return '昨天';
  final md = '${d.month}月${d.day}日 ${weekdayNames[d.weekday - 1]}';
  return d.year == today.year ? md : '${d.year}年$md';
}

/// 备忘时间的完整写法，如"明天 15:30"、"10月12日 周一 全天"。
String memoWhen(Memo m, DateTime now) =>
    '${friendlyDate(m.at, now)} ${m.allDay ? '全天' : formatClock(m.at)}';

/// 提醒选择：常用提前量与自定义提前量，最多 [maxReminders] 个。
class ReminderChips extends StatelessWidget {
  const ReminderChips({
    super.key,
    required this.value,
    required this.allDay,
    required this.onChanged,
  });

  final List<int> value;
  final bool allDay;
  final ValueChanged<List<int>> onChanged;

  void _toggle(BuildContext context, int m, bool on) {
    final next = {...value};
    if (on) {
      if (next.length >= maxReminders) {
        showJkToast(context, '最多设置 $maxReminders 个提醒');
        return;
      }
      next.add(m);
    } else {
      next.remove(m);
    }
    onChanged(next.toList()..sort());
  }

  Future<void> _custom(BuildContext context) async {
    final m = await showDialog<int>(
      context: context,
      builder: (_) => const CustomReminderDialog(),
    );
    if (m != null && context.mounted && !value.contains(m)) {
      _toggle(context, m, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = value.where((m) => !reminderPresets.contains(m));
    return Wrap(
      spacing: JkTokens.spacingSm,
      runSpacing: JkTokens.spacingSm,
      children: [
        for (final m in [...reminderPresets, ...custom])
          FilterChip(
            key: Key('memo-reminder-$m'),
            label: Text(reminderLabel(m, allDay: allDay)),
            selected: value.contains(m),
            onSelected: (on) => _toggle(context, m, on),
          ),
        ActionChip(
          key: const Key('memo-reminder-custom'),
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('自定义'),
          onPressed: () => _custom(context),
        ),
      ],
    );
  }
}

/// 自定义提前量：数字加单位（分钟、小时、天），不超过 30 天。
class CustomReminderDialog extends StatefulWidget {
  const CustomReminderDialog({super.key});

  @override
  State<CustomReminderDialog> createState() => _CustomReminderDialogState();
}

class _CustomReminderDialogState extends State<CustomReminderDialog> {
  final _amount = TextEditingController(text: '30');
  int _unit = 1;
  String? _error;

  static const _units = {1: '分钟', 60: '小时', 1440: '天'};

  void _submit() {
    final n = int.tryParse(_amount.text);
    final minutes = n == null ? null : n * _unit;
    if (minutes == null || minutes <= 0 || minutes > maxReminderMinutes) {
      setState(() => _error = '请输入 1 分钟到 30 天之间的提前量');
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义提醒'),
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: JkTokens.spacingLg),
          child: Text('提前'),
        ),
        const SizedBox(width: JkTokens.spacingSm),
        Expanded(
          child: TextField(
            key: const Key('custom-reminder-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            decoration: InputDecoration(errorText: _error, errorMaxLines: 2),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: JkTokens.spacingSm),
        DropdownButton<int>(
          key: const Key('custom-reminder-unit'),
          value: _unit,
          items: [
            for (final e in _units.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _unit = v ?? 1),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('custom-reminder-ok'),
        onPressed: _submit,
        child: const Text('确定'),
      ),
    ],
  );
}
