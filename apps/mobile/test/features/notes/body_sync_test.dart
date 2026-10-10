import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/notes/editor/body_sync.dart';

/// 模拟编辑器：Markdown 模式同步替换；富文本模式由测试决定确认或拒绝。
class _Harness {
  _Harness(String initial, {this.sync = true}) {
    body = BodySync(
      initial: initial,
      save: (b) async => saved.add(b),
      show: (b) {
        shown.add(b);
        editor = b;
        if (sync) body.applied();
      },
      onConflict: () => conflicts++,
    );
    editor = initial;
  }

  final bool sync;
  late final BodySync body;
  late String editor;
  final saved = <String>[];
  final shown = <String>[];
  var conflicts = 0;

  void type(String text) {
    editor = text;
    body.edited(text);
  }
}

void main() {
  test('停止输入后自动保存；没有变化不保存', () {
    fakeAsync((async) {
      final h = _Harness('a');
      h.type('ab');
      async.elapse(const Duration(milliseconds: 500));
      h.type('abc');
      async.elapse(const Duration(milliseconds: 999));
      expect(h.saved, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(h.saved, ['abc']);
      expect(h.body.hasUnsaved, isFalse);
      h.body.edited('abc');
      async.elapse(const Duration(seconds: 2));
      expect(h.saved, ['abc']);
    });
  });

  test('没有未保存的输入：直接显示远端内容；与已保存的相同时忽略', () {
    fakeAsync((async) {
      final h = _Harness('第一段');
      h.body.remote('第一段');
      expect(h.shown, isEmpty);
      h.body.remote('第一段\n远端');
      expect(h.shown, ['第一段\n远端']);
      expect(h.body.local, '第一段\n远端');
      async.elapse(const Duration(seconds: 2));
      expect(h.saved, isEmpty, reason: '远端内容不需要再保存');
    });
  });

  test('有未保存的输入：合并后显示并保存合并结果', () {
    fakeAsync((async) {
      final h = _Harness('第一段\n第二段');
      h.type('第一段，本地\n第二段');
      h.body.remote('第一段\n第二段，远端');
      expect(h.shown.single, '第一段，本地\n第二段，远端');
      async.elapse(const Duration(seconds: 1));
      expect(h.saved, ['第一段，本地\n第二段，远端']);
    });
  });

  test('保存后再收到其他设备的修改：以已保存的内容为基准，不会重复插入', () {
    fakeAsync((async) {
      final h = _Harness('甲');
      h.type('甲乙');
      async.elapse(const Duration(seconds: 1));
      expect(h.saved, ['甲乙']);
      h.type('甲乙丙');
      h.body.remote('前言\n甲乙');
      expect(h.shown.last, '前言\n甲乙丙');
    });
  });

  test('双方改了同一处：保留本地输入，提示冲突，按最后修改覆盖', () {
    fakeAsync((async) {
      final h = _Harness('同一行');
      h.type('本地改了这一行');
      h.body.remote('远端也改了这一行');
      expect(h.conflicts, 1);
      expect(h.shown, isEmpty);
      expect(h.body.local, '本地改了这一行');
      async.elapse(const Duration(seconds: 1));
      expect(h.saved, ['本地改了这一行']);
    });
  });

  test('不能保存的内容（超过上限）不保存，删减后再保存', () async {
    final saved = <String>[];
    final b = BodySync(
      initial: '',
      save: (v) async => saved.add(v),
      show: (_) {},
      canSave: (v) => v.length <= 3,
    );
    b.edited('太长的内容');
    await b.flush(force: true);
    expect(saved, isEmpty);
    expect(b.hasUnsaved, isTrue);
    b.edited('短');
    await b.flush(force: true);
    expect(saved, ['短']);
    b.dispose();
  });

  test('离开页面立即保存；关闭后不再保存', () async {
    final h = _Harness('a');
    h.type('ab');
    await h.body.flush(force: true);
    expect(h.saved, ['ab']);
    h.type('abc');
    h.body.close();
    await h.body.flush(force: true);
    h.body.remote('远端');
    h.body.edited('x');
    expect(h.saved, ['ab']);
    expect(h.shown, isEmpty);
    h.body.dispose();
  });

  group('富文本：替换异步确认', () {
    test('确认后，之后的输入基于新内容', () {
      fakeAsync((async) {
        final h = _Harness('甲', sync: false);
        h.body.remote('甲\n乙');
        expect(h.shown, ['甲\n乙']);
        h.body.applied();
        h.type('甲\n乙\n丙');
        h.body.remote('前言\n甲\n乙');
        expect(h.shown.last, '前言\n甲\n乙\n丙');
        h.body.applied();
        async.elapse(const Duration(seconds: 1));
        expect(h.saved.last, '前言\n甲\n乙\n丙');
      });
    });

    test('被拒绝：编辑器先送来尚未送达的输入，以替换前的内容为基准合并后再试', () {
      fakeAsync((async) {
        final h = _Harness('第一段\n第二段', sync: false);
        h.body.remote('第一段\n第二段，远端');
        expect(h.shown.single, '第一段\n第二段，远端');
        // 替换到达前用户已经输入（基于旧内容）
        h.type('第一段，本地\n第二段');
        h.body.rejected();
        expect(h.shown.last, '第一段，本地\n第二段，远端');
        h.body.applied();
        async.elapse(const Duration(seconds: 1));
        expect(h.saved.last, '第一段，本地\n第二段，远端');
      });
    });

    test('等待确认期间推迟自动保存，又到达的远端修改在确认后合并', () {
      fakeAsync((async) {
        final h = _Harness('甲', sync: false);
        h.type('甲，本地');
        h.body.remote('甲\n远端一');
        expect(h.shown.single, '甲，本地\n远端一');
        async.elapse(const Duration(seconds: 3));
        expect(h.saved, isEmpty, reason: '等待编辑器确认');
        h.body.remote('甲\n远端一\n远端二');
        expect(h.shown, hasLength(1));
        h.body.applied();
        expect(h.shown.last, '甲，本地\n远端一\n远端二');
        h.body.applied();
        async.elapse(const Duration(seconds: 1));
        expect(h.saved.last, '甲，本地\n远端一\n远端二');
      });
    });

    test('被拒绝后无法合并：保留编辑器中的内容并提示冲突', () {
      fakeAsync((async) {
        final h = _Harness('同一行', sync: false);
        h.body.remote('远端改了这一行');
        h.type('本地改了这一行');
        h.body.rejected();
        expect(h.conflicts, 1);
        expect(h.body.local, '本地改了这一行');
        async.elapse(const Duration(seconds: 1));
        expect(h.saved, ['本地改了这一行']);
      });
    });

    test('被拒绝但没有送来新输入：重新发送替换', () {
      final h = _Harness('甲', sync: false);
      h.body.remote('甲乙');
      h.body.rejected();
      expect(h.shown, ['甲乙', '甲乙']);
      h.body.applied();
      h.body.applied(); // 重复确认无影响
      h.body.rejected(); // 没有等待中的替换时忽略
      expect(h.shown, hasLength(2));
    });

    test('离开页面时即使在等待确认也立即保存', () async {
      final h = _Harness('甲', sync: false);
      h.type('甲，本地');
      h.body.remote('甲\n远端');
      await h.body.flush(force: true);
      expect(h.saved.single, '甲，本地\n远端');
    });
  });
}
