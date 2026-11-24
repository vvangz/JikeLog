import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 即刻日志（JikeLog）品牌徽标：「瞬刻书签 · J-Log Emblem」。
///
/// 24×24 几何网格构图：圆角日志页外框 + 极简记录微线 + 现代无衬线「J」字标 +
/// 左上四角星芒（✦ 象征「即刻 / 瞬时灵感」），在 18dp 导航栏图标到 72dp 欢迎页
/// 均保持锐利识别度。
class JkLogo extends StatelessWidget {
  const JkLogo({super.key, this.size = 24, this.color, this.sparkColor});

  final double size;
  final Color? color;
  final Color? sparkColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = color ?? scheme.primary;
    final spark = sparkColor ?? (color ?? scheme.tertiary);
    return CustomPaint(
      size: Size.square(size),
      painter: _JkLogoPainter(primary: primary, spark: spark),
    );
  }
}

class _JkLogoPainter extends CustomPainter {
  _JkLogoPainter({required this.primary, required this.spark});

  final Color primary;
  final Color spark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s, s);

    // 1. 圆角日志页外框（低饱和描边 + 轻透底色，象征「日志 / Log」）
    final frameRect = RRect.fromRectAndRadius(
      const Rect.fromLTRB(2.4, 2.4, 21.6, 21.6),
      const Radius.circular(5.2),
    );
    final fillPaint = Paint()
      ..color = primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(frameRect, fillPaint);

    final borderPaint = Paint()
      ..color = primary.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;
    canvas.drawRRect(frameRect, borderPaint);

    // 2. 左侧极简日志条目微线（一长一短，位于星芒与 J 底钩之间）
    final linePaint = Paint()
      ..color = primary.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(5.8, 12.2),
      const Offset(10.6, 12.2),
      linePaint,
    );
    canvas.drawLine(
      const Offset(5.8, 14.3),
      const Offset(8.6, 14.3),
      linePaint,
    );

    // 3. 主体现代无衬线「J」字标（纯净竖干 + 顺滑圆弧底钩）
    final jPaint = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final jPath = Path()
      ..moveTo(15.6, 6.2)
      ..lineTo(15.6, 14.0)
      ..arcTo(
        Rect.fromCircle(center: const Offset(11.9, 14.0), radius: 3.7),
        0,
        math.pi * 0.86,
        false,
      );
    canvas.drawPath(jPath, jPaint);

    // 4. 左上四角星芒（✦ 即刻灵感）
    final sparkPaint = Paint()
      ..color = spark
      ..style = PaintingStyle.fill;
    const cx = 8.4;
    const cy = 7.9;
    const r = 2.65;
    const c = r * 0.24;
    final star = Path()
      ..moveTo(cx, cy - r)
      ..quadraticBezierTo(cx + c, cy - c, cx + r, cy)
      ..quadraticBezierTo(cx + c, cy + c, cx, cy + r)
      ..quadraticBezierTo(cx - c, cy + c, cx - r, cy)
      ..quadraticBezierTo(cx - c, cy - c, cx, cy - r)
      ..close();
    canvas.drawPath(star, sparkPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_JkLogoPainter old) =>
      old.primary != primary || old.spark != spark;
}
