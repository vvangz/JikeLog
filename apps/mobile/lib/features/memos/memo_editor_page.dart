import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/text_patch.dart';
import '../../shared/ui/conflict_banner.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_states.dart';
import '../settings/settings_controller.dart';
import 'memo_models.dart';
import 'memo_repository.dart';
import 'memo_widgets.dart';
import 'reminder_banner.dart';

/// 新建备忘时路由中的 ID。
const newMemoId = 'new';

/// 备忘编辑页。新建时（[id] 为 [newMemoId]）填写内容后才保存；内容 1 秒防抖自动保存，
/// 时间、提醒等改动立即保存。
class MemoEditorPage extends ConsumerStatefulWidget {
  const MemoEditorPage({super.key, required this.id, this.day});

  final String id;

  /// 新建时预选的日期（从日历中某天新建）。
  final DateTime? day;

  @override
  ConsumerState<MemoEditorPage> createState() => _MemoEditorPageState();
}

class _MemoEditorPageState extends ConsumerState<MemoEditorPage> {
  static const _autosave = Duration(seconds: 1);

  final _content = TextEditingController();
  late final MemoRepository _repo;
  Timer? _timer;

  /// 已保存的备忘 ID；新建且尚未保存时为 null。
  String? _id;
  bool _loaded = false;
  bool _deleting = false;
  String _savedContent = '';

  /// 编辑框上次的文字（区分真正的编辑与光标移动）。
  String _lastText = '';

  /// 进行中的保存。
  Future<void>? _inflight;

  /// 新建且尚未保存时的草稿字段。
  late DateTime _draftAt;
  bool _draftAllDay = false;
  List<int> _draftReminders = const [];

  bool get _isNew => widget.id == newMemoId;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(memoRepositoryProvider);
    _content.addListener(_onEdit);
    if (_isNew) {
      final now = DateTime.now();
      final day = widget.day;
      _draftAt = day == null || dateOnly(day) == dateOnly(now)
          ? defaultMemoTime(now)
          : allDayAt(day);
      _draftReminders = ref.read(settingsControllerProvider).defaultReminders;
      _loaded = true;
    } else {
      _id = widget.id;
      _draftAt = DateTime.now();
    }
  }

  void _load(Memo m) {
    _savedContent = m.content;
    _lastText = m.content;
    _content.text = m.content;
    _loaded = true;
  }

  void _onEdit() {
    // 只移动光标、输入法组字等不改变文字的变化不算编辑
    if (!_loaded || _content.text == _lastText) return;
    _lastText = _content.text;
    setState(() {}); // 更新"内容不能为空"提示
    _timer?.cancel();
    _timer = Timer(_autosave, () => unawaited(_flush()));
  }

  /// 保存当前内容。保存按顺序进行：新建尚未完成时，后一次保存等它完成后按"修改"处理，
  /// 不会建出两条备忘。
  Future<void> _flush() {
    _timer?.cancel();
    final content = _content.text; // 离开页面时控制器随后就会释放，先取出文字
    final prev = _inflight ?? Future<void>.value();
    return _inflight = prev.then((_) => _save(content));
  }

  Future<void> _save(String content) async {
    if (!_loaded) return; // 已删除，不能再写入
    if (content.trim().isEmpty || content == _savedContent) return;
    try {
      final id = _id;
      if (id != null) {
        await _repo.update(id, content: content);
      } else {
        _id = await _repo.create(
          content: content,
          at: _draftAt,
          allDay: _draftAllDay,
          reminders: _draftReminders,
        );
        if (mounted) setState(() {});
      }
      // 写入成功后才算已保存：失败时下次保存还会重试
      _savedContent = content;
    } on Object catch (e) {
      debugPrint('保存备忘失败: $e');
      if (mounted) showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
    }
  }

  /// 其他设备的修改到达：没有未保存的输入时直接刷新，否则把本地输入合并到新内容上。
  void _onRemote(Memo? prev, Memo? next) {
    if (next == null) {
      if (prev != null && mounted && !_deleting) {
        _timer?.cancel();
        _loaded = false;
        showJkToast(context, '这条备忘已在其他设备上删除');
        // 上面可能还叠着修订历史页，直接回到列表
        context.go('/memos');
      }
      return;
    }
    if (!_loaded) {
      setState(() => _load(next));
      return;
    }
    if (next.content == _savedContent) return;
    final local = _content.text;
    final saved = _savedContent;
    _savedContent = next.content;
    if (local == saved) {
      _setContent(next.content);
      return;
    }
    final merged = TextPatch.rebase(saved, local, next.content);
    if (merged.ok) {
      _setContent(merged.text); // 触发自动保存，保存合并后的内容
    } else if (mounted) {
      showJkToast(context, '其他设备同时修改了这里，已保留你的输入，对方的版本可在修订历史中查看');
    }
  }

  /// 替换编辑框内容，光标尽量留在原来的文字旁边。
  void _setContent(String text) {
    final old = _content.text;
    var cursor = _content.selection.baseOffset;
    if (cursor > _commonPrefix(old, text)) cursor += text.length - old.length;
    _content.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
    );
  }

  static int _commonPrefix(String a, String b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  /// 修改时间、全天或提醒：已保存的备忘立即写入，新建的先记在草稿里。
  Future<void> _set({DateTime? at, bool? allDay, List<int>? reminders}) async {
    final id = _id;
    if (id == null) {
      setState(() {
        if (allDay != null) _draftAllDay = allDay;
        if (at != null) _draftAt = at;
        if (_draftAllDay) _draftAt = allDayAt(_draftAt);
        if (reminders != null) _draftReminders = reminders;
      });
      return;
    }
    try {
      await _repo.update(id, at: at, allDay: allDay, reminders: reminders);
    } on Object catch (e) {
      debugPrint('保存备忘失败: $e');
      if (mounted) showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
    }
  }

  Future<void> _toggleDone(Memo m) async {
    try {
      await _repo.update(m.id, done: !m.done);
    } on Object catch (e) {
      debugPrint('保存备忘失败: $e');
      if (mounted) showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
    }
  }

  Future<void> _pickDate(DateTime at) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(2000),
      lastDate: DateTime(2199, 12, 31),
    );
    if (picked == null) return;
    await _set(
      at: DateTime(picked.year, picked.month, picked.day, at.hour, at.minute),
    );
  }

  Future<void> _pickTime(DateTime at) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (picked == null) return;
    await _set(
      at: DateTime(at.year, at.month, at.day, picked.hour, picked.minute),
    );
  }

  Future<void> _setAllDay(bool on, DateTime at) => on
      ? _set(allDay: true)
      // 取消全天：默认改为当天 9:00 的普通备忘
      : _set(allDay: false, at: allDayAt(at));

  Future<void> _delete() async {
    final id = _id;
    if (id == null) {
      _loaded = false;
      _close();
      return;
    }
    final ok = await showJkConfirm(
      context,
      title: '删除备忘',
      message: '删除后其他设备上也会删除，提醒随之取消。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;
    _timer?.cancel();
    _loaded = false;
    _deleting = true;
    try {
      await _inflight; // 等进行中的保存结束，删除之后不能再写入
      await _repo.delete(id);
    } on Object catch (e) {
      debugPrint('删除备忘失败: $e');
      _loaded = true;
      _deleting = false;
      if (mounted) showJkToast(context, '删除失败，请重试', kind: JkToastKind.error);
      return;
    }
    if (mounted) _close();
  }

  /// 关闭编辑页；直接打开（没有上一页）时回到备忘录列表。
  void _close() => context.canPop() ? context.pop() : context.go('/memos');

  @override
  void dispose() {
    if (_loaded) unawaited(_flush());
    _timer?.cancel();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    if (id == null) return _scaffold(null);
    ref.listen(
      memoProvider(id),
      (prev, next) => _onRemote(prev?.value, next.value),
    );
    final async = ref.watch(memoProvider(id));
    final m = async.value;
    if (m != null && !_loaded) _load(m);
    return switch (async) {
      AsyncData(value: null) when !_isNew => Scaffold(
        appBar: AppBar(title: const Text('备忘')),
        body: const JkEmptyState(
          icon: Icon(Icons.inventory_2_outlined),
          title: '备忘不存在',
          message: '可能已在其他设备上删除',
        ),
      ),
      AsyncError() => Scaffold(
        appBar: AppBar(title: const Text('备忘')),
        body: JkErrorState(
          message: '读取备忘失败',
          onRetry: () => ref.invalidate(memoProvider(id)),
        ),
      ),
      // 新建的备忘刚保存、尚未读回时继续显示编辑框（不能闪成骨架屏而丢掉输入焦点）
      _ when m == null && !_loaded => Scaffold(
        appBar: AppBar(title: const Text('备忘')),
        body: const Padding(
          padding: EdgeInsets.all(JkTokens.spacingLg),
          child: JkSkeleton(lines: 4),
        ),
      ),
      _ => _scaffold(m),
    };
  }

  Widget _scaffold(Memo? m) {
    final at = m?.at ?? _draftAt;
    final allDay = m?.allDay ?? _draftAllDay;
    final reminders = m?.reminders ?? _draftReminders;
    final empty = _content.text.trim().isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew && m == null ? '新建备忘' : '备忘'),
        actions: [
          if (m != null) ...[
            IconButton(
              key: const Key('memo-done'),
              tooltip: m.done ? '标记为未完成' : '标记为已完成',
              icon: Icon(
                m.done ? Icons.check_circle : Icons.check_circle_outline,
              ),
              onPressed: () => _toggleDone(m),
            ),
            IconButton(
              key: const Key('memo-revisions'),
              tooltip: '修订历史',
              icon: const Icon(Icons.history),
              onPressed: () => context.push('/memos/${m.id}/revisions'),
            ),
          ],
          IconButton(
            key: const Key('memo-delete'),
            tooltip: m == null ? '放弃' : '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(JkTokens.spacingLg),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (m?.hasConflict ?? false)
                    ConflictBanner(
                      key: const Key('memo-conflict'),
                      onTap: () => context.push('/memos/${m!.id}/revisions'),
                    ),
                  if (reminders.isNotEmpty) const ReminderBanner(),
                  TextField(
                    key: const Key('memo-content'),
                    controller: _content,
                    autofocus: _isNew,
                    minLines: 3,
                    maxLines: null,
                    maxLength: maxMemoLength,
                    decoration: InputDecoration(
                      hintText: '要记住什么事？',
                      border: const OutlineInputBorder(),
                      errorText:
                          empty && (m != null || _savedContent.isNotEmpty)
                          ? '内容不能为空，清空的内容不会保存'
                          : null,
                    ),
                  ),
                  const SizedBox(height: JkTokens.spacingMd),
                  _TimeCard(
                    at: at,
                    allDay: allDay,
                    onPickDate: () => _pickDate(at),
                    onPickTime: () => _pickTime(at),
                    onAllDay: (on) => _setAllDay(on, at),
                  ),
                  const SizedBox(height: JkTokens.spacingMd),
                  Text('提醒', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: JkTokens.spacingSm),
                  ReminderChips(
                    value: reminders,
                    allDay: allDay,
                    onChanged: (v) => _set(reminders: v),
                  ),
                  if (_isNew && m == null) ...[
                    const SizedBox(height: JkTokens.spacingLg),
                    Text(
                      '填写内容后自动保存',
                      style: TextStyle(color: context.jkColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.at,
    required this.allDay,
    required this.onPickDate,
    required this.onPickTime,
    required this.onAllDay,
  });

  final DateTime at;
  final bool allDay;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final ValueChanged<bool> onAllDay;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Column(
      children: [
        ListTile(
          key: const Key('memo-date'),
          leading: const Icon(Icons.event_outlined),
          title: Text(friendlyDate(at, DateTime.now())),
          subtitle: Text('${at.year}年${at.month}月${at.day}日'),
          onTap: onPickDate,
        ),
        if (!allDay)
          ListTile(
            key: const Key('memo-time'),
            leading: const Icon(Icons.schedule),
            title: Text(formatClock(at)),
            onTap: onPickTime,
          ),
        SwitchListTile(
          key: const Key('memo-all-day'),
          secondary: const Icon(Icons.wb_sunny_outlined),
          title: const Text('全天'),
          subtitle: allDay ? const Text('提醒从当天 9:00 起算') : null,
          value: allDay,
          onChanged: onAllDay,
        ),
      ],
    ),
  );
}
