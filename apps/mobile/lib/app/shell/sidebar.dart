import 'package:flutter/material.dart';

import '../../shared/ui/jk_icon.dart';
import '../../shared/ui/jk_logo.dart';
import '../../shared/ui/jk_page.dart';
import '../theme/app_theme.dart';
import '../theme/jk_tokens.g.dart';
import 'destinations.dart';
import 'sync_status.dart';

/// 侧栏宽度。
const sidebarExpandedWidth = 264.0;
const sidebarRailWidth = 72.0;

/// 左上角入口图标：点击展开/收起侧栏。
class SidebarToggle extends StatelessWidget {
  const SidebarToggle({super.key, required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('sidebar-toggle'),
    tooltip: open ? '收起导航' : '展开导航',
    onPressed: onPressed,
    icon: const JkLogo(size: 28),
  );
}

/// 侧栏：上方四个模块入口，下方设置与帐号。[expanded] 为 false 时只显示图标（导航栏样式）。
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.selectedPath,
    required this.onSelect,
    required this.expanded,
    required this.onToggle,
    this.userName,
  });

  final String? selectedPath;
  final ValueChanged<Destination> onSelect;
  final bool expanded;
  final VoidCallback onToggle;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Material(
      color: c.surface,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: expanded ? sidebarExpandedWidth : sidebarRailWidth,
          child: JkFillScroll(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(expanded: expanded, onToggle: onToggle),
                const SizedBox(height: JkTokens.spacingSm),
                for (final d in moduleDestinations) _item(d),
                const Spacer(),
                Divider(height: 1, color: c.divider),
                const SizedBox(height: JkTokens.spacingSm),
                for (final d in generalDestinations) _item(d),
                if (expanded && userName != null) _Footer(userName: userName!),
                const SizedBox(height: JkTokens.spacingSm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(Destination d) => _SidebarItem(
    destination: d,
    selected: selectedPath == d.path,
    expanded: expanded,
    onTap: () => onSelect(d),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Row(
      children: [
        const SizedBox(width: JkTokens.spacingMd),
        SidebarToggle(open: expanded, onPressed: onToggle),
        if (expanded) ...[
          const SizedBox(width: JkTokens.spacingXs),
          Text('即刻日志', style: Theme.of(context).textTheme.titleLarge),
        ],
      ],
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final Destination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final fg = selected ? c.onPrimaryContainer : c.textSecondary;
    final icon = JkIcon(destination.icon, color: fg);
    final content = expanded
        ? Row(
            children: [
              icon,
              const SizedBox(width: JkTokens.spacingMd),
              Text(
                destination.label,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: selected ? fg : c.textPrimary),
              ),
            ],
          )
        : Center(child: icon);
    return Padding(
      // 图标栏模式下减小外边距，保证点击区域不小于 48dp
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? JkTokens.spacingMd : JkTokens.spacingSm,
        vertical: JkTokens.spacingXxs,
      ),
      child: Semantics(
        selected: selected,
        button: true,
        label: destination.label,
        // 合并为单个语义节点，并保留点击动作，读屏（TalkBack）用户才能激活入口
        excludeSemantics: true,
        onTap: onTap,
        child: Tooltip(
          message: expanded ? '' : destination.label,
          child: InkWell(
            key: Key('nav-${destination.path}'),
            borderRadius: BorderRadius.circular(JkTokens.radiusMd),
            onTap: onTap,
            child: AnimatedContainer(
              duration: JkTokens.motionDurationFast,
              height: 48,
              padding: const EdgeInsets.symmetric(
                horizontal: JkTokens.spacingMd,
              ),
              decoration: BoxDecoration(
                color: selected ? c.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(JkTokens.radiusMd),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingXl,
        JkTokens.spacingSm,
        JkTokens.spacingLg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 8, color: c.success),
              const SizedBox(width: JkTokens.spacingSm),
              Expanded(
                child: Text(
                  '$userName · 已登录',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          const SyncStatusLine(),
        ],
      ),
    );
  }
}
