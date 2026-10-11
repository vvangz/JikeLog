import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/api/api_exception.dart';
import '../../shared/ui/jk_button.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_page.dart';
import '../../shared/ui/jk_states.dart';
import 'export_api.dart';

/// 数据导出：选择模块发起导出，查看进度，下载后分享或保存（ADR-010）。
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  /// 有进行中的导出时刷新状态的间隔。
  static const pollInterval = Duration(seconds: 3);

  final _modules = {...ExportModule.values};
  bool _attachments = false;
  bool _creating = false;

  /// 正在下载的导出。
  String? _downloading;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// 有进行中的导出时定期刷新，全部结束后停止。
  void _schedulePoll(List<ExportJob> jobs) {
    final active = jobs.any((j) => j.status.active);
    if (active && _poll == null) {
      _poll = Timer.periodic(
        pollInterval,
        (_) => ref.invalidate(exportsProvider),
      );
    } else if (!active && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  /// 请求失败时的提示：服务端给出的原因，或通用的网络提示。
  void _toastError(Object e) {
    if (!mounted) return;
    if (e is! ApiException) debugPrint('导出请求失败: $e');
    showJkToast(
      context,
      e is ApiException ? e.message : '操作失败，请检查网络后重试',
      kind: JkToastKind.error,
    );
  }

  // 以下操作都在 await 之后检查 mounted：页面可能已经关闭，此时 ref 不能再用

  Future<void> _create() async {
    setState(() => _creating = true);
    final api = ref.read(exportApiProvider);
    try {
      await api.create(_modules, attachments: _attachments);
      if (!mounted) return;
      ref.invalidate(exportsProvider);
      showJkToast(context, '已开始导出，完成后会通知你');
    } on Object catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _download(ExportJob job) async {
    setState(() => _downloading = job.id);
    final api = ref.read(exportApiProvider);
    final files = ref.read(exportFilesProvider);
    try {
      final url = await api.downloadUrl(job.id);
      await files.downloadAndShare(url, exportFileName(job.createdAt));
    } on ApiException catch (e) {
      _toastError(e);
      // 可能已过期：刷新状态
      if (mounted) ref.invalidate(exportsProvider);
    } on Object catch (e) {
      debugPrint('下载导出文件失败: $e');
      if (mounted) {
        showJkToast(context, '下载失败，请检查网络后重试', kind: JkToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _delete(ExportJob job) async {
    final ok = await showJkConfirm(
      context,
      title: '删除这次导出？',
      message: '服务器上的导出文件会立即删除。已经下载到本机的文件不受影响。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(exportApiProvider).delete(job.id);
      if (mounted) ref.invalidate(exportsProvider);
    } on Object catch (e) {
      _toastError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final jobs = ref.watch(exportsProvider);
    ref.listen(exportsProvider, (_, next) {
      if (next.value case final list?) _schedulePoll(list);
    });
    final busy = jobs.value?.any((j) => j.status.active) ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('数据导出')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(exportsProvider.future),
        child: JkPage(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const JkSectionTitle('新的导出'),
            JkCard(
              children: [
                for (final m in ExportModule.values)
                  CheckboxListTile(
                    key: Key('export-module-${m.name}'),
                    title: Text(m.label),
                    value: _modules.contains(m),
                    onChanged: (v) => setState(
                      () => v == true ? _modules.add(m) : _modules.remove(m),
                    ),
                  ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('export-attachments'),
                  title: const Text('包含附件文件'),
                  subtitle: const Text('工作日志和笔记中的图片、文档等，文件可能较大'),
                  value: _attachments,
                  onChanged: (v) => setState(() => _attachments = v),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingMd),
              child: Text(
                '导出在服务器上生成，完成后会通知你。包含表格、Markdown、日历文件和完整的 JSON 数据。'
                '导出文件不加密，保留 24 小时后自动删除，下载后请妥善保管。',
                style: t.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ),
            JkButton(
              key: const Key('export-start'),
              label: busy ? '正在导出…' : '开始导出',
              loading: _creating,
              onPressed: _modules.isEmpty || busy || _creating ? null : _create,
            ),
            const JkSectionTitle('最近的导出'),
            jobs.when(
              // 定时刷新偶尔失败时继续显示上次的列表，不闪成错误页
              skipError: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(JkTokens.spacingLg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => JkErrorState(
                message: e is ApiException ? e.message : '读取导出记录失败',
                onRetry: () => ref.invalidate(exportsProvider),
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(JkTokens.spacingLg),
                      child: Text(
                        '还没有导出过',
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(color: c.textSecondary),
                      ),
                    )
                  : JkCard(
                      children: [
                        for (final (i, job) in list.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _ExportTile(
                            job: job,
                            downloading: _downloading == job.id,
                            onDownload: _downloading == null
                                ? () => _download(job)
                                : null,
                            onDelete: () => _delete(job),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.job,
    required this.downloading,
    required this.onDownload,
    required this.onDelete,
  });

  final ExportJob job;
  final bool downloading;
  final VoidCallback? onDownload;
  final VoidCallback onDelete;

  String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
  }

  String _detail(DateTime now) {
    final j = job;
    final parts = <String>[_when(j.createdAt)];
    switch (j.status) {
      case ExportStatus.done when j.canDownload(now):
        if (j.size != null) parts.add(formatBytes(j.size!));
        parts.add('${_when(j.expiresAt!)} 前可下载');
      case ExportStatus.done:
        parts.add('已过期');
      case ExportStatus.failed:
        parts.add(j.error ?? '导出失败');
      default:
        parts.add(j.status.label);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final now = DateTime.now();
    final title = [
      job.modules.map((m) => m.label).join('、'),
      if (job.attachments) '含附件',
    ].join(' · ');
    return ListTile(
      key: Key('export-${job.id}'),
      leading: switch (job.status) {
        // 生成可能要几分钟，用静态图标，不让页面一直重绘
        ExportStatus.pending ||
        ExportStatus.running => Icon(Icons.hourglass_top, color: c.info),
        ExportStatus.done when job.canDownload(now) => Icon(
          Icons.inventory_2_outlined,
          color: c.success,
        ),
        ExportStatus.failed => Icon(Icons.error_outline, color: c.error),
        _ => Icon(Icons.history, color: c.textSecondary),
      },
      title: Text(title),
      subtitle: Text(_detail(now)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (job.canDownload(now))
            downloading
                ? const SizedBox.square(
                    dimension: 48,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: Key('export-download-${job.id}'),
                    tooltip: '下载并分享',
                    icon: const Icon(Icons.download),
                    onPressed: onDownload,
                  ),
          if (!job.status.active)
            IconButton(
              key: Key('export-delete-${job.id}'),
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
