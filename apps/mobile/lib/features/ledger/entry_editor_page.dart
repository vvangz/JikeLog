import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_states.dart';
import 'accounts_tab.dart' show showAccountEditor;
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'ledger_stats.dart';
import 'category_picker.dart';
import 'money.dart';

/// 新建流水时路由中的 ID。
const newEntryId = 'new';

/// 上次使用的账户（新建流水时默认选中）。
const _lastAccountKey = 'ledger.lastAccount';

/// 流水的大类：支出、收入、转账、借贷（借贷再分四种）。
enum _Group { expense, income, transfer, loan }

_Group _groupOf(EntryType t) => switch (t) {
  EntryType.expense => _Group.expense,
  EntryType.income => _Group.income,
  EntryType.transfer => _Group.transfer,
  _ => _Group.loan,
};

/// 记一笔 / 修改流水。[type] 与 [loanId] 用于从借贷详情直接记收款或还款。
class EntryEditorPage extends ConsumerStatefulWidget {
  const EntryEditorPage({super.key, required this.id, this.type, this.loanId});

  final String id;
  final EntryType? type;
  final String? loanId;

  @override
  ConsumerState<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends ConsumerState<EntryEditorPage> {
  final _amount = TextEditingController();
  final _fee = TextEditingController();
  final _note = TextEditingController();
  final _counterparty = TextEditingController();

  late EntryType _type = widget.type ?? EntryType.expense;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  late String? _loanId = widget.loanId;
  DateTime? _dueDate;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.id == newEntryId;

  /// 修改已有的借出/借入流水时，借贷与对方不能更换。
  bool get _loanFixed =>
      !_isNew && (_type == EntryType.lend || _type == EntryType.borrow);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_isNew) {
      final e = await ref.read(ledgerRepositoryProvider).getEntry(widget.id);
      if (!mounted) return;
      if (e != null) {
        _type = e.type;
        _amount.text = editableYuan(e.amount);
        _fee.text = e.fee > 0 ? editableYuan(e.fee) : '';
        _note.text = e.note;
        _date = e.date;
        _accountId = e.accountId;
        _toAccountId = e.toAccountId;
        _categoryId = e.categoryId;
        _loanId = e.loanId;
      }
    } else {
      _accountId = ref.read(keyValueStoreProvider).getString(_lastAccountKey);
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    _note.dispose();
    _counterparty.dispose();
    super.dispose();
  }

  void _setGroup(_Group g) => setState(() {
    _error = null;
    _type = switch (g) {
      _Group.expense => EntryType.expense,
      _Group.income => EntryType.income,
      _Group.transfer => EntryType.transfer,
      _Group.loan => EntryType.lend,
    };
    _categoryId = null;
  });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2199, 12, 31),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickDue() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _date.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2199, 12, 31),
    );
    if (d != null) setState(() => _dueDate = d);
  }

  Future<void> _save(List<Account> accounts) async {
    final amount = parseYuan(_amount.text);
    final feeText = _fee.text.trim();
    final fee = feeText.isEmpty ? 0 : parseYuan(feeText);
    final account = _accountId;
    String? problem;
    if (amount == null || amount <= 0) {
      problem = '请输入正确的金额，最多两位小数';
    } else if (fee == null) {
      problem = '手续费格式不正确';
    } else if (account == null || !accounts.any((a) => a.id == account)) {
      problem = '请选择账户';
    }
    final newLoan =
        _isNew && (_type == EntryType.lend || _type == EntryType.borrow);
    if (problem == null && newLoan && _counterparty.text.trim().isEmpty) {
      problem = '请填写对方';
    }
    final draft = EntryDraft(
      type: _type,
      amount: amount ?? 0,
      fee: fee ?? 0,
      date: _date,
      accountId: account ?? '',
      toAccountId: _toAccountId,
      categoryId: _categoryId,
      loanId: newLoan ? 'new' : _loanId,
      note: _note.text.trim(),
    );
    problem ??= draft.problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(ledgerRepositoryProvider);
    try {
      if (newLoan) {
        await repo.createLoan(
          direction: _type == EntryType.lend
              ? LoanDirection.lend
              : LoanDirection.borrow,
          counterparty: _counterparty.text,
          amount: amount!,
          accountId: account!,
          date: _date,
          dueDate: _dueDate,
          note: draft.note,
        );
      } else if (_isNew) {
        await repo.createEntry(draft);
      } else {
        await repo.updateEntry(widget.id, draft);
      }
      await ref
          .read(keyValueStoreProvider)
          .setString(_lastAccountKey, account!);
    } on Object catch (e) {
      debugPrint('保存流水失败: $e');
      if (mounted) {
        setState(() => _saving = false);
        showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
      }
      return;
    }
    if (!mounted) return;
    showJkToast(context, '已保存', kind: JkToastKind.success);
    context.canPop() ? context.pop() : context.go('/ledger');
  }

  Future<void> _delete() async {
    final ok = await showJkConfirm(
      context,
      title: '删除流水',
      message: '删除后账户余额与统计随之更新，其他设备上也会删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(ledgerRepositoryProvider).deleteEntry(widget.id);
    } on Object catch (e) {
      debugPrint('删除流水失败: $e');
      if (mounted) showJkToast(context, '删除失败，请重试', kind: JkToastKind.error);
      return;
    }
    if (mounted) context.canPop() ? context.pop() : context.go('/ledger');
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final active = accounts
        .where((a) => !a.archived || a.id == _accountId || a.id == _toAccountId)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '记一笔' : '修改流水'),
        actions: [
          if (!_isNew)
            IconButton(
              key: const Key('entry-delete'),
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(JkTokens.spacingLg),
              child: JkSkeleton(lines: 6),
            )
          : accounts.isEmpty
          ? JkEmptyState(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              title: '还没有账户',
              message: '先添加一个账户（如现金、银行卡、支付宝），再开始记账。',
              actionLabel: '添加账户',
              onAction: () => showAccountEditor(context, ref),
            )
          : _form(active),
      bottomNavigationBar: _loading || accounts.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(JkTokens.spacingMd),
                child: FilledButton(
                  key: const Key('entry-save'),
                  onPressed: _saving ? null : () => _save(accounts),
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ),
    );
  }

  Widget _form(List<Account> accounts) {
    final c = context.jkColors;
    final group = _groupOf(_type);
    return ListView(
      padding: const EdgeInsets.all(JkTokens.spacingLg),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_loanFixed && widget.type == null)
                  SegmentedButton<_Group>(
                    key: const Key('entry-group'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: _Group.expense, label: Text('支出')),
                      ButtonSegment(value: _Group.income, label: Text('收入')),
                      ButtonSegment(value: _Group.transfer, label: Text('转账')),
                      ButtonSegment(value: _Group.loan, label: Text('借贷')),
                    ],
                    selected: {group},
                    onSelectionChanged: (v) => _setGroup(v.first),
                  ),
                if (group == _Group.loan &&
                    !_loanFixed &&
                    widget.type == null) ...[
                  const SizedBox(height: JkTokens.spacingSm),
                  Wrap(
                    spacing: JkTokens.spacingSm,
                    children: [
                      for (final t in const [
                        EntryType.lend,
                        EntryType.borrow,
                        EntryType.collect,
                        EntryType.repay,
                      ])
                        ChoiceChip(
                          key: Key('entry-type-${t.name}'),
                          label: Text(t.label),
                          selected: _type == t,
                          onSelected: (_) => setState(() {
                            _type = t;
                            _loanId = null;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: JkTokens.spacingMd),
                TextField(
                  key: const Key('entry-amount'),
                  controller: _amount,
                  autofocus: _isNew,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: const InputDecoration(
                    labelText: '金额（元）',
                    prefixText: '¥ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: JkTokens.spacingMd),
                ..._typeFields(accounts),
                const SizedBox(height: JkTokens.spacingMd),
                ListTile(
                  key: const Key('entry-date'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text('${_date.year}年${_date.month}月${_date.day}日'),
                  onTap: _pickDate,
                ),
                TextField(
                  key: const Key('entry-note'),
                  controller: _note,
                  maxLength: maxLedgerNoteLength,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: JkTokens.spacingSm),
                    child: Text(
                      _error!,
                      key: const Key('entry-error'),
                      style: TextStyle(color: c.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _typeFields(List<Account> accounts) {
    final accountField = _AccountField(
      key: const Key('entry-account'),
      label: _type == EntryType.transfer ? '转出账户' : '账户',
      accounts: accounts,
      value: _accountId,
      onChanged: (v) => setState(() => _accountId = v),
    );
    switch (_type) {
      case EntryType.expense || EntryType.income:
        return [
          accountField,
          const SizedBox(height: JkTokens.spacingMd),
          CategoryPicker(
            kind: _type == EntryType.income
                ? CategoryKind.income
                : CategoryKind.expense,
            value: _categoryId,
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ];
      case EntryType.transfer:
        return [
          accountField,
          const SizedBox(height: JkTokens.spacingMd),
          _AccountField(
            key: const Key('entry-to-account'),
            label: '转入账户',
            accounts: accounts,
            value: _toAccountId,
            onChanged: (v) => setState(() => _toAccountId = v),
          ),
          TextField(
            key: const Key('entry-fee'),
            controller: _fee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: '手续费（元，可不填）',
              helperText: '从转出账户扣除，计入支出',
            ),
          ),
        ];
      case EntryType.lend || EntryType.borrow when !_loanFixed:
        return [
          accountField,
          TextField(
            key: const Key('entry-counterparty'),
            controller: _counterparty,
            maxLength: maxCounterpartyLength,
            decoration: InputDecoration(
              labelText: _type == EntryType.lend ? '借给谁' : '向谁借',
            ),
          ),
          ListTile(
            key: const Key('entry-due'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              _dueDate == null
                  ? '到期日（可不填）'
                  : '${_dueDate!.year}年${_dueDate!.month}月${_dueDate!.day}日到期',
            ),
            trailing: _dueDate == null
                ? null
                : IconButton(
                    tooltip: '清除到期日',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
            onTap: _pickDue,
          ),
        ];
      default:
        return [accountField, _loanField()];
    }
  }

  Widget _loanField() {
    final loans = ref.watch(loansProvider).value ?? const <Loan>[];
    final entries = ref.watch(entriesProvider).value ?? const <Entry>[];
    final byLoan = loanBalances(entries);
    final direction = switch (_type) {
      EntryType.collect || EntryType.lend => LoanDirection.lend,
      _ => LoanDirection.borrow,
    };
    final options = [
      for (final l in loans)
        if (l.direction == direction && (!l.settled || l.id == _loanId)) l,
    ];
    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: JkTokens.spacingMd),
        child: Text(
          direction == LoanDirection.lend
              ? '没有待收的借出，请先记一笔"借出"'
              : '没有待还的借入，请先记一笔"借入"',
          style: TextStyle(color: context.jkColors.textSecondary),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: const Key('entry-loan'),
      initialValue: options.any((l) => l.id == _loanId) ? _loanId : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: direction == LoanDirection.lend ? '收回哪笔借出' : '归还哪笔借入',
      ),
      items: [
        for (final l in options)
          DropdownMenuItem(
            value: l.id,
            child: Text(
              '${l.counterparty} · ${direction == LoanDirection.lend ? '待收' : '待还'} '
              '${formatYuan(byLoan[l.id]?.outstanding ?? 0)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _loanFixed ? null : (v) => setState(() => _loanId = v),
    );
  }
}

/// 账户选择。
class _AccountField extends StatelessWidget {
  const _AccountField({
    super.key,
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: accounts.any((a) => a.id == value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final a in accounts)
        DropdownMenuItem(
          value: a.id,
          child: Text(
            '${a.name}（${a.type.label}）',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: onChanged,
  );
}
