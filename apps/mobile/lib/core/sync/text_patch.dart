import 'dart:convert';
import 'dart:math';

import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/foundation.dart';

/// 文本补丁片段，与服务端 `server/internal/textpatch` 一致（ADR-005）。
///
/// [pos] 为删除内容在基准文本中的起始位置，仅作定位提示；位置一律按 Unicode 码点计数。
@immutable
class Hunk {
  const Hunk({
    required this.pos,
    this.before = '',
    this.del = '',
    this.ins = '',
    this.after = '',
  });

  factory Hunk.fromJson(Map<String, dynamic> j) => Hunk(
    pos: (j['p'] as num).toInt(),
    before: j['b'] as String? ?? '',
    del: j['d'] as String? ?? '',
    ins: j['i'] as String? ?? '',
    after: j['a'] as String? ?? '',
  );

  final int pos;
  final String before;
  final String del;
  final String ins;
  final String after;

  Map<String, dynamic> toJson() => {
    'p': pos,
    'b': before,
    'd': del,
    'i': ins,
    'a': after,
  };
}

/// 补丁应用结果：失败（对方改了同一处）时 [text] 为原文。
typedef PatchResult = ({String text, bool ok});

/// 生成与应用带上下文的文本补丁。
abstract final class TextPatch {
  /// 默认前后文长度（码点），与 diff-match-patch 的 Patch_Margin 相同。
  static const _context = 4;

  /// 为消除歧义最多扩展到的前后文长度。
  static const _maxContext = 32;

  /// 生成把 [base] 改为 [target] 的补丁。
  static List<Hunk> make(String base, String target) {
    if (base == target) return const [];
    final b = base.runes.toList();
    final t = target.runes.toList();
    final regions = _regions(b, t);
    final hunks = <Hunk>[];
    for (var i = 0; i < regions.length; i++) {
      final r = regions[i];
      final lower = i == 0 ? 0 : regions[i - 1].end;
      final upper = i == regions.length - 1 ? b.length : regions[i + 1].start;
      hunks.add(_hunk(b, r, lower, upper));
    }
    return hunks;
  }

  /// 把补丁依次应用到 [text]，算法与服务端相同。
  static PatchResult apply(String text, List<Hunk> hunks) {
    final runes = text.runes.toList();
    var delta = 0;
    var minDel = 0;
    var lastPos = 0;
    for (final h in hunks) {
      if (h.pos < lastPos) return (text: text, ok: false);
      lastPos = h.pos;
      final before = h.before.runes.toList();
      final del = h.del.runes.toList();
      final ins = h.ins.runes.toList();
      final target = [...before, ...del, ...h.after.runes];
      final start = _nearest(
        runes,
        target,
        h.pos + delta - before.length,
        minDel - before.length,
      );
      if (start < 0) return (text: text, ok: false);
      final delStart = start + before.length;
      runes.replaceRange(delStart, delStart + del.length, ins);
      delta += ins.length - del.length;
      minDel = delStart + ins.length;
    }
    return (text: String.fromCharCodes(runes), ok: true);
  }

  /// 编码为推送时使用的 JSON 字符串。
  static String encode(List<Hunk> hunks) =>
      jsonEncode([for (final h in hunks) h.toJson()]);

  static List<Hunk> decode(String json) => [
    for (final h in jsonDecode(json) as List<dynamic>)
      Hunk.fromJson(h as Map<String, dynamic>),
  ];

  /// 计算修改区域：相邻修改之间的相同文本少于两倍前后文时合并为一个区域，保证各片段的上下文互不重叠。
  static List<_Region> _regions(List<int> base, List<int> target) {
    final diffs = _diffRunes(base, target);
    final regions = <_Region>[];
    var pos = 0; // 在 base 中的位置
    _Region? cur;
    for (final (op, runes) in diffs) {
      if (op == DIFF_EQUAL) {
        if (cur != null && runes.length < 2 * _context) {
          cur.del.addAll(runes);
          cur.ins.addAll(runes);
          cur.pending += runes.length;
        } else if (cur != null) {
          regions.add(cur..trimPending());
          cur = null;
        }
        pos += runes.length;
        continue;
      }
      cur ??= _Region(pos);
      cur.pending = 0; // 中间的相同文本已确定属于本区域
      if (op == DIFF_DELETE) {
        cur.del.addAll(runes);
        pos += runes.length;
      } else {
        cur.ins.addAll(runes);
      }
    }
    if (cur != null) regions.add(cur..trimPending());
    return regions;
  }

  static Hunk _hunk(List<int> base, _Region r, int lower, int upper) {
    var ctx = _context;
    while (true) {
      final bStart = max(lower, r.start - ctx);
      final aEnd = min(upper, r.end + ctx);
      final before = base.sublist(bStart, r.start);
      final after = base.sublist(r.end, aEnd);
      final unique =
          _count(base, [...before, ...r.del, ...after]) <= 1 ||
          ctx >= _maxContext ||
          (bStart == lower && aEnd == upper);
      if (unique) {
        return Hunk(
          pos: r.start,
          before: String.fromCharCodes(before),
          del: String.fromCharCodes(r.del),
          ins: String.fromCharCodes(r.ins),
          after: String.fromCharCodes(after),
        );
      }
      ctx += 4;
    }
  }

  /// 按码点做差异比较：把每个码点映射为一个 UTF-16 码元后交给 diff-match-patch，避免拆开代理对。
  static List<(int, List<int>)> _diffRunes(List<int> a, List<int> b) {
    final codec = _RuneCodec.build(a, b);
    if (codec == null) return _singleRegion(a, b);
    final dmp = DiffMatchPatch()..diffTimeout = 1.0;
    final diffs = dmp.diff(codec.encode(a), codec.encode(b));
    dmp.diffCleanupSemantic(diffs);
    return [for (final d in diffs) (d.operation, codec.decode(d.text))];
  }

  /// 无法编码时（极少见）退化为一个区域：去掉公共前后缀后整体替换。
  static List<(int, List<int>)> _singleRegion(List<int> a, List<int> b) {
    var p = 0;
    while (p < a.length && p < b.length && a[p] == b[p]) {
      p++;
    }
    var s = 0;
    while (s < a.length - p && s < b.length - p) {
      if (a[a.length - 1 - s] != b[b.length - 1 - s]) break;
      s++;
    }
    return [
      if (p > 0) (DIFF_EQUAL, a.sublist(0, p)),
      if (a.length - s > p) (DIFF_DELETE, a.sublist(p, a.length - s)),
      if (b.length - s > p) (DIFF_INSERT, b.sublist(p, b.length - s)),
      if (s > 0) (DIFF_EQUAL, a.sublist(a.length - s)),
    ];
  }

  static int _count(List<int> runes, List<int> target) {
    var n = 0;
    for (var i = 0; i + target.length <= runes.length; i++) {
      if (_equalAt(runes, i, target) && ++n > 1) return n;
    }
    return n;
  }

  static int _nearest(
    List<int> runes,
    List<int> target,
    int expected,
    int lowest,
  ) {
    var best = -1;
    for (var i = max(lowest, 0); i + target.length <= runes.length; i++) {
      if (best >= 0 && i - expected > (best - expected).abs()) break;
      if (_equalAt(runes, i, target) &&
          (best < 0 || (i - expected).abs() < (best - expected).abs())) {
        best = i;
      }
    }
    return best;
  }

  static bool _equalAt(List<int> runes, int at, List<int> target) {
    for (var j = 0; j < target.length; j++) {
      if (runes[at + j] != target[j]) return false;
    }
    return true;
  }
}

class _Region {
  _Region(this.start);

  final int start;
  final List<int> del = [];
  final List<int> ins = [];

  /// 区域末尾暂时并入、但之后没有新修改的相同文本长度（结束时去掉）。
  int pending = 0;

  int get end => start + del.length;

  void trimPending() {
    if (pending == 0) return;
    del.removeRange(del.length - pending, del.length);
    ins.removeRange(ins.length - pending, ins.length);
    pending = 0;
  }
}

/// 码点 ↔ 单个 UTF-16 码元的映射：基本平面字符原样保留，补充平面字符（如 emoji）映射到未使用的私用区码元。
class _RuneCodec {
  _RuneCodec._(this._toUnit, this._fromUnit);

  static _RuneCodec? build(List<int> a, List<int> b) {
    final used = <int>{...a, ...b};
    final toUnit = <int, int>{};
    final fromUnit = <int, int>{};
    var next = 0xE000;
    for (final r in used) {
      if (r <= 0xFFFF) continue;
      while (next <= 0xF8FF && used.contains(next)) {
        next++;
      }
      if (next > 0xF8FF) return null;
      toUnit[r] = next;
      fromUnit[next] = r;
      next++;
    }
    return _RuneCodec._(toUnit, fromUnit);
  }

  final Map<int, int> _toUnit;
  final Map<int, int> _fromUnit;

  String encode(List<int> runes) =>
      String.fromCharCodes([for (final r in runes) _toUnit[r] ?? r]);

  List<int> decode(String s) => [
    for (final u in s.codeUnits) _fromUnit[u] ?? u,
  ];
}
