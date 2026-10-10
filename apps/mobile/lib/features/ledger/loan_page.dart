import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_states.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'ledger_stats.dart';
import 'ledger_widgets.dart';
import 'money.dart';

/// 借贷详情：金额、已收（已还）、待收（待还）、相关流水；记收款或还款、修改、结清、删除。
class LoanPage extends ConsumerWidget {
  const LoanPage({super.key, required this.id});

  final String id;

  Future<void> _run(BuildContext context, Future<void> Function() op) async {
    try {
      await op();
    } on Object catch (e) {
      debugPrint('保存借贷失败: $e');
      if (context.mounted) {
        showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
      }
    }
  }

  Future<void> _editCounterparty(
    BuildContext context,
    WidgetRef ref,
    Loan l,
  ) async {
    // 控制器归对话框所有：对话框关闭动画结束后才释放
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CounterpartyDialog(initial: l.counterparty),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await _run(
      context,
      () =>
          ref.read(ledgerRepositoryProvider).updateLoan(id, counterparty: name),
    );
  }

  Future<void> _pickDue(BuildContext context, WidgetRef ref, Loan l) async {
    final d = await showDatePicker(
      context: context,
      initialDate: l.dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2199, 12, 31),
    );
    if (d == null || !context.mounted) return;
    await _run(
      context,
      () => ref.read(ledgerRepositoryProvider).updateLoan(id, dueDate: d),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showJkConfirm(
      context,
      title: '删除借贷',
      message: '这笔借贷的借出、借入、收款、还款流水会一并删除，账户余额随之更新。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => ref.read(ledgerRepositoryProvider).deleteLoan(id),
    );
    if (context.mounted) {
      context.canPop() ? context.pop() : context.go('/ledger');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider);
    final entries = ref.watch(entriesProvider).value ?? const <Entry>[];
    final loan = loans.value?.where((l) => l.id == id).firstOrNull;
    if (loans.isLoading) {
      return Scaffold(appBar: AppBar(), body: const JkSkeleton(lines: 4));
    }
    if (loan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('借贷')),
        body: const JkEmptyState(
          icon: Icon(Icons.inventory_2_outlined),
          title: '借贷不存在',
          message: '可能已在其他设备上删除',
        ),
      );
    }
    final mine = [
      for (final e in entries)
        if (e.loanId == id) e,
    ];
    final bal =
        loanBalances(mine)[id] ?? const LoanBalance(principal: 0, returned: 0);
    final lend = loan.direction == LoanDirection.lend;
    final back = lend ? EntryType.collect : EntryType.repay;
    final t = Theme.of(context).textTheme;
    final c = context.jkColors;
    final categories = {
      for (final x
          in ref.watch(categoriesProvider).value ?? const <LedgerCategory>[])
        x.id: x,
    };
    final accounts = {
      for (final x in ref.watch(accountsProvider).value ?? const <Account>[])
        x.id: x,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text('${loan.direction.label} · ${loan.counterparty}'),
        actions: [
          IconButton(
            key: const Key('loan-delete'),
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      floatingActionButton: loan.settled
          ? null
          : FloatingActionButton.extended(
              key: const Key('loan-back'),
              onPressed: () =>
                  context.push('/ledger/entry/new?type=${back.name}&loan=$id'),
              icon: const Icon(Icons.add),
              label: Text('记一笔${back.label}'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          JkTokens.spacingLg,
          JkTokens.spacingMd,
          JkTokens.spacingLg,
          96,
        ),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(JkTokens.spacingLg),
              child: Column(
                children: [
                  Text(
                    lend ? '待收' : '待还',
                    style: t.bodyMedium?.copyWith(color: c.textSecondary),
                  ),
                  AmountText(
                    bal.outstanding,
                    colored: false,
                    style: t.headlineSmall,
                  ),
                  const SizedBox(height: JkTokens.spacingSm),
                  Text(
                    '${lend ? '借出' : '借入'} ${formatYuan(bal.principal)} · '
                    '${lend ? '已收' : '已还'} ${formatYuan(bal.returned)}',
                    style: TextStyle(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: JkTokens.spacingMd),
          ListTile(
            key: const Key('loan-edit-counterparty'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(loan.counterparty),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editCounterparty(context, ref, loan),
          ),
          ListTile(
            key: const Key('loan-due'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              loan.dueDate == null
                  ? '没有到期日'
                  : '${loan.dueDate!.year}年${loan.dueDate!.month}月${loan.dueDate!.day}日到期',
            ),
            trailing: loan.dueDate == null
                ? const Icon(Icons.edit_outlined)
                : IconButton(
                    tooltip: '清除到期日',
                    icon: const Icon(Icons.close),
                    onPressed: () => _run(
                      context,
                      () => ref
                          .read(ledgerRepositoryProvider)
                          .updateLoan(id, clearDueDate: true),
                    ),
                  ),
            onTap: () => _pickDue(context, ref, loan),
          ),
          SwitchListTile(
            key: const Key('loan-settled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('已结清'),
            subtitle: bal.outstanding > 0 && !loan.settled
                ? Text(
                    '还有 ${formatYuan(bal.outstanding)} ${lend ? '未收回' : '未归还'}',
                  )
                : null,
            value: loan.settled,
            onChanged: (v) => _run(
              context,
              () =>
                  ref.read(ledgerRepositoryProvider).updateLoan(id, settled: v),
            ),
          ),
          const Divider(),
          Text('相关流水', style: t.titleSmall),
          for (final e in mine)
            EntryTile(
              entry: e,
              categories: categories,
              accounts: accounts,
              loans: {loan.id: loan},
            ),
        ],
      ),
    );
  }
}

class _CounterpartyDialog extends StatefulWidget {
  const _CounterpartyDialog({required this.initial});

  final String initial;

  @override
  State<_CounterpartyDialog> createState() => _CounterpartyDialogState();
}

class _CounterpartyDialogState extends State<_CounterpartyDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改对方'),
    content: TextField(
      key: const Key('loan-counterparty'),
      controller: _ctl,
      autofocus: true,
      maxLength: maxCounterpartyLength,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('loan-counterparty-save'),
        onPressed: () => Navigator.of(context).pop(_ctl.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}
