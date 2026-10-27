import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// 热力图格子间距。
const _gap = 3.0;

/// 记录热力图：每列一周、每行一天，颜色深浅表示当天篇数。
/// 按可用宽度显示最近的若干周（格子大小由高度决定）。
class Heatmap extends StatelessWidget {
  const Heatmap({super.key, required this.weeks, this.height = 95});

  /// 按周排列的每天篇数，最早的一周在前；-1 表示还没到的日子。
  final List<List<int>> weeks;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final days = weeks.expand((w) => w).where((n) => n > 0).length;
    return Semantics(
      label: '记录热力图，近 ${weeks.length} 周有 $days 天写了日志',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _HeatmapPainter(
            weeks: weeks,
            empty: c.surfaceVariant,
            fill: c.primary,
          ),
        ),
      ),
    );
  }
}

/// 热力图的图例：少 □□□□ 多。
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: c.textSecondary);
    Widget cell(Color color) => Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2.5),
      ),
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('少', style: style),
          const SizedBox(width: 4),
          cell(c.surfaceVariant),
          for (final level in [1, 2, 3]) cell(_levelColor(c.primary, level)),
          const SizedBox(width: 4),
          Text('多', style: style),
        ],
      ),
    );
  }
}

Color _levelColor(Color fill, int count) => switch (count) {
  1 => fill.withValues(alpha: 0.4),
  2 => fill.withValues(alpha: 0.7),
  _ => fill,
};

class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter({
    required this.weeks,
    required this.empty,
    required this.fill,
  });

  final List<List<int>> weeks;
  final Color empty;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;
    final cell = (size.height - _gap * 6) / 7;
    final cols = math.min(
      weeks.length,
      ((size.width + _gap) / (cell + _gap)).floor(),
    );
    if (cols <= 0) return;
    // 剩余宽度左右均分，网格居中
    final dx = (size.width - (cols * (cell + _gap) - _gap)) / 2;
    final radius = Radius.circular(cell * 0.28);
    final paint = Paint();
    final shown = weeks.sublist(weeks.length - cols);
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < 7; y++) {
        final n = shown[x][y];
        if (n < 0) continue;
        paint.color = n == 0 ? empty : _levelColor(fill, n);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              dx + x * (cell + _gap),
              y * (cell + _gap),
              cell,
              cell,
            ),
            radius,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.weeks != weeks || old.empty != empty || old.fill != fill;
}

/// 完成率圆环；[ratio] 为 null 时显示"—"。
class CompletionRing extends StatelessWidget {
  const CompletionRing({super.key, required this.ratio, this.size = 64});

  final double? ratio;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final reduce = MediaQuery.of(context).disableAnimations;
    final r = ratio;
    return Semantics(
      label: r == null ? '本周没有备忘' : '本周完成 ${(r * 100).round()}%',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: r ?? 0),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(
              value: v,
              track: c.surfaceVariant,
              fill: r == 1 ? c.success : c.primary,
            ),
            child: Center(
              child: Text(
                r == null ? '—' : '${(v * 100).round()}%',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  static const _stroke = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, p);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0, 1),
      false,
      p..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// 迷你折线（面积渐变），只看走势，不显示坐标轴。
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 56});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.jkColors;
    final reduce = MediaQuery.of(context).disableAnimations;
    final top = values.fold(0, math.max);
    final spots = [
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i].toDouble()),
    ];
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LineChart(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
          LineChartData(
            minY: 0,
            maxY: top == 0 ? 1 : top * 1.15,
            minX: 0,
            maxX: math.max(1, values.length - 1).toDouble(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            clipData: const FlClipData.all(),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.3,
                preventCurveOverShooting: true,
                color: c.primary,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  checkToShowDot: (s, _) => s.x == spots.length - 1,
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 3,
                    color: c.primary,
                    strokeWidth: 2,
                    strokeColor: c.surface,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c.primary.withValues(alpha: 0.22),
                      c.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
