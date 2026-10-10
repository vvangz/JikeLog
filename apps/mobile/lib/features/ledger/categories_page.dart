import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_feedback.dart';
import 'ledger_models.dart';
import 'ledger_presets.dart';
import 'ledger_repository.dart';
import 'ledger_widgets.dart';

/// 收支分类管理：新增、改名、换图标、隐藏与删除（ADR-009 第 5 节）。
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  CategoryKind _kind = CategoryKind.expense;

  bool _isPreset(String id) {
    final user = ref.read(ledgerUserIdProvider);
    return user != null &&
        presetCategories.any((p) => presetCategoryId(user, p.key) == id);
  }

  Future<void> _edit({LedgerCategory? category, String? parentId}) async {
    final result = await showDialog<_CategoryResult>(
      context: context,
      builder: (_) => _CategoryDialog(
        category: category,
        preset: category != null && _isPreset(category.id),
        child: parentId != null || category?.parentId != null,
      ),
    );
    if (result == null || !mounted) return;
    final repo = ref.read(ledgerRepositoryProvider);
    try {
      switch (result.action) {
        case _CategoryAction.save when category == null:
          await repo.createCategory(
            name: result.name,
            kind: _kind,
            parentId: parentId,
            icon: result.icon,
          );
        case _CategoryAction.save:
          await repo.updateCategory(
            category!.id,
            name: result.name,
            icon: result.icon,
          );
        case _CategoryAction.toggleHidden:
          await repo.updateCategory(category!.id, archived: !category.archived);
        case _CategoryAction.delete:
          final ok = await showJkConfirm(
            context,
            title: '删除分类',
            message: '它的二级分类一并删除；已有流水的分类只会隐藏。',
            confirmLabel: '删除',
            destructive: true,
          );
          if (!ok || !mounted) return;
          final deleted = await repo.deleteCategory(
            category!.id,
            preset: _isPreset(category.id),
          );
          if (!deleted && mounted) {
            showJkToast(context, '预置分类或已有流水的分类不能删除，已改为隐藏');
          }
      }
    } on Object catch (e) {
      debugPrint('保存分类失败: $e');
      if (mounted) showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(categoriesProvider).value ?? const <LedgerCategory>[];
    final tops = [
      for (final c in all)
        if (c.kind == _kind && c.parentId == null) c,
    ];
    final c = context.jkColors;
    return Scaffold(
      appBar: AppBar(title: const Text('收支分类')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('category-add'),
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('新增分类'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          JkTokens.spacingLg,
          JkTokens.spacingSm,
          JkTokens.spacingLg,
          96,
        ),
        children: [
          Center(
            child: SegmentedButton<CategoryKind>(
              key: const Key('category-kind'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: CategoryKind.expense, label: Text('支出')),
                ButtonSegment(value: CategoryKind.income, label: Text('收入')),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
          ),
          const SizedBox(height: JkTokens.spacingSm),
          Text(
            '点按修改；已有流水的分类与预置分类只能隐藏，不能删除。',
            style: TextStyle(color: c.textSecondary),
          ),
          for (final top in tops) ...[
            _CategoryRow(
              category: top,
              onTap: () => _edit(category: top),
            ),
            for (final child in all.where((x) => x.parentId == top.id))
              Padding(
                padding: const EdgeInsets.only(left: JkTokens.spacingXl),
                child: _CategoryRow(
                  category: child,
                  onTap: () => _edit(category: child),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: JkTokens.spacingXl),
              child: TextButton.icon(
                key: Key('category-add-child-${top.id}'),
                onPressed: () => _edit(parentId: top.id),
                icon: const Icon(Icons.add, size: 18),
                label: Text('在"${top.name}"下新增'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onTap});

  final LedgerCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: Key('category-row-${category.id}'),
    contentPadding: EdgeInsets.zero,
    leading: LedgerAvatar(icon: categoryIcon(category.icon)),
    title: Text(
      category.name,
      style: category.archived
          ? TextStyle(color: context.jkColors.textDisabled)
          : null,
    ),
    subtitle: category.archived ? const Text('已隐藏') : null,
    trailing: const Icon(Icons.edit_outlined),
    onTap: onTap,
  );
}

enum _CategoryAction { save, toggleHidden, delete }

class _CategoryResult {
  const _CategoryResult(this.action, {this.name = '', this.icon = ''});

  final _CategoryAction action;
  final String name;
  final String icon;
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    this.category,
    required this.preset,
    required this.child,
  });

  final LedgerCategory? category;
  final bool preset;
  final bool child;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _icon = widget.category?.icon ?? 'more_horiz';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    return AlertDialog(
      title: Text(cat == null ? (widget.child ? '新增二级分类' : '新增分类') : '修改分类'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('category-name'),
              controller: _name,
              autofocus: cat == null,
              maxLength: maxCategoryNameLength,
              decoration: InputDecoration(labelText: '名称', errorText: _error),
            ),
            const SizedBox(height: JkTokens.spacingSm),
            Text('图标', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: JkTokens.spacingXs),
            Wrap(
              spacing: JkTokens.spacingXs,
              runSpacing: JkTokens.spacingXs,
              children: [
                for (final name in categoryIcons.keys)
                  Semantics(
                    button: true,
                    selected: name == _icon,
                    label: '图标 $name',
                    child: InkWell(
                      key: Key('icon-$name'),
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _icon = name),
                      // 点按区域不小于 48dp
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: LedgerAvatar(
                            icon: categoryIcon(name),
                            highlight: name == _icon,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (cat != null) ...[
          if (!widget.preset)
            TextButton(
              key: const Key('category-delete'),
              onPressed: () =>
                  Navigator.of(context)
                      .pop(const _CategoryResult(_CategoryAction.delete)),
              child: const Text('删除'),
            ),
          TextButton(
            key: const Key('category-hide'),
            onPressed: () =>
                Navigator.of(context)
                    .pop(const _CategoryResult(_CategoryAction.toggleHidden)),
            child: Text(cat.archived ? '取消隐藏' : '隐藏'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('category-save'),
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = '请填写名称');
              return;
            }
            Navigator.of(context).pop(
              _CategoryResult(_CategoryAction.save, name: name, icon: _icon),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
