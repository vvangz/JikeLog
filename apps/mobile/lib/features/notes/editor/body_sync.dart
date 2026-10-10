import 'dart:async';

import '../../../core/sync/text_patch.dart';

/// 已发给编辑器、尚未确认的一次替换。
class _Pending {
  const _Pending({
    required this.from,
    required this.target,
    required this.remote,
  });

  /// 发出替换时编辑器中的内容（被拒绝时，编辑器中是它加上之后的输入）。
  final String from;

  /// 替换的内容。
  final String target;

  /// 计算 [target] 时依据的本机记录。
  final String remote;
}

/// 编辑中正文的保存与合并（Markdown 与富文本两种编辑方式共用）。
///
/// - 输入停止 [autosave] 后保存到本机；离开页面时立即保存（[flush] 传 force）
/// - 其他设备的修改到达时：没有未保存的输入就直接显示；有未保存的输入时，
///   把本地输入（相对它所基于的版本）合并到新内容上，与工作日志编辑页相同
///
/// 富文本编辑器的替换是异步的，可能被拒绝（编辑器中有尚未送达的输入，ADR-007）：
/// 编辑器先送来这些输入（[edited]），再回复拒绝（[rejected]），此时以发出替换时的内容为基准
/// 把这些输入合并到替换内容上再试。Markdown 编辑器的替换是同步的，[show] 之后立即调用 [applied]。
class BodySync {
  BodySync({
    required String initial,
    required this.save,
    required this.show,
    this.onConflict,
    this.autosave = const Duration(seconds: 1),
  }) : _saved = initial,
       _local = initial,
       _base = initial;

  /// 保存到本机。
  final Future<void> Function(String body) save;

  /// 在编辑器中显示（替换）内容。
  final void Function(String body) show;

  /// 双方改了同一处、无法合并：保留本地输入（保存时按最后修改覆盖），对方的版本可在修订历史中找回。
  final void Function()? onConflict;
  final Duration autosave;

  /// 本机记录中的正文（最后一次保存或读到的值）。
  String _saved;

  /// 编辑器中的内容（最新收到的）。
  String _local;

  /// 编辑器内容所基于的本机记录版本：编辑器内容 = 基准 + 尚未保存的输入。
  String _base;
  _Pending? _pending;
  Timer? _timer;
  bool _closed = false;

  String get local => _local;
  bool get hasUnsaved => _local != _saved;

  /// 用户输入（编辑器中的完整内容）。
  void edited(String body) {
    if (_closed || body == _local) return;
    _local = body;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(autosave, () => unawaited(flush()));
  }

  /// 保存尚未保存的输入。等待编辑器确认替换期间推迟，除非 [force]（离开页面时）。
  Future<void> flush({bool force = false}) async {
    _timer?.cancel();
    if (_closed || _local == _saved) return;
    if (_pending != null && !force) {
      _schedule();
      return;
    }
    _saved = _local;
    if (_pending == null) _base = _local;
    await save(_local);
  }

  /// 本机记录中的正文变化（其他设备的修改、同步合并的结果）。
  void remote(String body) {
    if (_closed || body == _saved) return;
    _saved = body;
    // 等待确认期间先记下，确认或拒绝后再合并
    if (_pending == null) _merge();
  }

  void _merge() {
    if (_local == _base) {
      if (_local != _saved) _replace(_saved);
      return;
    }
    final merged = TextPatch.rebase(_base, _local, _saved);
    if (merged.ok) {
      _replace(merged.text);
      _schedule(); // 合并结果与本机记录不同，需要保存
    } else {
      _conflict();
    }
  }

  void _conflict() {
    _base = _saved;
    _schedule();
    onConflict?.call();
  }

  void _replace(String target) {
    _pending = _Pending(from: _local, target: target, remote: _saved);
    _local = target;
    show(target);
  }

  /// 编辑器确认了替换：之后的输入基于替换依据的本机记录。
  void applied() {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    _base = p.remote;
    if (_saved != p.remote) _merge(); // 等待期间又有新的修改到达
  }

  /// 编辑器拒绝了替换：编辑器中是 [_Pending.from] 加上之后的输入，把这些输入合并到替换内容上再试。
  void rejected() {
    final p = _pending;
    if (_closed || p == null) return;
    _pending = null;
    // 编辑器中的当前内容（拒绝前送来的输入）；没有送来新输入时仍是替换前的内容
    final editor = _local == p.target ? p.from : _local;
    final merged = TextPatch.rebase(p.from, editor, p.target);
    if (!merged.ok) {
      _local = editor;
      _conflict();
      return;
    }
    _pending = _Pending(from: editor, target: merged.text, remote: p.remote);
    _local = merged.text;
    show(merged.text);
    _schedule();
  }

  /// 停止：之后不再保存（记录已删除时）。
  void close() {
    _closed = true;
    _timer?.cancel();
  }

  void dispose() => _timer?.cancel();
}
