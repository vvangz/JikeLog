import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/shell/app_shell.dart';
import 'package:jikelog/app/shell/destinations.dart';
import 'package:jikelog/app/shell/sidebar.dart';

import '../support/app_harness.dart';

void main() {
  test('布局断点', () {
    expect(layoutFor(390), ShellLayout.compact);
    expect(layoutFor(600), ShellLayout.medium);
    expect(layoutFor(839), ShellLayout.medium);
    expect(layoutFor(840), ShellLayout.expanded);
    expect(destinationFor('/account/devices')?.path, '/account');
    expect(destinationFor('/nope'), isNull);
  });

  testWidgets('手机宽度：点击左上角入口自上而下展开侧栏，选择模块后收起', (tester) async {
    await pumpApp(tester, width: 400);
    expect(find.text('工作日志'), findsWidgets); // AppBar 标题 + 空状态
    expect(find.byType(Sidebar), findsNothing);

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pump(); // 动画在下一帧开始
    await tester.pump(const Duration(milliseconds: 100));
    // 动画进行中：侧栏只展开了一部分高度
    final align = tester.widget<Align>(
      find
          .ancestor(of: find.byType(Sidebar), matching: find.byType(Align))
          .first,
    );
    expect(align.heightFactor, inExclusiveRange(0, 1));
    // 实际渲染高度随动画增长（而不只是属性变化）
    final visible = tester
        .getSize(find.byKey(const Key('sidebar-overlay')))
        .height;
    expect(visible, inExclusiveRange(1, 800));
    await tester.pumpAndSettle();

    for (final d in allDestinations) {
      expect(find.byKey(Key('nav-${d.path}')), findsOneWidget);
    }
    // 四个模块在上方，设置与帐号在下方
    final notesY = tester.getCenter(find.byKey(const Key('nav-/notes'))).dy;
    final settingsY = tester
        .getCenter(find.byKey(const Key('nav-/settings')))
        .dy;
    expect(notesY, lessThan(settingsY));

    await tapAndSettle(tester, find.byKey(const Key('nav-/notes')));
    expect(find.byType(Sidebar), findsNothing);
    expect(find.text('笔记'), findsWidgets);
  });

  testWidgets('点击遮罩或返回键收起侧栏', (tester) async {
    await pumpApp(tester, width: 400);
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tester.tapAt(const Offset(390, 450));
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsNothing);

    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsNothing);
  });

  testWidgets('系统开启"减少动态效果"时侧栏直接展开', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, width: 400);
    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('nav-/ledger')), findsOneWidget);
  });

  testWidgets('平板宽度：常驻图标导航栏，入口图标展开完整侧栏', (tester) async {
    await pumpApp(tester, width: 700);
    final rail = tester.widget<Sidebar>(find.byType(Sidebar).first);
    expect(rail.expanded, isFalse);
    expect(find.byType(AppBar), findsNothing);

    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')).first);
    expect(find.byType(Sidebar), findsNWidgets(2));
    expect(find.text('记账'), findsWidgets);
    await tapAndSettle(tester, find.byKey(const Key('nav-/ledger')).last);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byKey(const Key('ledger-tab')), findsOneWidget);
  });

  testWidgets('宽屏：常驻完整侧栏，入口图标收起为图标栏', (tester) async {
    await pumpApp(tester, width: 1000);
    expect(tester.widget<Sidebar>(find.byType(Sidebar)).expanded, isTrue);
    expect(find.textContaining('张三 · 已登录'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    expect(tester.widget<Sidebar>(find.byType(Sidebar)).expanded, isFalse);

    await tapAndSettle(tester, find.byKey(const Key('nav-/ledger')));
    expect(find.byKey(const Key('ledger-tab')), findsOneWidget);
  });

  testWidgets('读屏可通过语义动作激活侧栏入口', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, width: 1000);
    final node = tester.getSemantics(find.byKey(const Key('nav-/ledger')));
    expect(node.label, '记账');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await settleApp(tester);
    expect(find.byKey(const Key('ledger-tab')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('横屏小高度 + 2 倍字号：侧栏与隐私页可滚动，不溢出', (tester) async {
    await pumpApp(tester, width: 740, height: 360, textScale: 2);
    expect(tester.takeException(), isNull);
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')).first);
    final account = find.byKey(const Key('nav-/account')).last;
    await tester.scrollUntilVisible(
      account,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tapAndSettle(tester, account);
    expect(find.text('@zhangsan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏 + 2 倍字号：隐私同意按钮可以滚动到并点击', (tester) async {
    await pumpApp(
      tester,
      width: 740,
      height: 360,
      textScale: 2,
      consented: false,
      signedIn: false,
    );
    expect(tester.takeException(), isNull);
    final accept = find.byKey(const Key('consent-accept'));
    await tester.scrollUntilVisible(
      accept,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tapAndSettle(tester, accept);
    expect(find.text('登录即刻日志'), findsOneWidget);
  });

  testWidgets('浮层打开时屏蔽下层语义，遮罩可被读屏关闭', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, width: 400);
    await tapAndSettle(tester, find.byKey(const Key('sidebar-toggle')));
    expect(find.bySemanticsLabel('关闭导航'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('关闭导航'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await settleApp(tester);
    expect(find.byType(Sidebar), findsNothing);
    handle.dispose();
  });
}
