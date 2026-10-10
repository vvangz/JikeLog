import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';

/// 冲突提示：与其他设备的修改冲突时，提示查看修订历史中落败的版本。
class ConflictBanner extends StatelessWidget {
  const ConflictBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: JkTokens.spacingLg),
      child: Material(
        color: c.warningContainer,
        borderRadius: BorderRadius.circular(JkTokens.radiusMd),
        child: ListTile(
          leading: Icon(Icons.call_split, color: c.onWarningContainer),
          title: Text(
            '与其他设备的修改冲突，已保留最后修改的版本',
            style: TextStyle(color: c.onWarningContainer),
          ),
          subtitle: Text(
            '点击查看另一版本，可以随时恢复',
            style: TextStyle(color: c.onWarningContainer),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
