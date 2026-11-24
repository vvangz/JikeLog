import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../app/version.dart';
import '../../core/platform/platform_features.dart';
import '../../shared/ui/jk_feedback.dart';
import 'update_models.dart';
import 'update_service.dart';

/// 概览页顶部轻量更新提示条（发现新版本且未忽略时展示）。
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final candidate = state.candidate;
    if (!state.shouldShowBanner || candidate == null) {
      return const SizedBox.shrink();
    }
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: JkTokens.spacingMd),
      child: Material(
        key: const Key('update-banner'),
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: JkTokens.spacingMd,
            vertical: JkTokens.spacingSm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                color: c.onPrimaryContainer,
                size: 20,
              ),
              const SizedBox(width: JkTokens.spacingSm),
              Expanded(
                child: Text(
                  '发现新版本 v${candidate.version}，可直接应用内更新',
                  style: text.bodyMedium?.copyWith(
                    color: c.onPrimaryContainer,
                    fontWeight: JkTokens.fontWeightMedium,
                  ),
                ),
              ),
              TextButton(
                key: const Key('update-banner-dismiss'),
                onPressed: () => unawaited(
                  ref
                      .read(appUpdateControllerProvider.notifier)
                      .dismissBanner(),
                ),
                child: const Text('忽略'),
              ),
              FilledButton.tonal(
                key: const Key('update-banner-action'),
                onPressed: () => showAppUpdateDialog(context),
                child: const Text('更新'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手动触发检查更新：发现新版本时弹出更新对话框，已是最新或失败时给 Toast 提示。
Future<void> triggerManualUpdateCheck(
  BuildContext context,
  WidgetRef ref,
) async {
  final notifier = ref.read(appUpdateControllerProvider.notifier);
  final state = ref.read(appUpdateControllerProvider);
  if (state.phase == UpdatePhase.downloading ||
      state.phase == UpdatePhase.verifying ||
      state.phase == UpdatePhase.permissionRequired) {
    if (context.mounted) await showAppUpdateDialog(context);
    return;
  }
  final found = await notifier.check();
  if (!context.mounted) return;
  final next = ref.read(appUpdateControllerProvider);
  if (found) {
    await showAppUpdateDialog(context);
  } else if (next.phase == UpdatePhase.error) {
    showJkToast(
      context,
      next.errorMessage ?? '检查更新失败，请稍后重试',
      kind: JkToastKind.error,
    );
  } else {
    showJkToast(context, '当前已是最新版本（v$appVersion）');
  }
}

/// 应用内更新对话框：展示版本信息、下载进度、校验状态与覆盖安装指引。
Future<void> showAppUpdateDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _AppUpdateDialog(),
);

class _AppUpdateDialog extends ConsumerWidget {
  const _AppUpdateDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final notifier = ref.read(appUpdateControllerProvider.notifier);
    final isDesktop = ref.watch(platformFeaturesProvider).isDesktop;
    final candidate = state.candidate;
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;

    if (candidate == null) {
      return AlertDialog(
        title: const Text('应用更新'),
        content: const Text('当前已是最新版本（v$appVersion）。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    }

    final busy =
        state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.verifying;

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        key: const Key('update-dialog'),
        title: Text('发现新版本 v${candidate.version}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '当前版本 v$appVersion → 新版本 v${candidate.version}',
                style: text.bodyMedium?.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: JkTokens.spacingXs),
              Text(
                '安装包：${candidate.file.name}（${formatByteSize(candidate.file.size)}）',
                style: text.bodySmall?.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: JkTokens.spacingMd),
              _statusBody(context, state, isDesktop),
            ],
          ),
        ),
        actions: _actions(context, ref, state, notifier, candidate),
      ),
    );
  }

  Widget _statusBody(
    BuildContext context,
    AppUpdateState state,
    bool isDesktop,
  ) {
    final c = context.jkColors;
    final text = Theme.of(context).textTheme;
    return switch (state.phase) {
      UpdatePhase.downloading => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: state.progress),
          const SizedBox(height: JkTokens.spacingSm),
          Text(
            state.progress != null
                ? '正在下载：${formatByteSize(state.received)} / ${formatByteSize(state.total)}'
                      '（${(state.progress! * 100).round()}%）'
                : '正在下载安装包…',
            style: text.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
      UpdatePhase.verifying => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: JkTokens.spacingSm),
          Text(
            '正在校验安装包完整性（SHA-256）…',
            style: text.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
      UpdatePhase.permissionRequired => Text(
        '系统尚未允许即刻日志安装更新。请在刚打开的系统设置中开启「允许来自此来源的应用」，返回后点击「继续安装」。',
        style: text.bodyMedium?.copyWith(color: c.warning),
      ),
      UpdatePhase.launched => Text(
        isDesktop
            ? '已打开 Windows 应用安装程序，请点击「更新」完成覆盖安装，本机数据会完整保留。'
            : '已调起系统安装界面，请确认覆盖安装，本机数据会完整保留。',
        style: text.bodyMedium?.copyWith(color: c.success),
      ),
      UpdatePhase.error => Text(
        state.errorMessage ?? '更新失败，请稍后重试',
        style: text.bodyMedium?.copyWith(color: c.error),
      ),
      _ => Text(
        isDesktop
            ? '下载并完成 SHA-256 校验后，将自动打开 Windows 应用安装程序进行覆盖升级，数据不受影响。'
            : '下载并完成 SHA-256 校验后，将自动调起系统安装器覆盖升级，数据不受影响。',
        style: text.bodyMedium,
      ),
    };
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    AppUpdateState state,
    AppUpdateController notifier,
    UpdateCandidate candidate,
  ) {
    if (state.phase == UpdatePhase.downloading) {
      return [
        TextButton(
          key: const Key('update-cancel-download'),
          onPressed: notifier.cancelDownload,
          child: const Text('取消下载'),
        ),
      ];
    }
    if (state.phase == UpdatePhase.verifying) {
      return const [];
    }
    if (state.phase == UpdatePhase.permissionRequired) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          key: const Key('update-continue-install'),
          onPressed: () => unawaited(notifier.retryInstall()),
          child: const Text('继续安装'),
        ),
      ];
    }
    if (state.phase == UpdatePhase.launched) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () {
          final uri = Uri.tryParse(candidate.changelogUrl);
          if (uri != null) {
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          }
        },
        child: const Text('更新日志'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('稍后再说'),
      ),
      FilledButton(
        key: const Key('update-start'),
        onPressed: () => unawaited(notifier.downloadAndInstall()),
        child: Text(state.phase == UpdatePhase.error ? '重试' : '立即更新'),
      ),
    ];
  }
}
