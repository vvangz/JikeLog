import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/theme/app_theme.dart';
import 'rich_editor_controller.dart';

/// 编辑器页面随 App 打包（apps/note-editor 的构建产物，ADR-007）。
const editorAsset = 'assets/editor/index.html';

/// 是否为打包的编辑器页面本身（Android 上从 flutter_assets 加载）。只允许停留在这个页面。
bool isEditorUrl(String url) =>
    url == 'file:///android_asset/flutter_assets/$editorAsset';

/// 承载编辑器的视图，测试中替换为不含 WebView 的实现。
typedef RichEditorViewBuilder = Widget Function(
  BuildContext context,
  RichEditorController controller,
);

final richEditorViewProvider = Provider<RichEditorViewBuilder>(
  (_) =>
      (context, controller) => RichEditorWebView(controller: controller),
);

/// WebView 中的富文本编辑器。只承载页面，消息处理全部在 [RichEditorController] 中。
class RichEditorWebView extends StatefulWidget {
  const RichEditorWebView({super.key, required this.controller});

  final RichEditorController controller;

  @override
  State<RichEditorWebView> createState() => _RichEditorWebViewState();
}

class _RichEditorWebViewState extends State<RichEditorWebView> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'JikeLog',
        onMessageReceived: (m) => widget.controller.handleMessage(m.message),
      )
      // 页面只能停留在打包的编辑器上：拦截一切跳转（链接由工具栏交给系统浏览器打开）
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) => isEditorUrl(req.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    widget.controller.attach(
      run: _web.runJavaScript,
      evaluate: _web.runJavaScriptReturningResult,
    );
    _web.loadFlutterAsset(editorAsset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _web.setBackgroundColor(context.jkColors.background);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
