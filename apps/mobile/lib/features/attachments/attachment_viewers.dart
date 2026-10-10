import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_button.dart';
import '../../shared/ui/jk_feedback.dart';
import 'attachment_images.dart';
import 'attachment_service.dart';
import 'media.dart';

/// 用系统中的应用打开文件（测试中替换）。返回 false 表示没有可用的应用。
final openExternalProvider = Provider<Future<bool> Function(File, String)>(
  (_) =>
      (file, mime) async =>
          (await OpenFilex.open(file.path, type: mime)).type == ResultType.done,
);

/// 按类型打开附件：图片全屏查看，PDF 在 App 内阅读，音频在 App 内播放，其他文件交给系统应用。
Future<void> showAttachment(
  BuildContext context,
  WidgetRef ref,
  AttachmentView a,
  File file,
) async {
  final nav = Navigator.of(context);
  if (a.isImage) {
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerPage(file: file, title: a.fileName),
      ),
    );
  } else if (a.mime == 'application/pdf') {
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PdfViewerPage(file: file, title: a.fileName, mime: a.mime),
      ),
    );
  } else if (a.mime.startsWith('audio/')) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => AudioPlayerSheet(file: file, title: a.fileName),
    );
  } else if (!await ref.read(openExternalProvider)(file, a.mime) &&
      context.mounted) {
    showJkToast(context, '没有可以打开该文件的应用');
  }
}

/// 图片全屏查看，可缩放。
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.file, required this.title});

  final File file;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
    body: InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image.file(
          file,
          errorBuilder: (_, _, _) => const Text('图片无法显示'),
        ),
      ),
    ),
  );
}

/// PDF 阅读。
class PdfViewerPage extends ConsumerWidget {
  const PdfViewerPage({
    super.key,
    required this.file,
    required this.title,
    required this.mime,
  });

  final File file;
  final String title;
  final String mime;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(title, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: '用其他应用打开',
          icon: const Icon(Icons.open_in_new),
          onPressed: () async {
            if (!await ref.read(openExternalProvider)(file, mime) &&
                context.mounted) {
              showJkToast(context, '没有可以打开该文件的应用');
            }
          },
        ),
      ],
    ),
    body: ref.watch(pdfViewBuilderProvider)(file),
  );
}

String _clock(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// 音频播放。
class AudioPlayerSheet extends ConsumerStatefulWidget {
  const AudioPlayerSheet({super.key, required this.file, required this.title});

  final File file;
  final String title;

  @override
  ConsumerState<AudioPlayerSheet> createState() => _AudioPlayerSheetState();
}

class _AudioPlayerSheetState extends ConsumerState<AudioPlayerSheet> {
  late final Player _player = ref.read(playerFactoryProvider)();
  final _subs = <StreamSubscription<Object>>[];
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.position.listen((p) => setState(() => _position = p)))
      ..add(_player.playing.listen((v) => setState(() => _playing = v)));
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await _player.load(widget.file.path);
      if (!mounted) return;
      setState(() => _duration = d ?? Duration.zero);
      await _player.play();
    } on Object catch (e) {
      debugPrint('音频无法播放: $e');
      if (mounted) setState(() => _error = '无法播放该音频');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = _duration.inMilliseconds.toDouble();
    final pos = _position.inMilliseconds.clamp(0, max).toDouble();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          JkTokens.spacingLg,
          0,
          JkTokens.spacingLg,
          JkTokens.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(JkTokens.spacingLg),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.jkColors.error),
                ),
              )
            else ...[
              Slider(
                key: const Key('audio-seek'),
                value: pos,
                max: max <= 0 ? 1 : max,
                onChanged: max <= 0
                    ? null
                    : (v) => _player.seek(Duration(milliseconds: v.round())),
              ),
              Row(
                children: [
                  Text(_clock(_position)),
                  const Spacer(),
                  IconButton.filled(
                    key: const Key('audio-toggle'),
                    iconSize: 32,
                    tooltip: _playing ? '暂停' : '播放',
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    onPressed: _playing ? _player.pause : _player.play,
                  ),
                  const Spacer(),
                  Text(_clock(_duration)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 录音：返回录好的文件（取消或失败时为 null）。
class RecorderSheet extends ConsumerStatefulWidget {
  const RecorderSheet({super.key});

  @override
  ConsumerState<RecorderSheet> createState() => _RecorderSheetState();
}

class _RecorderSheetState extends ConsumerState<RecorderSheet> {
  late final Recorder _recorder = ref.read(recorderFactoryProvider)();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  String? _error;

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = '没有麦克风权限，请在系统设置中允许即刻日志使用麦克风');
        return;
      }
      final dir = await ref.read(recordingDirProvider)();
      final now = DateTime.now();
      final name =
          '录音 ${now.year}-${_two(now.month)}-${_two(now.day)} '
          '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.m4a';
      await _recorder.start(p.join(dir.path, name));
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _elapsed += const Duration(seconds: 1)),
      );
      setState(() {
        _recording = true;
        _error = null;
      });
    } on Object catch (e) {
      debugPrint('录音失败: $e');
      if (mounted) setState(() => _error = '无法开始录音');
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _recording = false;
    final path = await _recorder.stop();
    if (!mounted) return;
    Navigator.of(context).pop(path == null ? null : File(path));
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _discard() async {
    try {
      final path = await _recorder.stop();
      if (path != null) await File(path).delete();
    } on Object catch (e) {
      debugPrint('丢弃录音失败: $e');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // 未保存就关闭：停止录音并丢弃文件
    if (_recording) {
      unawaited(_discard());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        0,
        JkTokens.spacingLg,
        JkTokens.spacingLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('录音', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: JkTokens.spacingLg),
          Text(
            _clock(_elapsed),
            key: const Key('recorder-elapsed'),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: JkTokens.spacingSm),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.jkColors.error),
              ),
            ),
          const SizedBox(height: JkTokens.spacingLg),
          JkButton(
            key: const Key('recorder-toggle'),
            label: _recording ? '停止并保存' : '开始录音',
            onPressed: _recording ? _stop : _start,
          ),
        ],
      ),
    ),
  );
}

/// 正文中的附件图片（Markdown 预览）。
class AttachmentImage extends ConsumerWidget {
  const AttachmentImage({super.key, required this.id, this.alt});

  final String id;
  final String? alt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    Widget placeholder(String text) => Container(
      padding: const EdgeInsets.all(JkTokens.spacingMd),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
      ),
      child: Text(text, style: TextStyle(color: c.textSecondary)),
    );
    return ref
        .watch(attachmentFileProvider(id))
        .when(
          loading: () => placeholder('图片加载中…'),
          error: (_, _) => placeholder(
            '图片无法显示${alt == null || alt!.isEmpty ? '' : '：$alt'}',
          ),
          data: (file) => ClipRRect(
            borderRadius: BorderRadius.circular(JkTokens.radiusMd),
            child: Image.file(
              file,
              semanticLabel: alt,
              errorBuilder: (_, _, _) => placeholder('图片无法显示'),
            ),
          ),
        );
  }
}

/// Markdown 预览中的图片：attachment: 引用显示附件图片；网络图片不加载（与富文本编辑器一致）。
Widget markdownImage(Uri uri, String? title, String? alt) {
  if (uri.scheme == 'attachment') {
    return AttachmentImage(id: uri.path, alt: alt);
  }
  return Text('[图片${alt == null || alt.isEmpty ? '' : '：$alt'}]');
}
