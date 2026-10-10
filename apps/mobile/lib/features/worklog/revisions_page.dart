import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/api/api_exception.dart';
import '../../core/sync/schema.dart';
import '../../core/sync/sync_api.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/jk_button.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_states.dart';
import 'worklog_repository.dart';

final _revisionsProvider = FutureProvider.autoDispose
    .family<List<RevisionInfo>, String>(
      (ref, id) => ref.watch(syncApiProvider).revisions(id),
    );

/// 修订历史：查看并恢复编辑前、冲突中落败、删除前的版本（需要联网）。
class RevisionsPage extends ConsumerStatefulWidget {
  const RevisionsPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<RevisionsPage> createState() => _RevisionsPageState();
}

class _RevisionsPageState extends ConsumerState<RevisionsPage> {
  @override
  void initState() {
    super.initState();
    // 用户已来查看冲突版本，清除冲突提示
    Future.microtask(
      () => ref.read(recordStoreProvider).clearConflict(widget.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_revisionsProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text('修订历史')),
      body: list.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(JkTokens.spacingLg),
          child: JkSkeleton(lines: 5),
        ),
        error: (e, _) => JkErrorState(
          message: e is ApiException && e.code == ApiErrorCode.recordNotFound
              ? '这篇日志还没有同步到服务器，暂无修订历史'
              : '读取修订历史失败，请检查网络后重试',
          onRetry: () => ref.invalidate(_revisionsProvider(widget.id)),
        ),
        data: (items) => items.isEmpty
            ? const JkEmptyState(
                icon: Icon(Icons.history),
                title: '暂无修订',
                message: '在其他设备上修改，或间隔一段时间再次修改后，这里会保留之前的版本',
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: JkTokens.spacingSm,
                ),
                children: [
                  for (final r in items)
                    ListTile(
                      leading: Icon(_icon(r.reason)),
                      title: Text(_label(r.reason)),
                      subtitle: Text(
                        '${_time(r.createdAt)}'
                        '${r.deviceModel.isEmpty ? '' : ' · ${r.deviceModel}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _RevisionDetail(
                            worklogId: widget.id,
                            revision: r,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  static IconData _icon(String reason) => switch (reason) {
    'conflict' => Icons.call_split,
    'delete' => Icons.delete_outline,
    _ => Icons.edit_note,
  };
}

String _label(String reason) => switch (reason) {
  'conflict' => '冲突中未被采用的版本',
  'delete' => '删除前的版本',
  _ => '修改前的版本',
};

String _time(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 修订内容与恢复。
class _RevisionDetail extends ConsumerStatefulWidget {
  const _RevisionDetail({required this.worklogId, required this.revision});

  final String worklogId;
  final RevisionInfo revision;

  @override
  ConsumerState<_RevisionDetail> createState() => _RevisionDetailState();
}

class _RevisionDetailState extends ConsumerState<_RevisionDetail> {
  late Future<Map<String, Object?>> _fields = _load();
  bool _restoring = false;

  Future<Map<String, Object?>> _load() async {
    final api = ref.read(syncApiProvider);
    return api.withSession((s) async {
      final data = await api.revision(s, widget.revision.id);
      final out = <String, Object?>{};
      for (final e in (data['fields'] as Map<String, dynamic>).entries) {
        final v = e.value;
        out[e.key] =
            v is String && Entities.field(Entities.worklog, e.key).sensitive
            ? await s.openValue(Entities.worklog, widget.worklogId, e.key, v)
            : v;
      }
      return out;
    });
  }

  Future<void> _restore(Map<String, Object?> f) async {
    setState(() => _restoring = true);
    try {
      await ref
          .read(worklogRepositoryProvider)
          .update(
            widget.worklogId,
            date: DateTime.tryParse(f['date'] as String? ?? ''),
            location: f['location'] as String? ?? '',
            content: f['content'] as String? ?? '',
          );
    } on Object catch (e) {
      debugPrint('恢复修订失败: $e');
      if (!mounted) return;
      setState(() => _restoring = false);
      showJkToast(context, '恢复失败，请重试', kind: JkToastKind.error);
      return;
    }
    if (!mounted) return;
    showJkToast(context, '已恢复此版本', kind: JkToastKind.success);
    // 先关闭本页（由修订列表推入），再由路由返回编辑页
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Scaffold(
      appBar: AppBar(title: Text(_label(widget.revision.reason))),
      body: FutureBuilder(
        future: _fields,
        builder: (context, snap) {
          if (snap.hasError) {
            return JkErrorState(
              message: '读取修订内容失败，请检查网络后重试',
              onRetry: () => setState(() => _fields = _load()),
            );
          }
          final f = snap.data;
          if (f == null) {
            return const Padding(
              padding: EdgeInsets.all(JkTokens.spacingLg),
              child: JkSkeleton(lines: 6),
            );
          }
          final location = f['location'] as String? ?? '';
          final content = f['content'] as String? ?? '';
          return ListView(
            padding: const EdgeInsets.all(JkTokens.spacingLg),
            children: [
              Text(
                '${f['date'] ?? ''}${location.isEmpty ? '' : ' · $location'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                _time(widget.revision.createdAt),
                style: TextStyle(color: c.textSecondary),
              ),
              const Divider(height: JkTokens.spacingXl),
              if (content.trim().isEmpty)
                Text('（无内容）', style: TextStyle(color: c.textDisabled))
              else
                MarkdownBody(data: content, selectable: true),
              const SizedBox(height: JkTokens.spacingXl),
              JkButton(
                key: const Key('revision-restore'),
                label: '恢复此版本',
                loading: _restoring,
                onPressed: () => _restore(f),
              ),
            ],
          );
        },
      ),
    );
  }
}
