/// 发送短信验证码前的人机验证（阿里云验证码 2.0，V3 架构 H5 接入）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/server_features.dart';
import '../../core/config.dart';

/// 完成人机验证，返回 captchaVerifyParam；用户取消时返回 null。
typedef CaptchaSolver = Future<String?> Function(
  BuildContext context,
  CaptchaConfig config,
);

/// 组件测试中替换为不加载网页的实现。
final captchaSolverProvider = Provider<CaptchaSolver>((_) => showCaptchaSheet);

/// 阿里云验证码脚本：官方要求从其 CDN 动态加载，不能打包进 App，否则无法随风控策略更新。
const _captchaScript =
    'https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js';

/// 生成验证码页面。参数经 JSON 编码后写入脚本，并把 `<` 转义为 `\x3c`，不会被解释为代码或提前结束 script 标签。
@visibleForTesting
String captchaHtml(CaptchaConfig c) {
  final cfg = _jsLiteral({'region': c.region, 'prefix': c.prefix});
  final scene = _jsLiteral(c.sceneId);
  return '''
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>body{margin:0;padding:16px 0;display:flex;justify-content:center;background:transparent}</style>
<script>window.AliyunCaptchaConfig = $cfg;</script>
</head><body>
<div id="captcha-element"></div>
<button id="captcha-button" style="display:none"></button>
<script>
function post(m) { JikeCaptcha.postMessage(JSON.stringify(m)); }
var s = document.createElement('script');
s.src = '$_captchaScript';
s.onerror = function () { post({type: 'error'}); };
s.onload = function () {
  try {
    initAliyunCaptcha({
      SceneId: $scene,
      mode: 'embed',
      element: '#captcha-element',
      button: '#captcha-button',
      language: 'cn',
      slideStyle: {width: 300, height: 40},
      success: function (p) { post({type: 'success', param: p}); },
      fail: function () {},
      getInstance: function () { post({type: 'ready'}); }
    });
  } catch (e) {
    post({type: 'error'});
  }
};
document.head.appendChild(s);
</script>
</body></html>
''';
}

String _jsLiteral(Object value) => jsonEncode(value).replaceAll('<', r'\x3c');

/// 验证页面发回的事件。
@visibleForTesting
sealed class CaptchaEvent {
  const CaptchaEvent();
}

/// 验证组件已显示。
@visibleForTesting
final class CaptchaReady extends CaptchaEvent {
  const CaptchaReady();
}

/// 验证通过。
@visibleForTesting
final class CaptchaPassed extends CaptchaEvent {
  const CaptchaPassed(this.param);
  final String param;
}

/// 验证组件加载失败。
@visibleForTesting
final class CaptchaLoadFailed extends CaptchaEvent {
  const CaptchaLoadFailed();
}

/// 解析页面发回的消息，无法识别时返回 null。
@visibleForTesting
CaptchaEvent? parseCaptchaMessage(String raw) {
  try {
    return switch (jsonDecode(raw)) {
      {'type': 'success', 'param': final String p} => CaptchaPassed(p),
      {'type': 'ready'} => const CaptchaReady(),
      {'type': 'error'} => const CaptchaLoadFailed(),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// 在底部弹层中显示验证码。
Future<String?> showCaptchaSheet(BuildContext context, CaptchaConfig config) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CaptchaSheet(config: config),
    );

class _CaptchaSheet extends StatefulWidget {
  const _CaptchaSheet({required this.config});

  final CaptchaConfig config;

  @override
  State<_CaptchaSheet> createState() => _CaptchaSheetState();
}

enum _Status { loading, ready, failed }

class _CaptchaSheetState extends State<_CaptchaSheet> {
  late final WebViewController _web;
  _Status _status = _Status.loading;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 页面中的任何框架都能调用这个通道；伪造的"通过"只会得到服务端校验不过的结果
      ..addJavaScriptChannel('JikeCaptcha', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          // 验证码在页面内完成：只允许加载本页（以 API 地址为来源）与验证组件的子框架
          onNavigationRequest: (req) =>
              !req.isMainFrame ||
                  req.url.startsWith(AppConfig.apiBaseUrl) ||
                  req.url.startsWith('about:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          // 验证组件通常在页面加载完成后才出现（getInstance 时发送 ready）；为免组件不回调时一直转圈，
          // 页面加载完成即收起加载提示
          onPageFinished: (_) {
            if (_status == _Status.loading) _setStatus(_Status.ready);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? false) _setStatus(_Status.failed);
          },
        ),
      );
    _load();
  }

  /// 以 API 地址为页面来源：阿里云会校验页面地址，空白来源可能被判为异常。
  /// 页面中没有登录令牌或 Cookie（App 用 Authorization 头访问接口），同源不会带来额外权限。
  void _load() {
    _setStatus(_Status.loading);
    unawaited(
      _web.loadHtmlString(
        captchaHtml(widget.config),
        baseUrl: AppConfig.apiBaseUrl,
      ),
    );
  }

  void _setStatus(_Status s) {
    if (mounted && _status != s) setState(() => _status = s);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_web.setBackgroundColor(context.jkColors.background));
  }

  void _onMessage(JavaScriptMessage m) {
    if (!mounted) return;
    switch (parseCaptchaMessage(m.message)) {
      case CaptchaPassed(:final param):
        Navigator.of(context).pop(param);
      case CaptchaReady():
        _setStatus(_Status.ready);
      case CaptchaLoadFailed():
        _setStatus(_Status.failed);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('安全验证', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('完成验证后发送短信验证码'),
          SizedBox(
            height: 320,
            child: _status == _Status.failed
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('验证组件加载失败，请检查网络'),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      Semantics(
                        label: '安全验证',
                        child: WebViewWidget(controller: _web),
                      ),
                      if (_status == _Status.loading)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

/// 按服务端要求完成人机验证后发送验证码，供 `JkSmsCodeField.onSend` 使用。[send] 收到验证结果
/// （不需要验证时为 null）；用户关闭验证弹层或页面已关闭时不发送，返回 null（不进入倒计时）。
Future<int?> sendWithCaptcha(
  BuildContext context,
  WidgetRef ref,
  Future<int?> Function(String? captchaVerifyParam) send,
) async {
  // 等系统信息查询完成：刚启动时查询尚未返回，不能当作不需要验证（查询失败时按默认值处理）
  final features = await ref.read(serverFeaturesProvider.future);
  final config = features.captcha;
  if (!context.mounted) return null;
  if (config == null) return send(null);
  final param = await ref.read(captchaSolverProvider)(context, config);
  if (param == null || !context.mounted) return null;
  return send(param);
}
