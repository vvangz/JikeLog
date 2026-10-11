import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../shared/ui/jk_icon.dart';
import '../../shared/ui/jk_states.dart';
import '../ledger/ledger_models.dart';
import '../ledger/ledger_repository.dart';
import '../ledger/ledger_widgets.dart';
import '../memos/memo_models.dart';
import '../memos/memo_widgets.dart';
import '../notes/note_models.dart';
import 'search_repository.dart';
import 'search_snippet.dart';

/// 全局搜索：关键词 + 模块 + 日期区间，结果按模块分组（ADR-010）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.module});

  /// 从某个模块进入时，默认只搜该模块。
  final SearchModule? module;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const _debounce = Duration(milliseconds: 250);

  final _text = TextEditingController();
  late SearchQuery _query = SearchQuery(modules: {?widget.module});
  SearchResult _result = SearchResult.empty;
  bool _loading = false;
  bool _failed = false;
  Timer? _timer;

  /// 每次搜索的序号：较早发起、较晚返回的结果直接丢弃。
  int _generation = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onText(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _update(_query.copyWith(text: text)));
  }

  void _update(SearchQuery q) {
    setState(() => _query = q);
    _run();
  }

  Future<void> _run() async {
    final gen = ++_generation;
    final q = _query;
    if (q.isEmpty) {
      setState(() {
        _result = SearchResult.empty;
        _loading = false;
        _failed = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ref.read(searchRepositoryProvider).search(q);
      if (!mounted || gen != _generation) return;
      setState(() {
        _result = r;
        _loading = false;
        _failed = false;
      });
    } on Object catch (e) {
      debugPrint('搜索失败: $e');
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _toggleModule(SearchModule? m) {
    final next = m == null
        ? <SearchModule>{}
        : (_query.modules.contains(m)
              ? ({..._query.modules}..remove(m))
              : {..._query.modules, m});
    _update(_query.copyWith(modules: next));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2199, 12, 31),
      initialDateRange: _query.from == null || _query.to == null
          ? null
          : DateTimeRange(start: _query.from!, end: _query.to!),
      currentDate: now,
      helpText: '选择时间范围',
    );
    if (picked != null) {
      _update(_query.copyWith(from: () => picked.start, to: () => picked.end));
    }
  }

  void _clearRange() =>
      _update(_query.copyWith(from: () => null, to: () => null));

  /// 打开一条结果；返回后重新搜索（内容可能已修改）。
  Future<void> _open(SearchHit h) async {
    final id = h.record.id;
    await context.push(switch (h.module) {
      SearchModule.worklog => '/worklog/$id',
      SearchModule.note => '/notes/$id',
      SearchModule.memo => '/memos/$id',
      SearchModule.ledger => '/ledger/entry/$id',
    });
    if (mounted) unawaited(_run());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('search-field'),
          controller: _text,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onText,
          onSubmitted: (t) {
            _timer?.cancel();
            _update(_query.copyWith(text: t));
          },
          decoration: InputDecoration(
            hintText: _query.modules.length == 1
                ? '搜索${_query.modules.first.label}'
                : '搜索全部内容',
            border: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_text.text.isNotEmpty)
            IconButton(
              key: const Key('search-clear'),
              tooltip: '清除',
              icon: const Icon(Icons.close),
              onPressed: () {
                _text.clear();
                _timer?.cancel();
                _update(_query.copyWith(text: ''));
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _Filters(
            query: _query,
            onModule: _toggleModule,
            onPickRange: _pickRange,
            onClearRange: _clearRange,
          ),
          Divider(height: 1, color: c.divider),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_failed) {
      return JkErrorState(message: '搜索失败', onRetry: _run);
    }
    if (_query.isEmpty) {
      return const JkEmptyState(
        icon: Icon(Icons.search),
        title: '搜索',
        message: '输入关键词搜索工作日志、笔记、备忘录和记账。多个关键词用空格分开，需同时满足。',
      );
    }
    if (_result.hits.isEmpty) {
      return _loading
          ? const SizedBox.shrink()
          : const JkEmptyState(
              icon: Icon(Icons.search_off),
              title: '没有找到相关内容',
              message: '换个关键词，或者放宽模块和时间筛选。',
            );
    }
    return _Results(result: _result, terms: _query.terms, onOpen: _open);
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.query,
    required this.onModule,
    required this.onPickRange,
    required this.onClearRange,
  });

  final SearchQuery query;
  final ValueChanged<SearchModule?> onModule;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  String _range() {
    String d(DateTime t) => '${t.year}/${t.month}/${t.day}';
    return '${d(query.from!)} – ${d(query.to!)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasRange = query.from != null && query.to != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: JkTokens.spacingMd,
        vertical: JkTokens.spacingSm,
      ),
      child: Row(
        children: [
          FilterChip(
            key: const Key('search-module-all'),
            label: const Text('全部'),
            selected: query.modules.isEmpty,
            onSelected: (_) => onModule(null),
          ),
          for (final m in SearchModule.values) ...[
            const SizedBox(width: JkTokens.spacingXs),
            FilterChip(
              key: Key('search-module-${m.name}'),
              label: Text(m.label),
              selected: query.modules.contains(m),
              onSelected: (_) => onModule(m),
            ),
          ],
          const SizedBox(width: JkTokens.spacingSm),
          hasRange
              ? InputChip(
                  key: const Key('search-range'),
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(_range()),
                  onPressed: onPickRange,
                  onDeleted: onClearRange,
                  deleteButtonTooltipMessage: '清除时间范围',
                )
              : ActionChip(
                  key: const Key('search-range'),
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: const Text('时间不限'),
                  onPressed: onPickRange,
                ),
        ],
      ),
    );
  }
}

/// 按模块分组的结果列表。
class _Results extends ConsumerWidget {
  const _Results({
    required this.result,
    required this.terms,
    required this.onOpen,
  });

  final SearchResult result;
  final List<String> terms;
  final ValueChanged<SearchHit> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final ledger = _LedgerNames(
      categories: {
        for (final x
            in ref.watch(categoriesProvider).value ?? const <LedgerCategory>[])
          x.id: x,
      },
      accounts: {
        for (final x in ref.watch(accountsProvider).value ?? const <Account>[])
          x.id: x,
      },
      loans: {
        for (final x in ref.watch(loansProvider).value ?? const <Loan>[])
          x.id: x,
      },
    );
    final groups = {
      for (final m in SearchModule.values)
        m: [
          for (final h in result.hits)
            if (h.module == m) h,
        ],
    }..removeWhere((_, v) => v.isEmpty);
    return ListView(
      key: const Key('search-results'),
      padding: const EdgeInsets.only(bottom: JkTokens.spacingXl),
      children: [
        if (result.truncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              JkTokens.spacingLg,
              JkTokens.spacingMd,
              JkTokens.spacingLg,
              0,
            ),
            child: Text(
              '共 ${result.total} 条，只显示最近的 ${result.hits.length} 条。'
              '可以添加关键词或筛选条件缩小范围。',
              style: t.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
        for (final MapEntry(key: m, value: hits) in groups.entries) ...[
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                JkTokens.spacingLg,
                JkTokens.spacingLg,
                JkTokens.spacingLg,
                JkTokens.spacingXs,
              ),
              child: Text(
                '${m.label} · ${result.counts[m] ?? hits.length}',
                key: Key('search-group-${m.name}'),
                style: t.titleSmall?.copyWith(color: c.textSecondary),
              ),
            ),
          ),
          for (final h in hits)
            _HitTile(
              hit: h,
              terms: terms,
              ledger: ledger,
              onTap: () => onOpen(h),
            ),
        ],
      ],
    );
  }
}

class _LedgerNames {
  const _LedgerNames({
    required this.categories,
    required this.accounts,
    required this.loans,
  });

  final Map<String, LedgerCategory> categories;
  final Map<String, Account> accounts;
  final Map<String, Loan> loans;
}

/// 一条结果：标题、带高亮的片段、日期；流水另显示金额。
class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.terms,
    required this.ledger,
    required this.onTap,
  });

  final SearchHit hit;
  final List<String> terms;
  final _LedgerNames ledger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final t = Theme.of(context).textTheme;
    final mark = TextStyle(
      color: c.primary,
      fontWeight: FontWeight.w700,
      backgroundColor: c.primaryContainer,
    );
    final h = hit;
    final (title, detail, trailing) = _describe(h);
    final snippet = h.body.isEmpty ? null : snippetOf(h.body, terms);
    return ListTile(
      key: Key('search-hit-${h.record.id}'),
      onTap: onTap,
      leading: _leading(h.module, c.textSecondary),
      title: HighlightText(
        snippetOf(title, terms, length: 60),
        style: t.bodyLarge,
        highlight: mark,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snippet != null && snippet.text != title)
            HighlightText(
              snippet,
              maxLines: 2,
              style: t.bodyMedium?.copyWith(color: c.textPrimary),
              highlight: mark,
            ),
          Text(detail, style: t.bodySmall?.copyWith(color: c.textSecondary)),
        ],
      ),
      trailing: trailing,
    );
  }

  Widget _leading(SearchModule m, Color color) => switch (m) {
    SearchModule.worklog => JkIcon(JkIcons.worklog, color: color),
    SearchModule.note => JkIcon(JkIcons.notes, color: color),
    SearchModule.memo => JkIcon(JkIcons.memos, color: color),
    SearchModule.ledger => JkIcon(JkIcons.ledger, color: color),
  };

  /// 标题、附加说明（日期等）与右侧内容。
  (String, String, Widget?) _describe(SearchHit h) {
    final r = h.record;
    switch (h.module) {
      case SearchModule.worklog:
        return (
          h.title.isEmpty ? h.day : '${h.day} · ${h.title}',
          '工作日志',
          null,
        );
      case SearchModule.note:
        return (Note.fromRecord(r).displayTitle, '修改于 ${h.day}', null);
      case SearchModule.memo:
        final m = Memo.fromRecord(r);
        return (m.title, memoWhen(m, DateTime.now()), null);
      case SearchModule.ledger:
        final e = Entry.fromRecord(r);
        if (e == null) return ('流水', h.day, null);
        return (
          entryTitle(
            e,
            categories: ledger.categories,
            accounts: ledger.accounts,
            loans: ledger.loans,
          ),
          h.day,
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: AmountText(signedAmount(e), signed: true),
            ),
          ),
        );
    }
  }
}
