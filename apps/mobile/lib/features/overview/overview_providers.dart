import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../ledger/ledger_models.dart';
import '../ledger/ledger_repository.dart';
import '../ledger/ledger_stats.dart';
import '../memos/memo_models.dart';
import '../memos/memo_repository.dart';
import '../notes/note_repository.dart';
import '../settings/settings_controller.dart';
import '../worklog/worklog_repository.dart';
import 'overview_stats.dart';

// 概况按计算时的当前时间统计：离开概览页后释放，回来时重新计算；
// 页面一直开着时由概览页在回到前台与跨过零点时刷新。

final worklogSummaryProvider = Provider.autoDispose<AsyncValue<WorklogSummary>>(
  (ref) {
    final weekStart = ref.watch(settingsControllerProvider).weekStart;
    return ref
        .watch(worklogListProvider)
        .whenData(
          (logs) => worklogSummary(logs, DateTime.now(), weekStart: weekStart),
        );
  },
);

final memoSummaryProvider = Provider.autoDispose<AsyncValue<MemoSummary>>((
  ref,
) {
  final weekStart = ref.watch(settingsControllerProvider).weekStart;
  return ref
      .watch(memoListProvider)
      .whenData((m) => memoSummary(m, DateTime.now(), weekStart: weekStart));
});

final noteSummaryProvider = Provider.autoDispose<AsyncValue<NoteSummary>>(
  (ref) => ref
      .watch(noteListProvider)
      .whenData((n) => noteSummary(n, DateTime.now())),
);

/// 记账概况。
@immutable
class LedgerSummary {
  const LedgerSummary({
    required this.month,
    required this.netWorth,
    required this.daily,
    required this.hasData,
  });

  /// 本月收支。
  final Totals month;
  final NetWorth netWorth;

  /// 近 30 天每天的支出（分），最早的在前。
  final List<int> daily;

  /// 有账户或流水。
  final bool hasData;
}

LedgerSummary ledgerSummary(
  List<Account> accounts,
  List<Loan> loans,
  List<Entry> entries,
  DateTime now,
) {
  final today = dateOnly(now);
  final last30 = Period(
    DateTime(today.year, today.month, today.day - 29),
    DateTime(today.year, today.month, today.day + 1),
  );
  return LedgerSummary(
    month: periodTotals(entries, Period.month(today.year, today.month)),
    netWorth: netWorth(accounts, loans, entries),
    daily: [
      for (final p in trend(entries, last30, TrendUnit.day)) p.totals.expense,
    ],
    hasData: accounts.isNotEmpty || entries.isNotEmpty,
  );
}

final ledgerSummaryProvider = Provider.autoDispose<AsyncValue<LedgerSummary>>((
  ref,
) {
  final accounts = ref.watch(accountsProvider);
  final loans = ref.watch(loansProvider);
  final entries = ref.watch(entriesProvider);
  for (final a in <AsyncValue<Object>>[accounts, loans, entries]) {
    if (a.hasError) return AsyncError(a.error!, a.stackTrace!);
  }
  if (!accounts.hasValue || !loans.hasValue || !entries.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    ledgerSummary(
      accounts.value!,
      loans.value!,
      entries.value!,
      DateTime.now(),
    ),
  );
});

/// 概览中是否隐藏金额（记在本机）。
final amountsHiddenProvider = NotifierProvider<AmountsHiddenController, bool>(
  AmountsHiddenController.new,
);

class AmountsHiddenController extends Notifier<bool> {
  static const _key = 'overview.hideAmounts';

  @override
  bool build() => ref.read(keyValueStoreProvider).getString(_key) == '1';

  Future<void> toggle() async {
    final hidden = !state;
    state = hidden;
    final store = ref.read(keyValueStoreProvider);
    try {
      await (hidden ? store.setString(_key, '1') : store.remove(_key));
    } on Object catch (e) {
      // 没能记下来：恢复原状，避免界面与下次启动时不一致
      debugPrint('保存金额隐藏设置失败: $e');
      if (ref.mounted) state = !hidden;
    }
  }
}
