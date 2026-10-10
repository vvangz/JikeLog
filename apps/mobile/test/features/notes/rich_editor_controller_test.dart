import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/theme/jk_tokens.g.dart';
import 'package:jikelog/features/notes/editor/rich_editor_controller.dart';

const _id = '0190a1b2-0000-7000-8000-000000000001';

/// 假的 WebView：记录发给编辑器的消息，模拟 evaluate 的返回值。
class _FakeWebView {
  final sent = <Map<String, dynamic>>[];
  Object? evaluateResult;
  final scripts = <String>[];

  Future<void> run(String js) async {
    scripts.add(js);
    final m = RegExp(r'receive\((.*)\)$').firstMatch(js)!;
    sent.add(jsonDecode(jsonDecode(m[1]!) as String) as Map<String, dynamic>);
  }

  Future<Object?> evaluate(String js) async => evaluateResult;
}

void main() {
  late _FakeWebView web;
  late RichEditorController c;
  late List<String> changes;
  late List<String> errors;
  final images = <String, String?>{};

  setUp(() {
    web = _FakeWebView();
    changes = [];
    errors = [];
    c = RichEditorController(
      onChange: changes.add,
      loadImage: (id) async {
        if (id == 'boom') throw StateError('x');
        return images[id];
      },
      onError: errors.add,
    )..attach(run: web.run, evaluate: web.evaluate);
  });

  tearDown(() => c.dispose());

  test('页面就绪后才发送初始化；就绪后再初始化立即发送', () async {
    c.init(markdown: '# 你好', placeholder: '写点什么', theme: {'dark': false});
    expect(web.sent, isEmpty);
    await c.handleMessage('{"type":"ready"}');
    expect(c.ready.value, isTrue);
    expect(web.sent.single, {
      'type': 'init',
      'markdown': '# 你好',
      'placeholder': '写点什么',
      'theme': {'dark': false},
    });
    c.init(markdown: '第二篇', placeholder: '', theme: {'dark': true});
    await Future<void>.delayed(Duration.zero);
    expect(web.sent.last['markdown'], '第二篇');
  });

  test('正文作为字符串字面量传入，不会被当作代码执行', () async {
    await c.handleMessage('{"type":"ready"}');
    await c.setMarkdown("');alert(1);//</script>");
    expect(
      web.scripts.single,
      startsWith('window.jikelog && window.jikelog.receive("'),
    );
    expect(web.sent.single['markdown'], "');alert(1);//</script>");
  });

  test('修改、格式状态与错误', () async {
    await c.handleMessage(
      jsonEncode({'type': 'change', 'markdown': '## 改了', 'rev': 1}),
    );
    expect(changes, ['## 改了']);
    await c.handleMessage(
      jsonEncode({
        'type': 'state',
        'state': {
          'bold': true,
          'heading': 2,
          'link': 'https://a.b',
          'canUndo': true,
        },
      }),
    );
    expect(c.format.value.bold, isTrue);
    expect(c.format.value.heading, 2);
    expect(c.format.value.link, 'https://a.b');
    expect(c.format.value.canUndo, isTrue);
    expect(c.format.value.italic, isFalse);
    await c.handleMessage(jsonEncode({'type': 'error', 'message': '坏消息'}));
    expect(errors, ['坏消息']);
  });

  test('忽略格式不对的消息', () async {
    for (final raw in [
      'not json',
      '[]',
      '{"type":"change","markdown":1,"rev":1}',
      '{"type":"change","markdown":"缺少序号"}',
      '{"type":"state","state":"x"}',
      '{"type":"requestImage","id":"../x"}',
      '{"type":"unknown"}',
    ]) {
      await c.handleMessage(raw);
    }
    expect(changes, isEmpty);
    expect(web.sent, isEmpty);
    expect(
      FormatState.fromJson(const {'heading': 9}).heading,
      0,
      reason: '标题级别超出范围时按正文处理',
    );
  });

  test('编辑器请求图片：返回 data 地址；取不到或出错时返回 null', () async {
    images[_id] = 'data:image/png;base64,AAAA';
    await c.handleMessage(jsonEncode({'type': 'requestImage', 'id': _id}));
    expect(web.sent.last, {
      'type': 'image',
      'id': _id,
      'dataUrl': 'data:image/png;base64,AAAA',
    });
    images.remove(_id);
    await c.handleMessage(jsonEncode({'type': 'requestImage', 'id': _id}));
    expect(web.sent.last['dataUrl'], isNull);
  });

  test('图片加载抛出异常时回复 null', () async {
    final c2 = RichEditorController(
      onChange: (_) {},
      loadImage: (_) async => throw StateError('下载失败'),
    )..attach(run: web.run, evaluate: web.evaluate);
    addTearDown(c2.dispose);
    await c2.handleMessage(jsonEncode({'type': 'requestImage', 'id': _id}));
    expect(web.sent.last, {'type': 'image', 'id': _id, 'dataUrl': null});
  });

  test('替换内容带上已收到的修改序号；被拒绝时通知页面重新合并', () async {
    var rejected = 0;
    var applied = 0;
    final c2 = RichEditorController(
      onChange: (_) {},
      loadImage: (_) async => null,
      onSetApplied: () => applied++,
      onSetRejected: () => rejected++,
    )..attach(run: web.run, evaluate: web.evaluate);
    addTearDown(c2.dispose);
    await c2.handleMessage('{"type":"ready"}');
    await c2.setMarkdown('远端');
    expect(web.sent.last, {
      'type': 'setMarkdown',
      'markdown': '远端',
      'expectRev': 0,
    });
    await c2.handleMessage(
      jsonEncode({'type': 'change', 'markdown': '本地', 'rev': 2}),
    );
    await c2.handleMessage('{"type":"setRejected"}');
    expect(rejected, 1);
    await c2.handleMessage('{"type":"setApplied"}');
    expect(applied, 1);
    await c2.setMarkdown('合并后');
    expect(web.sent.last['expectRev'], 2);
    c2.init(markdown: '', placeholder: '', theme: {'dark': false});
    await c2.setMarkdown('重新初始化后');
    expect(web.sent.last['expectRev'], 0);
  });

  test('页面就绪前的替换只更新初始化内容并立即确认；修改也会更新初始化内容', () async {
    var applied = 0;
    final c2 = RichEditorController(
      onChange: (_) {},
      loadImage: (_) async => null,
      onSetApplied: () => applied++,
    )..attach(run: web.run, evaluate: web.evaluate);
    addTearDown(c2.dispose);
    // 初始化之前设置主题不会产生残缺的初始化消息
    await c2.setTheme({'dark': true});
    c2.init(markdown: '打开时的内容', placeholder: '', theme: {'dark': false});
    await c2.setMarkdown('其他设备的修改');
    expect(applied, 1);
    expect(web.sent, isEmpty);
    await c2.handleMessage('{"type":"ready"}');
    expect(web.sent.single['type'], 'init');
    expect(web.sent.single['markdown'], '其他设备的修改');

    await c2.handleMessage(
      jsonEncode({'type': 'change', 'markdown': '本地输入', 'rev': 1}),
    );
    await c2.setTheme({'dark': true});
    // 渲染进程重建后页面重新就绪：用最新内容初始化，序号归零
    await c2.handleMessage('{"type":"ready"}');
    expect(web.sent.last['type'], 'init');
    expect(web.sent.last['markdown'], '本地输入');
    expect(web.sent.last['theme'], {'dark': true});
    await c2.setMarkdown('再次替换');
    expect(web.sent.last['expectRev'], 0);
  });

  test('等待确认时页面重新加载：初始化内容已包含替换，视为已确认', () async {
    var applied = 0;
    final c2 = RichEditorController(
      onChange: (_) {},
      loadImage: (_) async => null,
      onSetApplied: () => applied++,
    )..attach(run: web.run, evaluate: web.evaluate);
    addTearDown(c2.dispose);
    c2.init(markdown: '旧', placeholder: '', theme: {'dark': false});
    await c2.handleMessage('{"type":"ready"}');
    await c2.setMarkdown('新');
    expect(applied, 0);
    await c2.handleMessage('{"type":"ready"}');
    expect(applied, 1);
    expect(web.sent.last['markdown'], '新');
  });

  test('销毁后迟到的消息被忽略', () async {
    final got = <String>[];
    final c2 = RichEditorController(
      onChange: got.add,
      loadImage: (_) async => null,
    );
    c2.dispose();
    await c2.handleMessage(
      jsonEncode({'type': 'change', 'markdown': 'x', 'rev': 1}),
    );
    await c2.handleMessage('{"type":"ready"}');
    expect(got, isEmpty);
  });

  test('命令、链接、图片、主题、聚焦', () async {
    await c.handleMessage('{"type":"ready"}');
    await c.run(RichCommand.insertTable);
    expect(await c.setLink(' https://example.com '), isTrue);
    expect(await c.setLink('javascript:alert(1)'), isFalse);
    await c.insertImage(_id, '截图.png');
    await c.setTheme({'dark': true});
    await c.focus();
    expect(web.sent, [
      {'type': 'command', 'name': 'insertTable'},
      {'type': 'setLink', 'href': 'https://example.com'},
      {'type': 'insertImage', 'id': _id, 'alt': '截图.png'},
      {
        'type': 'theme',
        'theme': {'dark': true},
      },
      {'type': 'focus'},
    ]);
  });

  group('flush', () {
    setUp(() => c.handleMessage('{"type":"ready"}'));

    Object result(String md, int rev) => {
      'c': {'md': md, 'rev': rev},
    };

    test('Android：结果多包了一层 JSON 引号', () async {
      web.evaluateResult = jsonEncode(jsonEncode(result('# 内容', 1)));
      expect(await c.flush(), '# 内容');
    });

    test('其他平台：直接返回 JSON 字符串；正文恰好是合法 JSON 也不会误解析', () async {
      web.evaluateResult = jsonEncode(result('123', 1));
      expect(await c.flush(), '123');
      web.evaluateResult = jsonEncode(result('"引号"', 2));
      expect(await c.flush(), '"引号"');
    });

    test('取回的修改计入序号，之后的替换带上新序号', () async {
      web.evaluateResult = jsonEncode(result('本地', 3));
      await c.flush();
      await c.setMarkdown('合并后');
      expect(web.sent.last['expectRev'], 3);
    });

    test('WebView 没有响应时超时返回 null，不阻塞离开页面', () {
      fakeAsync((async) {
        final c2 = RichEditorController(
          onChange: (_) {},
          loadImage: (_) async => null,
        )..attach(run: web.run, evaluate: (_) => Completer<Object?>().future);
        unawaited(c2.handleMessage('{"type":"ready"}'));
        String? result = 'unset';
        unawaited(c2.flush().then((v) => result = v));
        async.elapse(RichEditorController.flushTimeout);
        expect(result, isNull);
        c2.dispose();
      });
    });

    test('没有尚未发出的修改、结果异常或未就绪时返回 null', () async {
      web.evaluateResult = jsonEncode({'c': null});
      expect(await c.flush(), isNull);
      web.evaluateResult = jsonEncode({
        'c': {'md': 1, 'rev': 1},
      });
      expect(await c.flush(), isNull);
      web.evaluateResult = 'not json';
      expect(await c.flush(), isNull);
      final idle = RichEditorController(
        onChange: (_) {},
        loadImage: (_) async => null,
      );
      addTearDown(idle.dispose);
      expect(await idle.flush(), isNull);
    });
  });

  test('未连接 WebView 时发送消息不报错', () async {
    final idle = RichEditorController(
      onChange: (_) {},
      loadImage: (_) async => null,
    );
    addTearDown(idle.dispose);
    await idle.run(RichCommand.bold);
  });

  test('主题颜色转成 CSS 十六进制', () {
    final t = editorTheme(JkColorTokens.light, dark: false);
    final colors = t['colors']! as Map<String, String>;
    expect(t['dark'], isFalse);
    expect(colors.keys, containsAll(['background', 'text', 'primary']));
    for (final v in colors.values) {
      expect(v, matches(RegExp(r'^#[0-9a-f]{8}$')));
    }
  });

  test('链接校验', () {
    expect(isSafeLink('mailto:a@b.c'), isTrue);
    expect(isSafeLink('TEL:10086'), isTrue);
    expect(isSafeLink('file:///etc'), isFalse);
  });
}
