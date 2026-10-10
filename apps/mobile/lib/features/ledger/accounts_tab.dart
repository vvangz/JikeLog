import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_feedback.dart';
import 'ledger_models.dart';
import 'ledger_presets.dart';
import 'ledger_repository.dart';
import 'ledger_stats.dart';
import 'ledger_widgets.dart';
import 'money.dart';

/// 账户与借贷：净资产、各账户余额、待收待还。
class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final loans = ref.watch(loansProvider).value ?? const <Loan>[];
    final entries = ref.watch(entriesProvider).value ?? const <Entry>[];
    final balances = accountBalances(accounts, entries);
    final byLoan = loanBalances(entries);
    final worth = netWorth(accounts, loans, entries);
    final active = accounts.where((a) => !a.archived).toList();
    final hidden = accounts.where((a) => a.archived).toList();
    final openLoans = loans.where((l) => !l.settled).toList();
    final closedLoans = loans.where((l) => l.settled).toList();
    final t = Theme.of(context).textTheme;
    return ListView(
      key: const Key('ledger-accounts'),
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        JkTokens.spacingSm,
        JkTokens.spacingLg,
        96,
      ),
      children: [
        _WorthCard(worth: worth),
        const SizedBox(height: JkTokens.spacingLg),
        Row(
          children: [
            Expanded(child: Text('账户', style: t.titleSmall)),
            TextButton.icon(
              key: const Key('account-add'),
              onPressed: () => showAccountEditor(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('添加账户'),
            ),
          ],
        ),
        if (accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(JkTokens.spacingMd),
            child: Text(
              '先添加一个账户（如现金、银行卡、支付宝），再开始记账。',
              style: TextStyle(color: context.jkColors.textSecondary),
            ),
          ),
        for (final a in active)
          _AccountTile(account: a, balance: balances[a.id] ?? 0),
        if (hidden.isNotEmpty)
          ExpansionTile(
            key: const Key('accounts-hidden'),
            tilePadding: EdgeInsets.zero,
            title: Text('已隐藏的账户 ${hidden.length}'),
            children: [
              for (final a in hidden)
                _AccountTile(account: a, balance: balances[a.id] ?? 0),
            ],
          ),
        const SizedBox(height: JkTokens.spacingLg),
        Text('借贷', style: t.titleSmall),
        if (loans.isEmpty)
          Padding(
            padding: const EdgeInsets.all(JkTokens.spacingMd),
            child: Text(
              '记一笔"借出"或"借入"后，在这里查看待收与待还。',
              style: TextStyle(color: context.jkColors.textSecondary),
            ),
          ),
        for (final l in openLoans) _LoanTile(loan: l, balance: byLoan[l.id]),
        if (closedLoans.isNotEmpty)
          ExpansionTile(
            key: const Key('loans-settled'),
            tilePadding: EdgeInsets.zero,
            title: Text('已结清 ${closedLoans.length}'),
            children: [
              for (final l in closedLoans)
                _LoanTile(loan: l, balance: byLoan[l.id]),
            ],
          ),
        const SizedBox(height: JkTokens.spacingLg),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: const Key('categories-manage'),
            leading: const Icon(Icons.category_outlined),
            title: const Text('管理收支分类'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/ledger/categories'),
          ),
        ),
      ],
    );
  }
}

class _WorthCard extends StatelessWidget {
  const _WorthCard({required this.worth});

  final NetWorth worth;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.jkColors;
    Widget cell(String label, int v) => Expanded(
      child: Column(
        children: [
          Text(label, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          AmountText(v, colored: false, style: t.titleSmall),
        ],
      ),
    );
    return Card(
      key: const Key('net-worth'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(JkTokens.spacingLg),
        child: Column(
          children: [
            Text('净资产', style: t.bodyMedium?.copyWith(color: c.textSecondary)),
            AmountText(worth.total, colored: false, style: t.headlineSmall),
            const SizedBox(height: JkTokens.spacingMd),
            Row(
              children: [
                cell('账户合计', worth.accounts),
                cell('待收', worth.receivable),
                cell('待还', worth.payable),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account, required this.balance});

  final Account account;
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: Key('account-${account.id}'),
    contentPadding: EdgeInsets.zero,
    leading: LedgerAvatar(icon: accountIcon(account.type)),
    title: Text(account.name),
    subtitle: Text(account.type.label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: AmountText(
        balance,
        colored: balance < 0,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    ),
    onTap: () => showAccountEditor(context, ref, account: account),
  );
}

class _LoanTile extends StatelessWidget {
  const _LoanTile({required this.loan, required this.balance});

  final Loan loan;
  final LoanBalance? balance;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final out = balance?.outstanding ?? 0;
    final due = loan.dueDate;
    // 到期当天不算逾期：按日期比较
    final overdue =
        due != null &&
        !loan.settled &&
        out > 0 &&
        due.isBefore(DateUtils.dateOnly(DateTime.now()));
    final label = loan.direction == LoanDirection.lend ? '待收' : '待还';
    return ListTile(
      key: Key('loan-${loan.id}'),
      contentPadding: EdgeInsets.zero,
      leading: LedgerAvatar(
        icon: loan.direction == LoanDirection.lend
            ? Icons.call_made
            : Icons.call_received,
      ),
      title: Text('${loan.direction.label} · ${loan.counterparty}'),
      subtitle: Text(
        [
          if (loan.settled) '已结清' else '$label ${formatYuan(out)}',
          if (due != null)
            '${due.month}月${due.day}日到期${overdue ? '（已逾期）' : ''}',
        ].join(' · '),
        style: TextStyle(color: overdue ? c.error : c.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/ledger/loans/${loan.id}'),
    );
  }
}

/// 解析带符号的金额（元）：允许前置"-"，表示欠款。
int? parseSignedYuan(String input) {
  final s = input.trim();
  if (s.startsWith('-')) {
    final v = parseYuan(s.substring(1));
    return v == null ? null : -v;
  }
  return parseYuan(s);
}

/// 新建或修改账户。
Future<void> showAccountEditor(
  BuildContext context,
  WidgetRef ref, {
  Account? account,
}) async {
  final result = await showDialog<_AccountForm>(
    context: context,
    builder: (_) => _AccountDialog(account: account),
  );
  if (result == null || !context.mounted) return;
  final repo = ref.read(ledgerRepositoryProvider);
  try {
    switch (result.action) {
      case _AccountAction.save when account == null:
        final count = ref.read(accountsProvider).value?.length ?? 0;
        await repo.createAccount(
          name: result.name,
          type: result.type,
          initialBalance: result.initialBalance,
          sortOrder: count,
        );
      case _AccountAction.save:
        await repo.updateAccount(
          account!.id,
          name: result.name,
          type: result.type,
          initialBalance: result.initialBalance,
        );
      case _AccountAction.toggleHidden:
        await repo.updateAccount(account!.id, archived: !account.archived);
      case _AccountAction.delete:
        final ok = await showJkConfirm(
          context,
          title: '删除账户',
          message: '已有流水的账户只会隐藏；没有流水的账户将被删除，其他设备上也会删除。',
          confirmLabel: '删除',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        final deleted = await repo.deleteAccount(account!.id);
        if (!deleted && context.mounted) {
          showJkToast(context, '这个账户已有流水，已改为隐藏');
        }
    }
  } on Object catch (e) {
    debugPrint('保存账户失败: $e');
    if (context.mounted) {
      showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
    }
  }
}

enum _AccountAction { save, toggleHidden, delete }

class _AccountForm {
  const _AccountForm(
    this.action, {
    this.name = '',
    this.type = AccountType.cash,
    this.initialBalance = 0,
  });

  final _AccountAction action;
  final String name;
  final AccountType type;
  final int initialBalance;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.account});

  final Account? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _balance = TextEditingController(
    text: widget.account == null
        ? ''
        : (widget.account!.initialBalance < 0 ? '-' : '') +
              editableYuan(widget.account!.initialBalance.abs()),
  );
  late AccountType _type = widget.account?.type ?? AccountType.cash;
  String? _nameError;
  String? _balanceError;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final raw = _balance.text.trim();
    final balance = raw.isEmpty ? 0 : parseSignedYuan(raw);
    setState(() {
      _nameError = name.isEmpty ? '请填写名称' : null;
      _balanceError = balance == null ? '金额格式不正确，最多两位小数' : null;
    });
    if (_nameError != null || balance == null) return;
    Navigator.of(context).pop(
      _AccountForm(
        _AccountAction.save,
        name: name,
        type: _type,
        initialBalance: balance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return AlertDialog(
      title: Text(a == null ? '添加账户' : '修改账户'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('account-name'),
              controller: _name,
              autofocus: a == null,
              maxLength: maxAccountNameLength,
              decoration: InputDecoration(
                labelText: '名称',
                errorText: _nameError,
              ),
            ),
            DropdownButtonFormField<AccountType>(
              key: const Key('account-type'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: '类型'),
              items: [
                for (final t in AccountType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            TextField(
              key: const Key('account-balance'),
              controller: _balance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: '初始余额（元）',
                helperText: '信用卡欠款填负数，如 -1200',
                errorText: _balanceError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (a != null) ...[
          TextButton(
            key: const Key('account-delete'),
            onPressed: () =>
                Navigator.of(context)
                    .pop(const _AccountForm(_AccountAction.delete)),
            child: const Text('删除'),
          ),
          TextButton(
            key: const Key('account-hide'),
            onPressed: () =>
                Navigator.of(context)
                    .pop(const _AccountForm(_AccountAction.toggleHidden)),
            child: Text(a.archived ? '取消隐藏' : '隐藏'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('account-save'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
