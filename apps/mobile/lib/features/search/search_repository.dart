/// 全局搜索（ADR-010）：在本地 FTS5 trigram 索引中查找，覆盖四个模块。
library;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/search/search_doc.dart';
import '../../core/sync/record_store.dart';
import '../../core/sync/schema.dart';
import '../../core/sync/sync_providers.dart';

/// 可筛选的模块。
enum SearchModule {
  worklog('工作日志', Entities.worklog),
  note('笔记', Entities.note),
  memo('备忘录', Entities.memo),
  ledger('记账', Entities.ledgerEntry);

  const SearchModule(this.label, this.entity);
  final String label;

  /// 作为搜索结果的实体。
  final String entity;

  static SearchModule? ofEntity(String entity) {
    for (final m in values) {
      if (m.entity == entity) return m;
    }
    return null;
  }

  /// 路由参数 / 模块路径（如 `notes`、`/notes`）对应的模块。
  static SearchModule? parse(String? s) => switch (s?.replaceAll('/', '')) {
    'worklog' => worklog,
    'note' || 'notes' => note,
    'memo' || 'memos' => memo,
    'ledger' => ledger,
    _ => null,
  };
}

/// 一次搜索的条件。
@immutable
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.modules = const {},
    this.from,
    this.to,
  });

  /// 关键词，按空白拆分，多个关键词同时满足。
  final String text;

  /// 为空表示全部模块。
  final Set<SearchModule> modules;

  /// 日期区间（含两端，只比较日期）。
  final DateTime? from;
  final DateTime? to;

  /// 关键词最多个数，多出的忽略。
  static const maxTerms = 5;

  /// 单个关键词最多字符数，多出的截掉。
  static const maxTermLength = 50;

  List<String> get terms => [
    for (final t in text.trim().split(RegExp(r'\s+')))
      if (t.isNotEmpty) String.fromCharCodes(t.runes.take(maxTermLength)),
  ].take(maxTerms).toList();

  bool get isEmpty => terms.isEmpty;

  SearchQuery copyWith({
    String? text,
    Set<SearchModule>? modules,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) => SearchQuery(
    text: text ?? this.text,
    modules: modules ?? this.modules,
    from: from == null ? this.from : from(),
    to: to == null ? this.to : to(),
  );

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.text == text &&
      setEquals(other.modules, modules) &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode =>
      Object.hash(text, Object.hashAllUnordered(modules), from, to);
}

/// 一条搜索结果。
@immutable
class SearchHit {
  const SearchHit({
    required this.record,
    required this.module,
    required this.day,
    required this.title,
    required this.body,
  });

  final LocalRecord record;
  final SearchModule module;
  final String day;

  /// 索引中的标题与正文（纯文本），用于显示片段。
  final String title;
  final String body;
}

/// 搜索结果：按日期从新到旧，最多 [SearchRepository.maxHits] 条。
@immutable
class SearchResult {
  const SearchResult({required this.hits, required this.counts});

  static const empty = SearchResult(hits: [], counts: {});

  final List<SearchHit> hits;

  /// 各模块命中的总条数（含超出上限未返回的）。
  final Map<SearchModule, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);
  bool get truncated => total > hits.length;
}

class SearchRepository {
  SearchRepository(this.db);

  final AppDatabase db;

  /// 一次最多返回的结果数。
  static const maxHits = 200;

  /// trigram 索引能匹配的最短关键词；更短的用 LIKE 扫描。
  static const _minTrigram = 3;

  Future<SearchResult> search(SearchQuery q) async {
    final terms = q.terms;
    if (terms.isEmpty) return SearchResult.empty;
    Set<String>? ids;
    for (final t in terms) {
      final hit = await _expand(await _match(t));
      ids = ids == null ? hit : ids.intersection(hit);
      if (ids.isEmpty) return SearchResult.empty;
    }
    return _collect(ids!, q);
  }

  /// 一个关键词直接命中的记录：ID → 实体。
  Future<Map<String, String>> _match(String term) async {
    final rows = term.runes.length >= _minTrigram
        ? await db
              .customSelect(
                'SELECT d.record_id, d.entity FROM search_fts f '
                'JOIN search_docs d ON d.id = f.rowid WHERE search_fts MATCH ?',
                variables: [Variable('"${term.replaceAll('"', '""')}"')],
              )
              .get()
        : await db
              .customSelect(
                'SELECT record_id, entity FROM search_docs '
                r"WHERE title LIKE ?1 ESCAPE '\' OR body LIKE ?1 ESCAPE '\'",
                variables: [Variable('%${_escapeLike(term)}%')],
              )
              .get();
    return {
      for (final r in rows)
        r.read<String>('record_id'): r.read<String>('entity'),
    };
  }

  /// 命中分类、账户或借贷时，引用它们的流水也算命中（一级分类连同其二级分类）。
  /// 返回只含作为结果的实体的 ID。
  Future<Set<String>> _expand(Map<String, String> matched) async {
    final result = <String>{};
    final categories = <String>{};
    final accounts = <String>{};
    final loans = <String>{};
    for (final MapEntry(key: id, value: entity) in matched.entries) {
      switch (entity) {
        case Entities.ledgerCategory:
          categories.add(id);
        case Entities.ledgerAccount:
          accounts.add(id);
        case Entities.ledgerLoan:
          loans.add(id);
        default:
          if (SearchModule.ofEntity(entity) != null) result.add(id);
      }
    }
    if (categories.isNotEmpty) {
      categories.addAll(
        await _idsWhere(Entities.ledgerCategory, {'parentId': categories}),
      );
    }
    if (categories.isEmpty && accounts.isEmpty && loans.isEmpty) return result;
    result.addAll(
      await _idsWhere(Entities.ledgerEntry, {
        'categoryId': categories,
        'accountId': accounts,
        'toAccountId': accounts,
        'loanId': loans,
      }),
    );
    return result;
  }

  /// [entity] 中任一字段的值属于给定集合的记录 ID。
  Future<Set<String>> _idsWhere(
    String entity,
    Map<String, Set<String>> anyOf,
  ) async {
    final conds = <String>[];
    final vars = <Variable>[Variable(entity)];
    for (final MapEntry(key: field, value: values) in anyOf.entries) {
      if (values.isEmpty) continue;
      conds.add(
        "json_extract(fields, '\$.$field') IN "
        '(${List.filled(values.length, '?').join(', ')})',
      );
      vars.addAll(values.map(Variable.new));
    }
    if (conds.isEmpty) return {};
    final rows = await db
        .customSelect(
          'SELECT id FROM records WHERE entity = ? AND deleted = 0 '
          'AND (${conds.join(' OR ')})',
          variables: vars,
        )
        .get();
    return {for (final r in rows) r.read<String>('id')};
  }

  /// 按模块与日期筛选、排序并加载记录。
  Future<SearchResult> _collect(Set<String> ids, SearchQuery q) async {
    final docs = <(String, SearchModule, String, String, String)>[];
    final from = q.from == null ? null : formatDay(q.from!);
    final to = q.to == null ? null : formatDay(q.to!);
    for (final chunk in _chunks(ids.toList(), 500)) {
      final rows = await db
          .customSelect(
            'SELECT record_id, entity, day, title, body FROM search_docs '
            'WHERE record_id IN (${List.filled(chunk.length, '?').join(', ')})',
            variables: chunk.map(Variable.new).toList(),
          )
          .get();
      for (final r in rows) {
        final module = SearchModule.ofEntity(r.read<String>('entity'));
        final day = r.read<String>('day');
        if (module == null) continue;
        if (q.modules.isNotEmpty && !q.modules.contains(module)) continue;
        if (from != null && day.compareTo(from) < 0) continue;
        if (to != null && day.compareTo(to) > 0) continue;
        docs.add((
          r.read<String>('record_id'),
          module,
          day,
          r.read<String>('title'),
          r.read<String>('body'),
        ));
      }
    }
    // 日期从新到旧；同一天按 ID 倒序（UUIDv7 大致是创建先后）
    docs.sort((a, b) {
      final d = b.$3.compareTo(a.$3);
      return d != 0 ? d : b.$1.compareTo(a.$1);
    });
    final counts = <SearchModule, int>{};
    for (final d in docs) {
      counts[d.$2] = (counts[d.$2] ?? 0) + 1;
    }
    final top = docs.take(maxHits).toList();
    final records = await _records(top.map((d) => d.$1).toList());
    return SearchResult(
      hits: [
        for (final (id, module, day, title, body) in top)
          if (records[id] case final r?)
            SearchHit(
              record: r,
              module: module,
              day: day,
              title: title,
              body: body,
            ),
      ],
      counts: counts,
    );
  }

  Future<Map<String, LocalRecord>> _records(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (db.select(
      db.records,
    )..where((t) => t.id.isIn(ids) & t.deleted.not())).get();
    return {for (final r in rows) r.id: LocalRecord.fromRow(r)};
  }

  static Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, i + size > list.length ? list.length : i + size);
    }
  }

  static String _escapeLike(String s) =>
      s.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(appDatabaseProvider)),
);
