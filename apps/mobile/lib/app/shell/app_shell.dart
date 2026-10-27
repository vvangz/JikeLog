import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/memos/memos_page.dart';
import '../../features/notes/notes_list_page.dart';
import '../../features/search/search_repository.dart';
import '../../features/worklog/worklog_list_page.dart';
import '../theme/app_theme.dart';
import '../theme/jk_tokens.g.dart';
import 'destinations.dart';
import 'sidebar.dart';

/// 布局档位，断点来自设计令牌。
enum ShellLayout {
  /// < 600：侧栏隐藏，点击左上角入口图标后自上而下展开为浮层。
  compact,

  /// 600–840：常驻图标导航栏；点击入口图标展开完整侧栏浮层。
  medium,

  /// ≥ 840：常驻完整侧栏；点击入口图标收起为图标导航栏。
  expanded,
}

ShellLayout layoutFor(double width) {
  if (width < JkTokens.breakpointMedium) return ShellLayout.compact;
  if (width < JkTokens.breakpointExpanded) return ShellLayout.medium;
  return ShellLayout.expanded;
}

/// 应用外壳：左上角入口图标 + 左侧导航栏 + 内容区。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.navigator,
  });

  final String location;
  final Widget child;

  /// 外壳内的导航器（底部面板等弹在这里）。
  final GlobalKey<NavigatorState>? navigator;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: JkTokens.motionDurationSlow,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// 宽屏下用户是否把侧栏收起为图标栏。
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // 动画状态变化时重建，使返回键拦截（PopScope.canPop）与入口图标状态始终正确
    _reveal.addStatusListener((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _creating?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  bool get _overlayOpen =>
      _reveal.status == AnimationStatus.forward ||
      _reveal.status == AnimationStatus.completed;

  void _toggleOverlay() {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (_overlayOpen) {
      reduce ? _reveal.value = 0 : _reveal.reverse();
    } else {
      reduce ? _reveal.value = 1 : _reveal.forward();
    }
  }

  void _closeOverlay() {
    if (_reveal.value > 0) {
      MediaQuery.of(context).disableAnimations
          ? _reveal.value = 0
          : _reveal.reverse();
    }
  }

  void _select(Destination d) {
    _closeOverlay();
    if (destinationFor(widget.location) != d || widget.location != d.path) {
      context.go(d.path);
    }
  }

  /// 打开全局搜索：在某个模块中打开时默认只搜该模块。
  void _search() {
    _closeOverlay();
    final module = SearchModule.parse(destinationFor(widget.location)?.path);
    context.push(module == null ? '/search' : '/search?module=${module.name}');
  }

  /// 键盘快捷键（桌面端与外接键盘）：Ctrl+F 搜索，Ctrl+N 在当前模块中新建。
  /// 子页面或对话框在上层时不处理。
  bool _onKey(KeyEvent e) {
    final keys = HardwareKeyboard.instance;
    // Windows 上 AltGr 会同时报告 Ctrl+Alt：排除，避免吞掉 AltGr 组合输入的字符
    if (e is! KeyDownEvent ||
        !keys.isControlPressed ||
        keys.isAltPressed ||
        keys.isMetaPressed) {
      return false;
    }
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    // 模块页上打开了底部面板等（弹在外壳内的导航器上）
    if (widget.navigator?.currentState?.canPop() ?? false) return false;
    if (e.logicalKey == LogicalKeyboardKey.keyF) {
      _search();
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyN) return _createInModule();
    return false;
  }

  /// 刚按过 Ctrl+N：新建是异步的，页面打开前再按不重复新建（1 秒后恢复）。
  Timer? _creating;

  bool _createInModule() {
    final module = destinationFor(widget.location)?.path;
    // 只在模块首页处理（如笔记的文件夹面板等仍在模块页内）
    if (module == null || widget.location != module) return false;
    if (_creating?.isActive ?? false) return true;
    _closeOverlay();
    switch (module) {
      case '/worklog':
        unawaited(createWorklog(context, ref));
      case '/notes':
        unawaited(createNote(context, ref));
      case '/memos':
        createMemo(context, ref);
      case '/ledger':
        unawaited(context.push('/ledger/entry/new'));
      default:
        return false;
    }
    _creating = Timer(const Duration(seconds: 1), () {});
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final layout = layoutFor(MediaQuery.sizeOf(context).width);
    if (layout == ShellLayout.expanded && _reveal.value > 0) {
      // 旋转到宽屏时浮层不再显示，同步收起，避免返回键被拦截
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal.value = 0;
      });
    }
    final auth = ref.watch(authControllerProvider);
    final userName = auth is SignedIn ? auth.user.displayName : null;
    final selected = destinationFor(widget.location)?.path;

    Widget sidebar({required bool expanded, required VoidCallback onToggle}) =>
        Sidebar(
          selectedPath: selected,
          onSelect: _select,
          expanded: expanded,
          onToggle: onToggle,
          onSearch: _search,
          userName: userName,
        );

    final Widget body = switch (layout) {
      ShellLayout.compact => widget.child,
      ShellLayout.medium => Row(
        children: [
          sidebar(expanded: false, onToggle: _toggleOverlay),
          VerticalDivider(width: 1, color: context.jkColors.divider),
          Expanded(child: SafeArea(left: false, child: widget.child)),
        ],
      ),
      ShellLayout.expanded => Row(
        children: [
          sidebar(
            expanded: !_collapsed,
            onToggle: () => setState(() => _collapsed = !_collapsed),
          ),
          VerticalDivider(width: 1, color: context.jkColors.divider),
          Expanded(child: SafeArea(left: false, child: widget.child)),
        ],
      ),
    };

    // 返回键：先收起侧栏浮层；在模块、设置、帐号页回到概览；只有在概览页才退出应用
    final atHome = widget.location == overviewDestination.path;
    return PopScope(
      canPop: !_overlayOpen && atHome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_overlayOpen) {
          _closeOverlay();
        } else if (!atHome) {
          context.go(overviewDestination.path);
        }
      },
      child: Scaffold(
        appBar: layout == ShellLayout.compact
            ? AppBar(
                leading: SidebarToggle(
                  open: _overlayOpen,
                  onPressed: _toggleOverlay,
                ),
                title: Text(destinationFor(widget.location)?.label ?? '即刻日志'),
                actions: [
                  IconButton(
                    key: const Key('shell-search'),
                    tooltip: '搜索',
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ],
              )
            : null,
        // StackFit.expand：浮层收起时是 0 尺寸的子组件，若按非定位子组件定尺寸，Stack 会缩成 0×0，内容区将无法点击
        body: Stack(
          fit: StackFit.expand,
          children: [
            body,
            if (layout != ShellLayout.expanded)
              _SidebarOverlay(
                animation: _curve,
                onDismiss: _closeOverlay,
                child: sidebar(expanded: true, onToggle: _toggleOverlay),
              ),
          ],
        ),
      ),
    );
  }
}

/// 侧栏浮层：自上而下展开（可见高度从 0 增长到全高），背后为半透明遮罩，点击遮罩关闭。
/// 浮层打开时屏蔽其下内容的语义，读屏只能访问侧栏与"关闭导航"。
class _SidebarOverlay extends StatelessWidget {
  const _SidebarOverlay({
    required this.animation,
    required this.onDismiss,
    required this.child,
  });

  final Animation<double> animation;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          if (t == 0) return const SizedBox.shrink();
          return BlockSemantics(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: '关闭导航',
                    button: true,
                    onTap: onDismiss,
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const Key('sidebar-scrim'),
                      onTap: onDismiss,
                      child: ColoredBox(
                        color: c.scrim.withValues(alpha: 0.32 * t),
                      ),
                    ),
                  ),
                ),
                // 只固定顶部：高度不受约束，Align 的 heightFactor 才能真正决定可见高度
                Positioned(
                  key: const Key('sidebar-overlay'),
                  left: 0,
                  top: 0,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: t,
                      child: Material(
                        elevation: 8,
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
