import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import 'ledger_models.dart';
import 'ledger_presets.dart';
import 'ledger_repository.dart';
import 'ledger_widgets.dart';

/// 分类选择：一级分类网格；选中有二级分类的一级分类后，下方列出它的二级分类（可不选）。
class CategoryPicker extends ConsumerWidget {
  const CategoryPicker({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
  });

  final CategoryKind kind;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(categoriesProvider).value ?? const <LedgerCategory>[];
    final byId = {for (final c in all) c.id: c};
    bool visible(LedgerCategory c) =>
        c.kind == kind && (!c.archived || c.id == value);
    final tops = [
      for (final c in all)
        if (c.parentId == null && visible(c)) c,
    ];
    final selected = byId[value];
    final topId = selected?.parentId ?? selected?.id;
    final children = [
      for (final c in all)
        if (c.parentId == topId && topId != null && visible(c)) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('分类', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton(
              key: const Key('category-manage-link'),
              onPressed: () => context.push('/ledger/categories'),
              child: const Text('管理'),
            ),
          ],
        ),
        if (tops.isEmpty)
          Text(
            '还没有${kind.label}分类',
            style: TextStyle(color: context.jkColors.textSecondary),
          ),
        Wrap(
          spacing: JkTokens.spacingXs,
          runSpacing: JkTokens.spacingXs,
          children: [
            for (final c in tops)
              _CategoryCell(
                category: c,
                selected: c.id == topId,
                onTap: () => onChanged(c.id),
              ),
          ],
        ),
        if (children.isNotEmpty) ...[
          const SizedBox(height: JkTokens.spacingSm),
          Wrap(
            spacing: JkTokens.spacingSm,
            children: [
              for (final c in children)
                ChoiceChip(
                  key: Key('category-${c.id}'),
                  label: Text(c.name),
                  selected: c.id == value,
                  onSelected: (on) => onChanged(on ? c.id : topId),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final LedgerCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: category.name,
    child: InkWell(
      key: Key('category-${category.id}'),
      borderRadius: BorderRadius.circular(JkTokens.radiusMd),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingXs),
          child: Column(
            children: [
              LedgerAvatar(
                icon: categoryIcon(category.icon),
                highlight: selected,
              ),
              const SizedBox(height: JkTokens.spacingXxs),
              ExcludeSemantics(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
