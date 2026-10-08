import 'package:flutter/material.dart';

import '../../app/shell/destinations.dart';
import '../../shared/ui/jk_icon.dart';
import '../../shared/ui/jk_states.dart';

/// 模块主界面。各模块在后续版本逐步实现，此前显示说明性的空状态。
class ModulePage extends StatelessWidget {
  const ModulePage({super.key, required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) => JkEmptyState(
    icon: JkIcon(destination.icon, size: 32),
    title: destination.label,
    message: destination.description,
  );
}
