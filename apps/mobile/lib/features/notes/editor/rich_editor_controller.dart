import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../app/theme/jk_tokens.g.dart';
import '../../../core/sync/refs.dart';

/// 富文本编辑器（WebView 中的 Tiptap）的格式命令，与 `apps/note-editor/src/protocol.ts` 一致。
enum RichCommand {
  bold,
  italic,
  strike,
  code,
  paragraph,
  heading1,
  heading2,
  heading3,
  bulletList,
  orderedList,
  taskList,
  blockquote,
  codeBlock,
  horizontalRule,
  insertTable,
  addRowAfter,
  addColumnAfter,
  deleteRow,
  deleteColumn,
  deleteTable,
  unsetLink,
  undo,
  redo,
}

/// 光标处的格式状态（用于高亮工具栏按钮）。
@immutable
class FormatState {
  const FormatState({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.heading = 0,
    this.bulletList = false,
    this.orderedList = false,
    this.taskList = false,
    this.blockquote = false,
    this.codeBlock = false,
    this.inTable = false,
    this.link,
    this.canUndo = false,
    this.canRedo = false,
  });

  factory FormatState.fromJson(Map<String, dynamic> j) {
    bool b(String k) => j[k] == true;
    final h = j['heading'];
    final link = j['link'];
    return FormatState(
      bold: b('bold'),
      italic: b('italic'),
      strike: b('strike'),
      code: b('code'),
      heading: h is int && h >= 0 && h <= 3 ? h : 0,
      bulletList: b('bulletList'),
      orderedList: b('orderedList'),
      taskList: b('taskList'),
      blockquote: b('blockquote'),
      codeBlock: b('codeBlock'),
      inTable: b('inTable'),
      link: link is String ? link : null,
      canUndo: b('canUndo'),
      canRedo: b('canRedo'),
    );
  }

  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final int heading;
  final bool bulletList;
  final bool orderedList;
  final bool taskList;
  final bool blockquote;
  final bool codeBlock;
  final bool inTable;
  final String? link;
  final bool canUndo;
  final bool canRedo;
}

/// 链接只允许 http(s)、mailto、tel（编辑器一侧同样校验）。
bool isSafeLink(String href) =>
    href.length <= 2048 &&
    RegExp(r'^(https?:|mailto:|tel:)', caseSensitive: false).hasMatch(href);

/// 编辑器主题：CSS 变量（--jk-*）→ 颜色。
Map<String, Object> editorTheme(JkColorTokens c, {required bool dark}) {
  String hex(Color color) {
    int ch(double v) => (v * 255).round().clamp(0, 255);
    final argb = [color.r, color.g, color.b, color.a].map(ch);
    return '#${argb.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
  }

  return {
    'dark': dark,
    'colors': {
      'background': hex(c.background),
      'surface-variant': hex(c.surfaceVariant),
      'text': hex(c.textPrimary),
      'text-secondary': hex(c.textSecondary),
      'text-disabled': hex(c.textDisabled),
      'primary': hex(c.primary),
      'border': hex(c.border),
      'selection': hex(c.primaryContainer),
    },
  };
}

/// 与 WebView 中编辑器的通信（ADR-007）。不依赖 WebView 本身，便于测试。
///
/// - [post]：执行 `window.jikelog.receive(json)`
/// - [evaluate]：执行一段 JavaScript 并返回结果（用于离开页面前取回尚未发出的修改）
class RichEditorController {
  RichEditorController({
    required this.onChange,
    required this.loadImage,
    this.onError,
    this.onSetApplied,
    this.onSetRejected,
  });

  /// 用户编辑后的 Markdown。
  final void Function(String markdown) onChange;

  /// 编辑器应用了 [setMarkdown]。
  final VoidCallback? onSetApplied;

  /// 编辑器拒绝了 [setMarkdown]：其中有尚未收到的修改（已先通过 [onChange] 送达），需要重新合并。
  final VoidCallback? onSetRejected;

  /// 已收到的最后一次修改的序号（编辑器每次初始化后从 1 开始）。
  int _rev = 0;

  /// 取得附件图片的 data: 地址；无法显示时返回 null。
  final Future<String?> Function(String attachmentId) loadImage;
  final void Function(String message)? onError;

  final format = ValueNotifier(const FormatState());

  /// 编辑器页面已加载并完成初始化。
  final ready = ValueNotifier(false);

  Future<void> Function(String js)? _run;
  Future<Object?> Function(String js)? _evaluate;

  /// 初始化消息。其中的正文随修改与替换更新：页面重新加载（例如 WebView 渲染进程重建）时用最新内容初始化。
  Map<String, Object>? _pendingInit;

  /// 已发出、尚未收到确认的替换。
  bool _awaitingAck = false;
  bool _disposed = false;

  /// 取回编辑器内容的超时：WebView 卡死时不能让离开页面一直等待。
  static const flushTimeout = Duration(seconds: 2);

  /// 连接到 WebView。页面加载完成（收到 ready）后发送初始化消息。
  void attach({
    required Future<void> Function(String js) run,
    required Future<Object?> Function(String js) evaluate,
  }) {
    _run = run;
    _evaluate = evaluate;
  }

  /// 设置初始内容与主题（页面就绪前调用时，就绪后再发送）。
  void init({
    required String markdown,
    required String placeholder,
    required Map<String, Object> theme,
  }) {
    _rev = 0;
    _awaitingAck = false;
    _pendingInit = {
      'type': 'init',
      'markdown': markdown,
      'placeholder': placeholder,
      'theme': theme,
    };
    if (ready.value) _sendInit();
  }

  void _sendInit() {
    final m = _pendingInit;
    if (m != null) unawaited(_send(m));
  }

  Future<void> _send(Map<String, Object?> message) async {
    final run = _run;
    if (run == null) return;
    // JSON 字符串再编码一次，作为 JavaScript 字符串字面量传入，不拼接任何代码
    await run(
      'window.jikelog && window.jikelog.receive(${jsonEncode(jsonEncode(message))})',
    );
  }

  void _remember(String markdown) {
    final init = _pendingInit;
    if (init != null) _pendingInit = {...init, 'markdown': markdown};
  }

  /// 处理编辑器发来的消息（JavaScript 通道）。格式不对的消息、销毁后迟到的消息忽略。
  Future<void> handleMessage(String raw) async {
    if (_disposed) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['type']) {
      case 'ready':
        ready.value = true;
        _rev = 0;
        _sendInit();
        if (_focusOnReady && _pendingInit != null) {
          _focusOnReady = false;
          unawaited(_send({'type': 'focus'}));
        }
        // 页面重新加载：初始化内容已包含等待确认的替换
        if (_awaitingAck) {
          _awaitingAck = false;
          onSetApplied?.call();
        }
      case 'change':
        final md = decoded['markdown'];
        final rev = decoded['rev'];
        if (md is String && rev is int) {
          _rev = rev;
          _remember(md);
          onChange(md);
        }
      case 'setApplied':
        _awaitingAck = false;
        onSetApplied?.call();
      case 'setRejected':
        _awaitingAck = false;
        onSetRejected?.call();
      case 'state':
        final s = decoded['state'];
        if (s is Map<String, dynamic>) format.value = FormatState.fromJson(s);
      case 'requestImage':
        final id = decoded['id'];
        if (id is String && isUuid(id)) await _answerImage(id);
      case 'error':
        final msg = decoded['message'];
        if (msg is String) onError?.call(msg);
    }
  }

  Future<void> _answerImage(String id) async {
    String? dataUrl;
    try {
      dataUrl = await loadImage(id);
    } on Object catch (e) {
      debugPrint('读取笔记图片失败: $e');
    }
    await _send({'type': 'image', 'id': id, 'dataUrl': dataUrl});
  }

  /// 用其他设备的修改（或合并结果）替换内容。编辑器中有尚未收到的修改时会被拒绝（[onSetRejected]）。
  ///
  /// 页面尚未就绪时只更新初始化内容，并立即确认（就绪后用新内容初始化，不会再有回复）。
  Future<void> setMarkdown(String markdown) async {
    _remember(markdown);
    if (!ready.value) {
      onSetApplied?.call();
      return;
    }
    _awaitingAck = true;
    await _send({
      'type': 'setMarkdown',
      'markdown': markdown,
      'expectRev': _rev,
    });
  }

  Future<void> run(RichCommand c) => _send({'type': 'command', 'name': c.name});

  /// 设置链接。不安全的地址返回 false。
  Future<bool> setLink(String href) async {
    final h = href.trim();
    if (!isSafeLink(h)) return false;
    await _send({'type': 'setLink', 'href': h});
    return true;
  }

  Future<void> insertImage(String attachmentId, String alt) =>
      _send({'type': 'insertImage', 'id': attachmentId, 'alt': alt});

  Future<void> setTheme(Map<String, Object> theme) async {
    final init = _pendingInit;
    if (init != null) _pendingInit = {...init, 'theme': theme};
    if (ready.value) await _send({'type': 'theme', 'theme': theme});
  }

  bool _focusOnReady = false;

  /// 聚焦到文末。页面尚未就绪时，就绪并初始化后再聚焦。
  Future<void> focus() async {
    if (!ready.value) {
      _focusOnReady = true;
      return;
    }
    await _send({'type': 'focus'});
  }

  /// 立即取回尚未发出的修改（离开页面、切换格式前）。没有时返回 null。
  Future<String?> flush() async {
    final evaluate = _evaluate;
    if (evaluate == null || !ready.value) return null;
    try {
      final r = await evaluate(
        'JSON.stringify({c: window.jikelog ? window.jikelog.flush() : null})',
      ).timeout(flushTimeout);
      // 结果包在对象里再解码：Android 的 WebView 会把字符串结果再包一层 JSON 引号，
      // 直接返回正文时无法区分"正文恰好是合法 JSON"与"多包了一层"
      Object? v = r;
      for (var i = 0; i < 2 && v is String; i++) {
        v = jsonDecode(v);
      }
      final c = v is Map<String, dynamic> ? v['c'] : null;
      if (c is! Map<String, dynamic>) return null;
      final md = c['md'];
      final rev = c['rev'];
      if (md is! String || rev is! int) return null;
      _rev = rev;
      _remember(md);
      return md;
    } on Object catch (e) {
      debugPrint('取回编辑器内容失败: $e');
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    format.dispose();
    ready.dispose();
    _run = null;
    _evaluate = null;
  }
}
