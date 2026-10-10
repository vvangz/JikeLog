import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/jk_tokens.g.dart';
import 'accounts_tab.dart';
import 'entries_tab.dart';
import 'ledger_repository.dart';
import 'stats_tab.dart';

enum LedgerTab { entries, stats, accounts }

/// 当前查看的页签（本次运行内记住）。
final ledgerTabProvider = NotifierProvider<LedgerTabController, LedgerTab>(
  LedgerTabController.new,
);

class LedgerTabController extends Notifier<LedgerTab> {
  @override
  LedgerTab build() => LedgerTab.entries;

  void set(LedgerTab t) => state = t;
}

/// 记账主界面：流水、统计、账户三个页签。
class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  @override
  void initState() {
    super.initState();
    // 首次进入时写入预置分类（已有的跳过）
    final user = ref.read(ledgerUserIdProvider);
    if (user != null) {
      unawaited(
        ref
            .read(ledgerRepositoryProvider)
            .ensurePresets(user)
            .catchError((Object e) => debugPrint('写入预置分类失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(ledgerTabProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('entry-create'),
        onPressed: () => context.push('/ledger/entry/new'),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              JkTokens.spacingLg,
              JkTokens.spacingSm,
              JkTokens.spacingLg,
              0,
            ),
            child: Center(
              child: SegmentedButton<LedgerTab>(
                key: const Key('ledger-tab'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: LedgerTab.entries, label: Text('流水')),
                  ButtonSegment(value: LedgerTab.stats, label: Text('统计')),
                  ButtonSegment(value: LedgerTab.accounts, label: Text('账户')),
                ],
                selected: {tab},
                onSelectionChanged: (v) =>
                    ref.read(ledgerTabProvider.notifier).set(v.first),
              ),
            ),
          ),
          Expanded(
            child: switch (tab) {
              LedgerTab.entries => const EntriesTab(),
              LedgerTab.stats => const StatsTab(),
              LedgerTab.accounts => const AccountsTab(),
            },
          ),
        ],
      ),
    );
  }
}
