import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/sync_providers.dart';
import '../features/settings/settings_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// 应用根组件：主题与字号来自用户设置，路由由登录态与隐私同意状态驱动。
class JikeLogApp extends ConsumerWidget {
  const JikeLogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    // 按登录状态启停同步
    ref.watch(syncCoordinatorProvider);
    return MaterialApp.router(
      title: '即刻日志',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeModeOf(settings),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        // 应用内字号与系统字号叠加，并限制最大缩放，避免布局溢出
        final mq = MediaQuery.of(context);
        final scale = (mq.textScaler.scale(1) * settings.fontScale).clamp(
          0.8,
          2.0,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
