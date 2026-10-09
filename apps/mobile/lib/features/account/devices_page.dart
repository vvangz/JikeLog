import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_page.dart';
import '../../shared/ui/jk_states.dart';

final devicesProvider = FutureProvider.autoDispose<List<Device>>(
  (ref) => ref.watch(accountApiProvider).devices(),
  retry: (_, _) => null,
);

/// 登录设备列表：当前设备置顶标记，其他设备可下线。
class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('登录设备')),
      body: devices.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: JkSkeleton(lines: 6),
        ),
        error: (e, _) => JkErrorState(
          message: e is ApiException ? e.message : '$e',
          onRetry: () => ref.invalidate(devicesProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(devicesProvider.future),
          child: JkPage(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              JkCard(
                children: [
                  for (final (i, d) in list.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _DeviceTile(device: d),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device});

  final Device device;

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final ok = await showJkConfirm(
      context,
      title: '将设备下线？',
      message: '"${_name(device)}" 将立即退出登录，需要重新登录才能使用。',
      confirmLabel: '下线',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(accountApiProvider).revokeDevice(device.id);
      if (!context.mounted) return;
      ref.invalidate(devicesProvider);
      showJkToast(context, '设备已下线', kind: JkToastKind.success);
    } on ApiException catch (e) {
      if (context.mounted) {
        showJkToast(context, e.message, kind: JkToastKind.error);
      }
    }
  }

  static String _name(Device d) => d.model.isNotEmpty ? d.model : d.platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final local = device.lastActiveAt.toLocal();
    final last =
        '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
    return ListTile(
      leading: Icon(
        device.platform == 'android'
            ? Icons.phone_android
            : Icons.devices_other,
      ),
      title: Row(
        children: [
          Flexible(child: Text(_name(device), overflow: TextOverflow.ellipsis)),
          if (device.current) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.successContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '本机',
                style: TextStyle(fontSize: 12, color: c.onSuccessContainer),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          device.osVersion,
          if (device.appVersion.isNotEmpty) 'v${device.appVersion}',
          '最近活跃 $last',
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      trailing: device.current
          ? null
          : TextButton(
              key: Key('revoke-${device.id}'),
              onPressed: () => _revoke(context, ref),
              style: TextButton.styleFrom(foregroundColor: c.error),
              child: const Text('下线'),
            ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
