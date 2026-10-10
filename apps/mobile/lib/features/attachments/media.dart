import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:record/record.dart';

/// 录音（record 插件）。抽成接口：组件测试中没有平台插件，用假实现替换。
abstract interface class Recorder {
  /// 请求麦克风权限，用户拒绝时返回 false。
  Future<bool> hasPermission();

  /// 开始录音，写入 [path]（AAC，.m4a）。
  Future<void> start(String path);

  /// 停止录音，返回文件路径；没有在录音时返回 null。
  Future<String?> stop();

  Future<void> dispose();
}

class PluginRecorder implements Recorder {
  final _r = AudioRecorder();

  @override
  Future<bool> hasPermission() => _r.hasPermission();

  @override
  Future<void> start(String path) =>
      _r.start(const RecordConfig(numChannels: 1, bitRate: 96000), path: path);

  @override
  Future<String?> stop() => _r.stop();

  @override
  Future<void> dispose() => _r.dispose();
}

/// 音频播放（just_audio 插件）。
abstract interface class Player {
  /// 加载文件，返回时长（未知时为 null）。
  Future<Duration?> load(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get position;

  /// 是否正在播放；播放到结尾时为 false。
  Stream<bool> get playing;
  Future<void> dispose();
}

class PluginPlayer implements Player {
  final _p = AudioPlayer();

  @override
  Future<Duration?> load(String path) => _p.setFilePath(path);

  @override
  Future<void> play() async {
    // 播放到结尾后再次播放从头开始
    if (_p.processingState == ProcessingState.completed) {
      await _p.seek(Duration.zero);
    }
    unawaited(_p.play());
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  Stream<Duration> get position => _p.positionStream;

  @override
  Stream<bool> get playing => _p.playerStateStream.map(
    (s) => s.playing && s.processingState != ProcessingState.completed,
  );

  @override
  Future<void> dispose() => _p.dispose();
}

/// 录音的临时目录（保存为附件后删除），测试中替换。
final recordingDirProvider = Provider<Future<Directory> Function()>(
  (_) => getTemporaryDirectory,
);

final recorderFactoryProvider = Provider<Recorder Function()>(
  (_) => PluginRecorder.new,
);

final playerFactoryProvider = Provider<Player Function()>(
  (_) => PluginPlayer.new,
);

/// PDF 阅读视图（pdfx）。
final pdfViewBuilderProvider = Provider<Widget Function(File file)>(
  (_) =>
      (file) => _PdfView(file: file),
);

class _PdfView extends StatefulWidget {
  const _PdfView({required this.file});

  final File file;

  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView> {
  late final _controller = PdfControllerPinch(
    document: PdfDocument.openFile(widget.file.path),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PdfViewPinch(controller: _controller);
}
