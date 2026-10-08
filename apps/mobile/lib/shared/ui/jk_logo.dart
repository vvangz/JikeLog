import 'package:flutter/material.dart';

/// 即刻日志标志：线框笔记本 + 实心圆点。
///
/// 与 Web 端 logo.svg 同一造型，按 24 栅格、1.5 描边绘制后等比缩放。
class JkLogo extends StatelessWidget {
  const JkLogo({super.key, this.size = 24, this.color});

  final double size;

  /// 为空时使用主题主色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LogoPainter(color ?? Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, 3, 16, 18),
        const Radius.circular(3),
      ),
      stroke,
    );
    canvas
      ..drawLine(const Offset(8, 8), const Offset(16, 8), stroke)
      ..drawLine(const Offset(8, 12), const Offset(16, 12), stroke)
      ..drawLine(const Offset(8, 16), const Offset(13, 16), stroke)
      ..drawCircle(const Offset(17, 17), 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.color != color;
}
