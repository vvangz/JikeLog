import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_states.dart';
import '../attachments/attachment_section.dart';
import 'markdown_editor.dart';
import 'worklog_repository.dart';

/// 工作日志编辑页：修改即自动保存到本机（1 秒防抖），由同步引擎在后台推送。
class WorklogEditorPage extends ConsumerStatefulWidget {
  const WorklogEditorPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<WorklogEditorPage> createState() => _WorklogEditorPageState();
}

class _WorklogEditorPageState extends ConsumerState<WorklogEditorPage> {
  static const _autosave = Duration(seconds: 1);

  final _content = TextEditingController();
  final _location = TextEditingController();
  late final WorklogRepository _repo;
  Timer? _timer;
  bool _loaded = false;
  bool _deleting = false;

  /// 最后一次保存到本机的值：编辑框与它不同说明有未保存的输入。
  String _savedContent = '';
  String _savedLocation = '';

  @override
  void initState() {
    super.initState();
    _repo = ref.read(worklogRepositoryProvider);
    _content.addListener(_onEdit);
    _location.addListener(_onEdit);
  }

  void _load(Worklog w) {
    _savedContent = w.content;
    _savedLocation = w.location;
    _content.text = w.content;
    _location.text = w.location;
    _loaded = true;
  }

  void _onEdit() {
    if (!_loaded) return;
    _timer?.cancel();
    _timer = Timer(_autosave, () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    _timer?.cancel();
    final content = _content.text;
    final location = _location.text.trim();
    if (content == _savedContent && location == _savedLocation) return;
    _savedContent = content;
    _savedLocation = location;
    await _repo.update(widget.id, content: content, location: location);
  }

  /// 其他设备的修改到达：没有未保存的输入时直接刷新编辑框；否则保留本地输入，推送时由服务端合并。
  void _onRemote(Worklog? prev, Worklog? next) {
    if (next == null) {
      // 本机删除时由 _delete 负责返回，这里只处理其他设备的删除
      if (prev != null && mounted && !_deleting) {
        showJkToast(context, '这篇日志已在其他设备上删除');
        context.pop();
      }
      return;
    }
    if (!_loaded) {
      setState(() => _load(next));
      return;
    }
    if (next.content != _savedContent && _content.text == _savedContent) {
      _savedContent = next.content;
      _content.value = TextEditingValue(
        text: next.content,
        selection: TextSelection.collapsed(
          offset: _content.selection.baseOffset.clamp(0, next.content.length),
        ),
      );
    }
    if (next.location != _savedLocation && _location.text == _savedLocation) {
      _savedLocation = next.location;
      _location.text = next.location;
    }
  }

  Future<void> _pickDate(Worklog w) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: w.date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked != null) await _repo.update(widget.id, date: picked);
  }

  Future<void> _delete() async {
    final ok = await showJkConfirm(
      context,
      title: '删除日志',
      message: '删除后其他设备上也会删除，附件一并删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;
    _timer?.cancel();
    _loaded = false;
    _deleting = true;
    await _repo.delete(widget.id);
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    // 离开页面时立即保存尚未落盘的输入
    if (_loaded) unawaited(_flush());
    _timer?.cancel();
    _content.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      worklogProvider(widget.id),
      (prev, next) => _onRemote(prev?.value, next.value),
    );
    final async = ref.watch(worklogProvider(widget.id));
    final w = async.value;
    if (w != null && !_loaded) _load(w);
    return Scaffold(
      appBar: AppBar(
        title: w == null
            ? const Text('工作日志')
            : _Title(worklog: w, onPickDate: () => _pickDate(w)),
        actions: [
          IconButton(
            key: const Key('worklog-revisions'),
            tooltip: '修订历史',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/worklog/${widget.id}/revisions'),
          ),
          IconButton(
            key: const Key('worklog-delete'),
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: switch (async) {
        AsyncData(value: null) => const JkEmptyState(
          icon: Icon(Icons.inventory_2_outlined),
          title: '日志不存在',
          message: '可能已在其他设备上删除',
        ),
        AsyncData(value: final worklog?) => _body(worklog),
        AsyncError() => JkErrorState(
          message: '读取日志失败',
          onRetry: () => ref.invalidate(worklogProvider(widget.id)),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(JkTokens.spacingLg),
          child: JkSkeleton(lines: 6),
        ),
      },
    );
  }

  Widget _body(Worklog w) => ListView(
    padding: const EdgeInsets.all(JkTokens.spacingLg),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (w.hasConflict) _ConflictBanner(id: w.id),
              _LocationField(controller: _location, repo: _repo),
              const SizedBox(height: JkTokens.spacingLg),
              MarkdownEditor(controller: _content),
              const SizedBox(height: JkTokens.spacingLg),
              AttachmentSection(ownerEntity: 'worklog', ownerId: w.id),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Title extends ConsumerWidget {
  const _Title({required this.worklog, required this.onPickDate});

  final Worklog worklog;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(syncStatusProvider).value?.phase;
    final d = worklog.date;
    final status = switch (worklog) {
      Worklog(syncError: _?) => '同步失败：内容未被服务器接受',
      Worklog(pending: true) when phase == SyncPhase.offline =>
        '已保存在本机，联网后自动同步',
      Worklog(pending: true) => '已保存在本机，等待同步',
      _ => '已同步',
    };
    return InkWell(
      key: const Key('worklog-date'),
      onTap: onPickDate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d.year} 年 ${d.month} 月 ${d.day} 日'),
          Text(
            status,
            key: const Key('worklog-sync-status'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: worklog.syncError != null
                  ? context.jkColors.error
                  : context.jkColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: JkTokens.spacingLg),
      child: Material(
        color: c.warningContainer,
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        child: ListTile(
          key: const Key('worklog-conflict'),
          leading: Icon(Icons.call_split, color: c.onWarningContainer),
          title: Text(
            '与其他设备的修改冲突，已保留最后修改的版本',
            style: TextStyle(color: c.onWarningContainer),
          ),
          subtitle: Text(
            '点击查看另一版本，可以随时恢复',
            style: TextStyle(color: c.onWarningContainer),
          ),
          onTap: () => context.push('/worklog/$id/revisions'),
        ),
      ),
    );
  }
}

/// 工作地点：输入时联想历史地点。
class _LocationField extends StatefulWidget {
  const _LocationField({required this.controller, required this.repo});

  final TextEditingController controller;
  final WorklogRepository repo;

  @override
  State<_LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<_LocationField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsBuilder: (v) async {
      final all = await widget.repo.recentLocations();
      final q = v.text.trim();
      return all.where((l) => l != q && (q.isEmpty || l.contains(q)));
    },
    fieldViewBuilder: (context, c, focus, onSubmit) => TextField(
      key: const Key('worklog-location'),
      controller: c,
      focusNode: focus,
      maxLength: 100,
      decoration: const InputDecoration(
        labelText: '工作地点',
        hintText: '如：公司、客户现场、居家',
        prefixIcon: Icon(Icons.place_outlined),
        counterText: '',
      ),
      onSubmitted: (_) => onSubmit(),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final o in options)
                ListTile(title: Text(o), onTap: () => onSelected(o)),
            ],
          ),
        ),
      ),
    ),
  );
}
