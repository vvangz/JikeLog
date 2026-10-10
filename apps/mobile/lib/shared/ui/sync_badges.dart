import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';

/// 记录的同步状态小标记：待同步、同步失败、有冲突版本。
class SyncBadges extends StatelessWidget {
  const SyncBadges({
    super.key,
    required this.pending,
    required this.hasConflict,
    required this.syncError,
  });

  final bool pending;
  final bool hasConflict;
  final String? syncError;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    Widget badge(IconData icon, Color color, String label) => Padding(
      padding: const EdgeInsets.only(left: JkTokens.spacingXs),
      child: Tooltip(
        message: label,
        child: Icon(icon, size: 16, color: color, semanticLabel: label),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (syncError != null)
          badge(Icons.sync_problem, c.error, '同步失败')
        else if (pending)
          badge(Icons.cloud_upload_outlined, c.textSecondary, '待同步'),
        if (hasConflict) badge(Icons.call_split, c.warning, '有冲突版本'),
      ],
    );
  }
}
