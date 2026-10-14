import 'package:audioplayers/audioplayers.dart' as ap;

import 'media.dart';

/// Windows 上的音频播放（audioplayers，基于 Media Foundation）。
/// just_audio 没有 Windows 实现，第三方的 just_audio_windows 已无法用新版 MSVC 编译（ADR-013）。
class DesktopPlayer implements Player {
  final _p = ap.AudioPlayer();

  @override
  Future<Duration?> load(String path) async {
    await _p.setSource(ap.DeviceFileSource(path));
    return _p.getDuration();
  }

  @override
  Future<void> play() async {
    // 播放到结尾后再次播放从头开始
    if (_p.state == ap.PlayerState.completed) {
      await _p.seek(Duration.zero);
    }
    await _p.resume();
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  Stream<Duration> get position => _p.onPositionChanged;

  @override
  Stream<bool> get playing =>
      _p.onPlayerStateChanged.map((s) => s == ap.PlayerState.playing);

  @override
  Future<void> dispose() => _p.dispose();
}
