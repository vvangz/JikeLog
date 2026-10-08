import 'package:flutter/material.dart';

import '../shared/ui/jk_logo.dart';
import 'theme/app_theme.dart';
import 'version.dart';

/// 应用根组件。
class JikeLogApp extends StatelessWidget {
  const JikeLogApp({super.key, this.themeMode = ThemeMode.system});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '即刻日志',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const _PlaceholderHome(),
    );
  }
}

/// v0.1.0 占位首页；导航外壳与四个模块从 v0.2.0 起逐步替换。
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const JkLogo(size: 72),
            const SizedBox(height: 16),
            Text('即刻日志', style: text.displaySmall),
            const SizedBox(height: 8),
            Text(
              'v$appVersion · 工作日志 / 笔记 / 备忘录 / 记账',
              style: text.bodyMedium?.copyWith(
                color: context.jkColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
