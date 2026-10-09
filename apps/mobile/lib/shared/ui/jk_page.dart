import 'package:flutter/material.dart';

import '../../app/theme/jk_tokens.g.dart';

/// 内容区页面骨架：宽屏时限制内容宽度并居中，保证表单与列表在平板上也易读。
class JkPage extends StatelessWidget {
  const JkPage({
    super.key,
    required this.children,
    this.title,
    this.maxWidth = 560,
    this.physics,
  });

  /// 有标题时显示返回栏（用于子页面）。
  final String? title;
  final List<Widget> children;
  final double maxWidth;

  /// 外层包裹下拉刷新时传入 AlwaysScrollableScrollPhysics，内容不足一屏也能下拉。
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: physics,
      padding: const EdgeInsets.all(JkTokens.spacingLg),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
    if (title == null) return list;
    return Scaffold(
      appBar: AppBar(title: Text(title!)),
      body: list,
    );
  }
}

/// 设置项分组标题。
class JkSectionTitle extends StatelessWidget {
  const JkSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      JkTokens.spacingXs,
      JkTokens.spacingLg,
      0,
      JkTokens.spacingSm,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// 卡片式分组容器。
class JkCard extends StatelessWidget {
  const JkCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(JkTokens.radiusLg),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

/// 内容不足一屏时撑满高度（Spacer 生效，如把按钮推到底部），超过一屏时可以滚动，
/// 避免横屏、分屏或大字号时内容被截断、按钮无法点到。
class JkFillScroll extends StatelessWidget {
  const JkFillScroll({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - padding.vertical).clamp(
            0,
            double.infinity,
          ),
        ),
        child: IntrinsicHeight(child: child),
      ),
    ),
  );
}
