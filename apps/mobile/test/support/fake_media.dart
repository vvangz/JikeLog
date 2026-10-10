import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:jikelog/features/attachments/media.dart';
import 'package:jikelog/features/notes/editor/rich_editor_controller.dart';

/// 假的富文本编辑器：按 apps/note-editor 的消息协议应答，用纯文本模拟正文（组件测试中没有 WebView）。
class FakeRichEditor {
  FakeRichEditor(this.controller);

  /// 最近打开的编辑器（测试中用来模拟输入）。
  static FakeRichEditor? current;

  final RichEditorController controller;
  String markdown = '';
  int _rev = 0;

  /// 有尚未发给 Flutter 的输入（模拟 250 毫秒防抖期间）。
  bool unsent = false;
  final received = <Map<String, dynamic>>[];

  void attach() {
    controller.attach(run: _run, evaluate: _evaluate);
    scheduleMicrotask(() => controller.handleMessage('{"type":"ready"}'));
  }

  void _emit(Map<String, Object?> m) =>
      unawaited(controller.handleMessage(jsonEncode(m)));

  Future<void> _run(String js) async {
    final m = RegExp(r'receive\((.*)\)$').firstMatch(js)!;
    final msg = jsonDecode(jsonDecode(m[1]!) as String) as Map<String, dynamic>;
    received.add(msg);
    switch (msg['type']) {
      case 'init':
        markdown = msg['markdown'] as String;
        _rev = 0;
        unsent = false;
      case 'setMarkdown':
        if (unsent) _send();
        if (_rev != msg['expectRev']) {
          _emit({'type': 'setRejected'});
        } else {
          markdown = msg['markdown'] as String;
          _emit({'type': 'setApplied'});
        }
      case 'command':
        final name = msg['name'];
        if (name == 'heading1') markdown = '# $markdown';
        if (name == 'insertTable') markdown = '$markdown\n\n| a | b |';
        _changed();
      case 'insertImage':
        markdown = '$markdown\n\n![${msg['alt']}](attachment:${msg['id']})'
            .trim();
        _changed();
      case 'setLink':
        markdown = '$markdown[${msg['href']}](${msg['href']})';
        _changed();
    }
  }

  void _changed() {
    unsent = true;
    _send();
  }

  /// 模拟用户输入；[deliver] 为 false 时先不发出（停留在防抖期间）。
  void type(String text, {bool deliver = true}) {
    markdown = text;
    unsent = true;
    if (deliver) _send();
  }

  void _send() {
    if (!unsent) return;
    unsent = false;
    _rev++;
    _emit({'type': 'change', 'markdown': markdown, 'rev': _rev});
  }

  void requestImage(String id) => _emit({'type': 'requestImage', 'id': id});

  void reportState(Map<String, Object?> state) =>
      _emit({'type': 'state', 'state': state});

  Future<Object?> _evaluate(String js) async {
    if (!unsent) return jsonEncode(jsonEncode({'c': null}));
    unsent = false;
    _rev++;
    // 与 Android 的 WebView 一样多包一层 JSON 引号
    return jsonEncode(
      jsonEncode({
        'c': {'md': markdown, 'rev': _rev},
      }),
    );
  }
}

class FakeRichEditorView extends StatefulWidget {
  const FakeRichEditorView({super.key, required this.controller});

  final RichEditorController controller;

  @override
  State<FakeRichEditorView> createState() => _FakeRichEditorViewState();
}

class _FakeRichEditorViewState extends State<FakeRichEditorView> {
  late final FakeRichEditor editor = FakeRichEditor(widget.controller);

  @override
  void initState() {
    super.initState();
    FakeRichEditor.current = editor;
    editor.attach();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key('fake-rich-editor'));
}

class FakeRecorder implements Recorder {
  FakeRecorder({this.permitted = true});

  final bool permitted;
  String? _path;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> start(String path) async {
    _path = path;
    await File(path).writeAsBytes(List.filled(64, 7));
  }

  @override
  Future<String?> stop() async {
    final p = _path;
    _path = null;
    return p;
  }

  @override
  Future<void> dispose() async {}
}

class FakePlayer implements Player {
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final calls = <String>[];

  @override
  Future<Duration?> load(String path) async {
    calls.add('load');
    return const Duration(seconds: 90);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _playing.add(true);
    _position.add(const Duration(seconds: 3));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    _position.add(position);
  }

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _position.close();
    await _playing.close();
  }
}

/// 测试用的已选文件（file_picker 的结果）。
final class TestPickedFile extends PlatformFile {
  TestPickedFile(this.file);

  final File file;

  @override
  String get name => file.uri.pathSegments.last;

  @override
  Uri get uri => file.uri;

  @override
  XFile get xFile => XFile(file.path);

  @override
  int? lengthSync() => file.lengthSync();

  @override
  Future<int?> length() => file.length();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}

/// 1×1 的 PNG 图片。
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
