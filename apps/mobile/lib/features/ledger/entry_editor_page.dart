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

  /// 修改时流水原来的类型。
  EntryType? _origType;

  /// 读取失败或流水已不存在时的提示。
  String? _loadError;

  bool get _isNew => widget.id == newEntryId;

  /// 修改已有的借贷类流水时，类型与所属借贷不能更换（按原来的类型判断）。
  bool get _loanFixed => !_isNew && (_origType?.isLoan ?? false);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      if (!_isNew) {
        final e = await ref.read(ledgerRepositoryProvider).getEntry(widget.id);
        if (!mounted) return;
        if (e == null) {
          setState(() {
            _loadError = '这条流水不存在，可能已在其他设备上删除';
            _loading = false;
          });
          return;
        }
        _origType = e.type;
        _type = e.type;
        _amount.text = editableYuan(e.amount);
        _fee.text = e.fee > 0 ? editableYuan(e.fee) : '';
        _note.text = e.note;
        _date = e.date;
        _accountId = e.accountId;
        _toAccountId = e.toAccountId;
        _categoryId = e.categoryId;
        _loanId = e.loanId;
      } else {
        _accountId = ref.read(keyValueStoreProvider).getString(_lastAccountKey);
      }
    } on Object catch (e) {
      debugPrint('读取流水失败: $e');
      if (mounted) setState(() => _loadError = '读取流水失败');
    }
    if (mounted) setState(() => _loading = false);
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
    // 换了类型：清掉只属于原类型的字段，避免看不见的值挡住保存或被一起保存
    _categoryId = null;
    _toAccountId = null;
    _loanId = null;
    _fee.clear();
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

  /// 校验输入的问题；没有问题时为 null。
  String? _problemOf(
    EntryDraft draft,
    List<Account> accounts, {
    required int? amount,
    required int? fee,
    required bool newLoan,
  }) {
    final categories = ref.read(categoriesProvider).value ?? const [];
    if (amount == null || amount <= 0) return '请输入正确的金额，最多两位小数';
    if (fee == null) return '手续费格式不正确';
    if (!accounts.any((a) => a.id == draft.accountId)) return '请选择账户';
    if (_type == EntryType.transfer &&
        _toAccountId != null &&
        !accounts.any((a) => a.id == _toAccountId)) {
      return '请选择转入账户';
    }
    if (_type.hasCategory &&
        _categoryId != null &&
        !categories.any((c) => c.id == _categoryId)) {
      return '请选择分类';
    }
    if (newLoan && _counterparty.text.trim().isEmpty) return '请填写对方';
    return draft.problem;
  }

  /// 校验输入，返回草稿；有问题时显示原因并返回 null。
  EntryDraft? _validate(List<Account> accounts) {
    final amount = parseYuan(_amount.text);
    final feeText = _fee.text.trim();
    // 只有转账有手续费：其他类型下隐藏的手续费输入不参与校验
    final fee = _type == EntryType.transfer && feeText.isNotEmpty
        ? parseYuan(feeText)
        : 0;
    final newLoan =
        _isNew && (_type == EntryType.lend || _type == EntryType.borrow);
    final draft = EntryDraft(
      type: _type,
      amount: amount ?? 0,
      fee: fee ?? 0,
      date: _date,
      accountId: _accountId ?? '',
      toAccountId: _toAccountId,
      categoryId: _categoryId,
      loanId: newLoan ? 'new' : _loanId,
      note: _note.text.trim(),
    );
    final problem = _problemOf(
      draft,
      accounts,
      amount: amount,
      fee: fee,
      newLoan: newLoan,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return null;
    }
    return draft;
  }

  Future<void> _persist(EntryDraft draft) async {
    final repo = ref.read(ledgerRepositoryProvider);
    if (_isNew && (_type == EntryType.lend || _type == EntryType.borrow)) {
      await repo.createLoan(
        direction: _type == EntryType.lend
            ? LoanDirection.lend
            : LoanDirection.borrow,
        counterparty: _counterparty.text,
        amount: draft.amount,
        accountId: draft.accountId,
        date: _date,
        dueDate: _dueDate,
        note: draft.note,
      );
    } else if (_isNew) {
      await repo.createEntry(draft);
    } else {
      await repo.updateEntry(widget.id, draft);
    }
  }

  Future<void> _save(List<Account> accounts) async {
    final draft = _validate(accounts);
    if (draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _persist(draft);
    } on ArgumentError catch (e) {
      // 仓储的校验（例如收款超过待收）：在表单中说明原因
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '${e.message}';
        });
      }
      return;
    } on StateError {
      if (mounted) {
        showJkToast(context, '这条流水已在其他设备上删除', kind: JkToastKind.error);
        _close();
      }
      return;
    } on Object catch (e) {
      debugPrint('保存流水失败: $e');
      if (mounted) {
        setState(() => _saving = false);
        showJkToast(context, '保存失败，请重试', kind: JkToastKind.error);
      }
      return;
    }
    // 已保存：记住账户只是方便下次，失败不影响结果（不能让用户以为没保存而重复记）
    try {
      await ref
          .read(keyValueStoreProvider)
          .setString(_lastAccountKey, draft.accountId);
    } on Object catch (e) {
      debugPrint('记住账户失败: $e');
    }
    if (!mounted) return;
    showJkToast(context, '已保存', kind: JkToastKind.success);
    _close();
  }

  void _close() => context.canPop() ? context.pop() : context.go('/ledger');

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
    if (mounted) _close();
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
          : _loadError != null
          ? JkEmptyState(
              icon: const Icon(Icons.inventory_2_outlined),
              title: _loadError!,
              message: '返回流水列表查看最新内容',
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
      bottomNavigationBar: _loading || _loadError != null || accounts.isEmpty
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
                    segments: [
                      const ButtonSegment(
                        value: _Group.expense,
                        label: Text('支出'),
                      ),
                      const ButtonSegment(
                        value: _Group.income,
                        label: Text('收入'),
                      ),
                      const ButtonSegment(
                        value: _Group.transfer,
                        label: Text('转账'),
                      ),
                      // 已有的收支、转账不能改成借贷（借贷要关联一笔借贷）
                      if (_isNew)
                        const ButtonSegment(
                          value: _Group.loan,
                          label: Text('借贷'),
                        ),
                    ],
                    selected: {group},
                    onSelectionChanged: (v) => _setGroup(v.first),
                  ),
                if (group == _Group.loan && _isNew && widget.type == null) ...[
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
    return KeyedSubtree(
      key: const Key('entry-loan'),
      child: _loanDropdown(options, direction, byLoan),
    );
  }

  Widget _loanDropdown(
    List<Loan> options,
    LoanDirection direction,
    Map<String, LoanBalance> byLoan,
  ) {
    return DropdownButtonFormField<String>(
      // 类型、可选的借贷或当前值变化时重建：FormField 只在创建时读取 initialValue
      key: ValueKey(
        '${_type.name}|${options.map((l) => l.id).join(',')}|$_loanId',
      ),
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
    // 账户列表或当前值变化时重建：FormField 只在创建时读取 initialValue
    key: ValueKey('$label|${accounts.map((a) => a.id).join(',')}|$value'),
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
