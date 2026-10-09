import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/api/api_exception.dart';
import '../../shared/ui/jk_feedback.dart';
import 'attachment_providers.dart';
import 'attachment_service.dart';

/// 选择文件（测试中替换）。用户取消时返回空列表。
final filePickerProvider = Provider<Future<List<PlatformFile>> Function()>(
  (_) => FilePicker.pickFiles,
);

/// 记录详情页中的附件区：列表、添加、打开、删除。
class AttachmentSection extends ConsumerWidget {
  const AttachmentSection({
    super.key,
    required this.ownerEntity,
    required this.ownerId,
  });

  final String ownerEntity;
  final String ownerId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final picked = await ref.read(filePickerProvider)();
    final service = ref.read(attachmentServiceProvider);
    for (final f in picked) {
      final path = f.path;
      if (path == null) continue;
      await service.add(
        ownerEntity: ownerEntity,
        ownerId: ownerId,
        source: File(path),
        fileName: f.name,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(attachmentsProvider(ownerId)).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('附件', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              key: const Key('attachment-add'),
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingSm),
            child: Text(
              '可添加图片、PDF、音频等文件，单个不超过 100MB',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.jkColors.textSecondary),
            ),
          ),
        for (final a in items) _AttachmentTile(item: a),
      ],
    );
  }
}

class _AttachmentTile extends ConsumerStatefulWidget {
  const _AttachmentTile({required this.item});

  final AttachmentView item;

  @override
  ConsumerState<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends ConsumerState<_AttachmentTile> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      final file = await ref
          .read(attachmentServiceProvider)
          .open(widget.item.id);
      final res = await OpenFilex.open(file.path, type: widget.item.mime);
      if (res.type != ResultType.done && mounted) {
        showJkToast(context, '没有可以打开该文件的应用');
      }
    } on ApiException catch (e) {
      if (mounted) showJkToast(context, e.message, kind: JkToastKind.error);
    } on Object {
      if (mounted) {
        showJkToast(context, '打开附件失败，请稍后重试', kind: JkToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showJkConfirm(
      context,
      title: '删除附件',
      message: '确定删除"${widget.item.fileName}"吗？其他设备上也会删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok) await ref.read(attachmentServiceProvider).remove(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.item;
    final c = context.jkColors;
    final (subtitle, color) = switch (a.state) {
      AttachmentState.uploading => (
        '等待上传 · ${formatSize(a.size)}',
        c.textSecondary,
      ),
      AttachmentState.failed => (a.error ?? '上传失败', c.error),
      AttachmentState.ready => (formatSize(a.size), c.textSecondary),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(a), color: c.primary),
      title: Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, style: TextStyle(color: color)),
      onTap: a.state == AttachmentState.ready && !_opening ? _open : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_opening)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (a.state == AttachmentState.failed)
            IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(attachmentServiceProvider).retry(a.id),
            ),
          IconButton(
            tooltip: '删除附件',
            icon: const Icon(Icons.delete_outline),
            onPressed: _remove,
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(AttachmentView a) {
    if (a.isImage) return Icons.image_outlined;
    if (a.mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (a.mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (a.mime.startsWith('video/')) return Icons.movie_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

/// 文件大小的易读形式。
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
