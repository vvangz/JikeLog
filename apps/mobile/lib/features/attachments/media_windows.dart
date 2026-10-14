import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;

import 'media.dart';

/// Windows 上的音频播放（audioplayers，基于 Media Foundation）。
/// just_audio 没有 Windows 实现，第三方的 just_audio_windows 已无法用新版 MSVC 编译（ADR-013）。
/// 行为与 [PluginPlayer] 保持一致：暂停时拖动进度也会更新位置，播放到结尾后再次播放从头开始。
class DesktopPlayer implements Player {
  DesktopPlayer() {
    // 播放结束后保留音源，便于再次播放与拖动（默认的 release 会释放音源）
    unawaited(_p.setReleaseMode(ap.ReleaseMode.stop));
    _sub = _p.onPositionChanged.listen(_position.add);
  }

  final _p = ap.AudioPlayer();
  final _position = StreamController<Duration>.broadcast();
  late final StreamSubscription<Duration> _sub;

  @override
  Future<Duration?> load(String path) async {
    await _p.setSource(ap.DeviceFileSource(path));
    // 部分格式在加载后不能立即给出时长：等第一次时长通知
    return await _p.getDuration() ??
        await _p.onDurationChanged.first
            .timeout(const Duration(seconds: 2))
            .then<Duration?>((d) => d, onError: (Object _) => null);
  }

  @override
  Future<void> play() async {
    if (_p.state == ap.PlayerState.completed) await seek(Duration.zero);
    await _p.resume();
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(Duration position) async {
    await _p.seek(position);
    // audioplayers 只在播放时报告位置；暂停时拖动也要更新进度条
    _position.add(position);
  }

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<bool> get playing =>
      _p.onPlayerStateChanged.map((s) => s == ap.PlayerState.playing);

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    await _position.close();
    await _p.dispose();
  }
}
