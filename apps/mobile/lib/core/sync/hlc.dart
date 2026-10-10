import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 混合逻辑时钟（HLC），格式与服务端一致：`<13 位毫秒>-<4 位十六进制计数>-<16 位十六进制节点>`，
/// 按字符串比较即为先后顺序（ADR-005）。
///
/// 收到其他设备的时钟后推进自己的时钟，即使本机时间略慢，新的修改也排在后面。
class HybridClock {
  HybridClock({
    required String installationId,
    int Function()? nowMs,
    String? last,
  }) : node = nodeOf(installationId),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (last != null) receive(last, trustFuture: true);
  }

  /// 节点标识：安装实例 ID 的 SHA-256 前 8 字节。
  final String node;
  final int Function() _nowMs;
  int _ms = 0;
  int _counter = 0;

  /// 远端时钟领先本机超过该值时不跟随（防止一台时间错乱的设备把所有设备带偏，
  /// 也避免本机推送的时钟超出服务端允许的偏差）。
  static const _maxForwardMs = 4 * 60 * 1000;

  static String nodeOf(String installationId) => sha256
      .convert(utf8.encode(installationId))
      .bytes
      .take(8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  static final _pattern = RegExp(r'^(\d{13})-([0-9a-f]{4})-([0-9a-f]{16})$');

  static bool isValid(String s) => _pattern.hasMatch(s);

  /// 生成一个新的时钟值，严格大于之前生成或收到的所有值。
  String now() {
    final pt = _nowMs();
    if (pt > _ms) {
      _ms = pt;
      _counter = 0;
    } else {
      _counter++;
      if (_counter > 0xffff) {
        _ms++;
        _counter = 0;
      }
    }
    return format(_ms, _counter, node);
  }

  /// 收到其他设备的时钟后推进本地时钟。[trustFuture] 用于从本地持久化恢复。
  void receive(String remote, {bool trustFuture = false}) {
    final m = _pattern.firstMatch(remote);
    if (m == null) return;
    final ms = int.parse(m.group(1)!);
    final counter = int.parse(m.group(2)!, radix: 16);
    if (!trustFuture && ms - _nowMs() > _maxForwardMs) return;
    if (ms > _ms || (ms == _ms && counter > _counter)) {
      _ms = ms;
      _counter = counter;
    }
  }

  /// 当前时钟（用于持久化，重启后保持单调）。
  String get last => format(max(_ms, 0), _counter, node);

  static String format(int ms, int counter, String node) =>
      '${ms.toString().padLeft(13, '0')}-'
      '${counter.toRadixString(16).padLeft(4, '0')}-$node';
}
