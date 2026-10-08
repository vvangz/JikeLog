import 'package:flutter/material.dart';

/// 即刻日志自绘图标：24 栅格、1.5 描边、圆角端点（与 Lucide 风格一致），随文字颜色变化。
enum JkIcons { worklog, notes, memos, ledger, settings, account }

class JkIcon extends StatelessWidget {
  const JkIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  final JkIcons icon;
  final double size;

  /// 为空时使用 IconTheme 颜色。
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final painted = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _IconPainter(icon, c)),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: painted)
        : Semantics(label: semanticLabel, child: painted);
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.icon, this.color);

  final JkIcons icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), p);
    void rect(double l, double t, double w, double h, double r) => canvas
        .drawRRect(RRect.fromLTRBR(l, t, l + w, t + h, Radius.circular(r)), p);
    switch (icon) {
      case JkIcons.worklog: // 公文包
        rect(3, 7, 18, 13, 2);
        canvas.drawPath(
          Path()
            ..moveTo(9, 7)
            ..lineTo(9, 5)
            ..arcToPoint(const Offset(11, 3), radius: const Radius.circular(2))
            ..lineTo(13, 3)
            ..arcToPoint(const Offset(15, 5), radius: const Radius.circular(2))
            ..lineTo(15, 7),
          p,
        );
        line(3, 13, 21, 13);
        line(12, 12, 12, 14);
      case JkIcons.notes: // 笔记本
        rect(6, 3, 14, 18, 2);
        line(4, 7, 6, 7);
        line(4, 12, 6, 12);
        line(4, 17, 6, 17);
        line(10, 8, 16, 8);
        line(10, 12, 16, 12);
        line(10, 16, 13, 16);
      case JkIcons.memos: // 闹钟
        canvas.drawCircle(const Offset(12, 13), 7.5, p);
        canvas.drawPath(
          Path()
            ..moveTo(12, 9.5)
            ..lineTo(12, 13)
            ..lineTo(14.5, 15),
          p,
        );
        line(5, 3.5, 2.5, 6);
        line(19, 3.5, 21.5, 6);
      case JkIcons.ledger: // 钱包
        rect(3, 6, 18, 14, 2);
        canvas.drawPath(
          Path()
            ..moveTo(3, 9)
            ..lineTo(18, 9)
            ..moveTo(5, 6)
            ..lineTo(15, 3.5)
            ..lineTo(16, 6),
          p,
        );
        canvas.drawCircle(const Offset(16.5, 14.5), 1.2, p);
      case JkIcons.settings: // 调节滑杆
        line(4, 6, 12, 6);
        line(18, 6, 20, 6);
        line(4, 12, 6, 12);
        line(12, 12, 20, 12);
        line(4, 18, 14, 18);
        line(20, 18, 20, 18);
        canvas.drawCircle(const Offset(15, 6), 2.5, p);
        canvas.drawCircle(const Offset(9, 12), 2.5, p);
        canvas.drawCircle(const Offset(17, 18), 2.5, p);
      case JkIcons.account: // 用户
        canvas.drawCircle(const Offset(12, 8), 4, p);
        canvas.drawPath(
          Path()
            ..moveTo(4.5, 20.5)
            ..arcToPoint(
              const Offset(19.5, 20.5),
              radius: const Radius.circular(7.5),
            ),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}
