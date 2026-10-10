import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../core/sync/record_store.dart';
import '../../core/sync/schema.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import '../worklog/worklog_repository.dart' show formatDate;
import '../auth/auth_controller.dart';
import 'ledger_models.dart';
import 'ledger_presets.dart';
import 'money.dart';

/// 记账字段长度上限（与服务端一致）。
const maxAccountNameLength = 30;
const maxCategoryNameLength = 20;
const maxCounterpartyLength = 50;
const maxLedgerNoteLength = 1000;

/// 流水草稿：新建与修改共用。金额单位为分。
@immutable
class EntryDraft {
  const EntryDraft({
    required this.type,
    required this.amount,
    required this.date,
    required this.accountId,
    this.fee = 0,
    this.toAccountId,
    this.categoryId,
    this.loanId,
    this.note = '',
  });

  final EntryType type;
  final int amount;
  final int fee;
  final DateTime date;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String? loanId;
  final String note;

  /// 校验字段之间的约束（ADR-009），返回错误说明；没有问题时为 null。
  String? get problem {
    if (amount <= 0) return '请输入金额';
    if (amount > maxMoneyCents) return '金额过大';
    if (fee < 0 || fee > maxMoneyCents) return '手续费不正确';
    if (note.length > maxLedgerNoteLength) {
      return '备注不能超过 $maxLedgerNoteLength 字';
    }
    return switch (type) {
      EntryType.expense ||
      EntryType.income => categoryId == null ? '请选择分类' : null,
      EntryType.transfer =>
        toAccountId == null
            ? '请选择转入账户'
            : toAccountId == accountId
            ? '转出与转入不能是同一个账户'
            : null,
      _ => loanId == null ? '请选择借贷' : null,
    };
  }

  Map<String, Object?> toFields() => {
    'type': type.name,
    'amount': encodeCents(amount),
    'fee': type == EntryType.transfer && fee > 0 ? encodeCents(fee) : null,
    'date': formatDate(date),
    'accountId': accountId,
    'toAccountId': type == EntryType.transfer ? toAccountId : null,
    'categoryId': type.hasCategory ? categoryId : null,
    'loanId': type.isLoan ? loanId : null,
    'note': note,
  };
}

/// 记账的读写：写入本地后由同步引擎在后台推送。
class LedgerRepository {
  LedgerRepository({
    required this.db,
    required this.store,
    required this.engine,
  });

  final AppDatabase db;
  final RecordStore store;
  final SyncEngine engine;

  Stream<List<LocalRecord>> _watch(String entity, {bool newestFirst = false}) =>
      (db.select(db.records)
            ..where((t) => t.entity.equals(entity) & t.deleted.not())
            ..orderBy([
              (t) => newestFirst
                  ? OrderingTerm.desc(t.sortKey)
                  : OrderingTerm.asc(t.sortKey),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch()
          .map((rows) => [for (final r in rows) LocalRecord.fromRow(r)]);

  Stream<List<Account>> watchAccounts() => _watch(Entities.ledgerAccount)
      .map(
        (rs) =>
            [for (final r in rs) Account.fromRecord(r)]
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      )
      .distinct(listEquals);

  Stream<List<LedgerCategory>> watchCategories() =>
      _watch(Entities.ledgerCategory)
          .map(
            (rs) =>
                [for (final r in rs) LedgerCategory.fromRecord(r)]
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
          )
          .distinct(listEquals);

  Stream<List<Loan>> watchLoans() =>
      _watch(Entities.ledgerLoan)
          .map((rs) => [for (final r in rs) Loan.fromRecord(r)])
          .distinct(listEquals);

  /// 全部流水，最新的在前。字段不完整的记录被忽略。
  Stream<List<Entry>> watchEntries() =>
      _watch(Entities.ledgerEntry, newestFirst: true)
          .map((rs) => [for (final r in rs) ?Entry.fromRecord(r)])
          .distinct(listEquals);

  Future<Entry?> getEntry(String id) async {
    final r = await store.get(id);
    if (r == null || r.deleted || r.entity != Entities.ledgerEntry) return null;
    return Entry.fromRecord(r);
  }

  /// 写入预置分类（本机已有的跳过）。多台设备写入的是同一批 ID，同步后自然合并。
  Future<void> ensurePresets(String userId) async {
    var wrote = false;
    for (final (i, p) in presetCategories.indexed) {
      wrote |= await store.seed(
        Entities.ledgerCategory,
        presetCategoryId(userId, p.key),
        {
          'name': p.name,
          'kind': p.kind.name,
          'parentId': p.parent == null
              ? null
              : presetCategoryId(userId, p.parent!),
          'icon': p.icon,
          'archived': 0,
          'sortOrder': i,
        },
      );
    }
    if (wrote) engine.schedule();
  }

  // ───────────── 账户 ─────────────

  Future<String> createAccount({
    required String name,
    required AccountType type,
    int initialBalance = 0,
    int sortOrder = 0,
  }) async {
    final id = const Uuid().v7();
    await store.write(Entities.ledgerAccount, id, {
      'name': name.trim(),
      'type': type.name,
      'initialBalance': encodeCents(initialBalance),
      'archived': 0,
      'sortOrder': sortOrder,
    });
    engine.schedule();
    return id;
  }

  Future<void> updateAccount(
    String id, {
    String? name,
    AccountType? type,
    int? initialBalance,
    bool? archived,
  }) async {
    await store.write(Entities.ledgerAccount, id, create: false, {
      'name': ?name?.trim(),
      'type': ?type?.name,
      'initialBalance': ?(initialBalance == null
          ? null
          : encodeCents(initialBalance)),
      'archived': ?(archived == null ? null : (archived ? 1 : 0)),
    });
    engine.schedule();
  }

  /// 删除账户；已有流水引用时改为隐藏（历史流水仍显示它）。返回是否真的删除了。
  Future<bool> deleteAccount(String id) async {
    if (await _entryRefs((e) => e.accountId == id || e.toAccountId == id)) {
      await updateAccount(id, archived: true);
      return false;
    }
    await store.remove(id);
    engine.schedule();
    return true;
  }

  // ───────────── 分类 ─────────────

  Future<String> createCategory({
    required String name,
    required CategoryKind kind,
    String? parentId,
    String icon = 'more_horiz',
    int sortOrder = 1000,
  }) async {
    final id = const Uuid().v7();
    await store.write(Entities.ledgerCategory, id, {
      'name': name.trim(),
      'kind': kind.name,
      'parentId': parentId,
      'icon': icon,
      'archived': 0,
      'sortOrder': sortOrder,
    });
    engine.schedule();
    return id;
  }

  Future<void> updateCategory(
    String id, {
    String? name,
    String? icon,
    bool? archived,
  }) async {
    await store.write(Entities.ledgerCategory, id, create: false, {
      'name': ?name?.trim(),
      'icon': ?icon,
      'archived': ?(archived == null ? null : (archived ? 1 : 0)),
    });
    engine.schedule();
  }

  /// 删除分类；它或它的二级分类已有流水，或者它是预置分类时改为隐藏。返回是否真的删除了。
  Future<bool> deleteCategory(String id, {required bool preset}) async {
    final children =
        await (db.select(db.records)..where(
              (t) => t.entity.equals(Entities.ledgerCategory) & t.deleted.not(),
            ))
            .get();
    final ids = {
      id,
      for (final r in children)
        if (LocalRecord.fromRow(r).fields['parentId'] == id) r.id,
    };
    if (preset || await _entryRefs((e) => ids.contains(e.categoryId))) {
      for (final c in ids) {
        await updateCategory(c, archived: true);
      }
      return false;
    }
    for (final c in ids) {
      await store.remove(c);
    }
    engine.schedule();
    return true;
  }

  // ───────────── 流水与借贷 ─────────────

  Future<String> createEntry(EntryDraft d) async {
    final problem = d.problem;
    if (problem != null) throw ArgumentError(problem);
    final id = const Uuid().v7();
    await store.write(Entities.ledgerEntry, id, d.toFields());
    engine.schedule();
    return id;
  }

  Future<void> updateEntry(String id, EntryDraft d) async {
    final problem = d.problem;
    if (problem != null) throw ArgumentError(problem);
    await store.write(Entities.ledgerEntry, id, d.toFields(), create: false);
    engine.schedule();
  }

  Future<void> deleteEntry(String id) async {
    await store.remove(id);
    engine.schedule();
  }

  /// 新建一笔借贷，并记下借出（借入）的流水。返回借贷 ID。
  Future<String> createLoan({
    required LoanDirection direction,
    required String counterparty,
    required int amount,
    required String accountId,
    required DateTime date,
    DateTime? dueDate,
    String note = '',
  }) async {
    final who = counterparty.trim();
    if (who.isEmpty) throw ArgumentError('请填写对方');
    final draft = EntryDraft(
      type: direction == LoanDirection.lend ? EntryType.lend : EntryType.borrow,
      amount: amount,
      date: date,
      accountId: accountId,
      loanId: 'pending',
      note: note,
    );
    final problem = draft.problem;
    if (problem != null) throw ArgumentError(problem);
    final id = const Uuid().v7();
    await store.write(Entities.ledgerLoan, id, {
      'direction': direction.name,
      'counterparty': who,
      'dueDate': dueDate == null ? null : formatDate(dueDate),
      'note': '',
      'settled': 0,
    });
    await store.write(
      Entities.ledgerEntry,
      const Uuid().v7(),
      EntryDraft(
        type: draft.type,
        amount: amount,
        date: date,
        accountId: accountId,
        loanId: id,
        note: note,
      ).toFields(),
    );
    engine.schedule();
    return id;
  }

  Future<void> updateLoan(
    String id, {
    String? counterparty,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? note,
    bool? settled,
  }) async {
    await store.write(Entities.ledgerLoan, id, create: false, {
      'counterparty': ?counterparty?.trim(),
      if (clearDueDate)
        'dueDate': null
      else
        'dueDate': ?(dueDate == null ? null : formatDate(dueDate)),
      'note': ?note,
      'settled': ?(settled == null ? null : (settled ? 1 : 0)),
    });
    engine.schedule();
  }

  /// 删除借贷及其全部借贷流水。
  Future<void> deleteLoan(String id) async {
    final entries = await _entries();
    for (final e in entries.where((e) => e.loanId == id)) {
      await store.remove(e.id);
    }
    await store.remove(id);
    engine.schedule();
  }

  Future<List<Entry>> _entries() async {
    final rows =
        await (db.select(db.records)..where(
              (t) => t.entity.equals(Entities.ledgerEntry) & t.deleted.not(),
            ))
            .get();
    return [for (final r in rows) ?Entry.fromRecord(LocalRecord.fromRow(r))];
  }

  Future<bool> _entryRefs(bool Function(Entry) test) async =>
      (await _entries()).any(test);
}

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(
    db: ref.watch(appDatabaseProvider),
    store: ref.watch(recordStoreProvider),
    engine: ref.watch(syncEngineProvider),
  ),
);

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(ledgerRepositoryProvider).watchAccounts(),
);

final categoriesProvider = StreamProvider<List<LedgerCategory>>(
  (ref) => ref.watch(ledgerRepositoryProvider).watchCategories(),
);

final loansProvider = StreamProvider<List<Loan>>(
  (ref) => ref.watch(ledgerRepositoryProvider).watchLoans(),
);

final entriesProvider = StreamProvider<List<Entry>>(
  (ref) => ref.watch(ledgerRepositoryProvider).watchEntries(),
);

/// 当前账号 ID（预置分类的 ID 由它生成）；未登录时为 null。
final ledgerUserIdProvider = Provider<String?>(
  (ref) => switch (ref.watch(authControllerProvider)) {
    SignedIn(:final user) => user.id,
    _ => null,
  },
);

/// 转账手续费计入的分类 ID。
final feeCategoryIdProvider = Provider<String?>((ref) {
  final user = ref.watch(ledgerUserIdProvider);
  return user == null ? null : presetCategoryId(user, feeCategoryKey);
});
