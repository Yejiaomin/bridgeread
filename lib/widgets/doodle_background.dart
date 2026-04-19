import 'dart:math';
import 'package:flutter/material.dart';

/// Soft cream background with sepia line-art doodles (books, stars, paws,
/// flowers, etc) scattered across. Used by ProfileScreen and as the fallback
/// background for StudyScreen when the bg image fails to load.
///
/// [color] for solid fill. Pass [gradient] for a more dimensional look.
class DoodleBackground extends StatelessWidget {
  final Color color;
  final Gradient? gradient;
  const DoodleBackground({
    super.key,
    this.color = const Color(0xFFFFF0DC),
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
      ),
      child: CustomPaint(
        painter: DoodleBgPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class DoodleBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);

    final drawFns = <void Function(Canvas, Offset, double)>[
      _drawBook, _drawStar, _drawNote, _drawFlame, _drawPencil,
      _drawCamera, _drawHeart, _drawCloud, _drawPaw, _drawFlower,
    ];

    const cols = 9;
    const rows = 5;
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (int i = 0; i < cols * rows; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final x = (col + 0.2 + rng.nextDouble() * 0.6) * cellW;
      final y = (row + 0.2 + rng.nextDouble() * 0.6) * cellH;
      final s = 21.0 + rng.nextDouble() * 18;
      final rotation = (rng.nextDouble() - 0.5) * 0.4;
      final fn = drawFns[i % drawFns.length];

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      fn(canvas, Offset.zero, s);
      canvas.restore();
    }
  }

  Paint get _p => Paint()
    ..color = const Color(0xFFB89968).withOpacity(0.65)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;

  void _drawBook(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawLine(Offset(o.dx, o.dy - s * 0.3), Offset(o.dx - s * 0.4, o.dy - s * 0.2), p);
    c.drawLine(Offset(o.dx - s * 0.4, o.dy - s * 0.2), Offset(o.dx - s * 0.4, o.dy + s * 0.3), p);
    c.drawLine(Offset(o.dx - s * 0.4, o.dy + s * 0.3), Offset(o.dx, o.dy + s * 0.2), p);
    c.drawLine(Offset(o.dx, o.dy - s * 0.3), Offset(o.dx + s * 0.4, o.dy - s * 0.2), p);
    c.drawLine(Offset(o.dx + s * 0.4, o.dy - s * 0.2), Offset(o.dx + s * 0.4, o.dy + s * 0.3), p);
    c.drawLine(Offset(o.dx + s * 0.4, o.dy + s * 0.3), Offset(o.dx, o.dy + s * 0.2), p);
    c.drawLine(Offset(o.dx, o.dy - s * 0.3), Offset(o.dx, o.dy + s * 0.2), p);
  }

  void _drawStar(Canvas c, Offset o, double s) {
    final p = _p;
    final r = s * 0.4;
    final ir = r * 0.4;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final a = (i * pi / 5) - pi / 2;
      final rad = i.isEven ? r : ir;
      final pt = Offset(o.dx + cos(a) * rad, o.dy + sin(a) * rad);
      if (i == 0) path.moveTo(pt.dx, pt.dy); else path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    c.drawPath(path, p);
  }

  void _drawNote(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawLine(Offset(o.dx, o.dy - s * 0.35), Offset(o.dx, o.dy + s * 0.2), p);
    c.drawLine(Offset(o.dx, o.dy - s * 0.35), Offset(o.dx + s * 0.2, o.dy - s * 0.15), p);
    c.drawOval(Rect.fromCenter(
      center: Offset(o.dx - s * 0.06, o.dy + s * 0.25), width: s * 0.22, height: s * 0.15), p);
  }

  void _drawFlame(Canvas c, Offset o, double s) {
    final p = _p;
    final path = Path()
      ..moveTo(o.dx, o.dy - s * 0.4)
      ..quadraticBezierTo(o.dx + s * 0.3, o.dy - s * 0.1, o.dx + s * 0.15, o.dy + s * 0.3)
      ..quadraticBezierTo(o.dx, o.dy + s * 0.15, o.dx, o.dy + s * 0.3)
      ..quadraticBezierTo(o.dx, o.dy + s * 0.15, o.dx - s * 0.15, o.dy + s * 0.3)
      ..quadraticBezierTo(o.dx - s * 0.3, o.dy - s * 0.1, o.dx, o.dy - s * 0.4);
    c.drawPath(path, p);
  }

  void _drawPencil(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawLine(Offset(o.dx - s * 0.3, o.dy + s * 0.3), Offset(o.dx + s * 0.2, o.dy - s * 0.2), p);
    c.drawLine(Offset(o.dx - s * 0.25, o.dy + s * 0.22), Offset(o.dx + s * 0.25, o.dy - s * 0.28), p);
    c.drawLine(Offset(o.dx - s * 0.3, o.dy + s * 0.3), Offset(o.dx - s * 0.38, o.dy + s * 0.38), p);
    c.drawLine(Offset(o.dx + s * 0.2, o.dy - s * 0.2), Offset(o.dx + s * 0.25, o.dy - s * 0.28), p);
  }

  void _drawCamera(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(o.dx, o.dy + s * 0.05), width: s * 0.7, height: s * 0.45),
      Radius.circular(s * 0.06)), p);
    c.drawCircle(Offset(o.dx, o.dy + s * 0.05), s * 0.13, p);
    c.drawLine(Offset(o.dx - s * 0.1, o.dy - s * 0.18), Offset(o.dx + s * 0.1, o.dy - s * 0.18), p);
    c.drawLine(Offset(o.dx + s * 0.1, o.dy - s * 0.18), Offset(o.dx + s * 0.15, o.dy - s * 0.1), p);
    c.drawLine(Offset(o.dx - s * 0.1, o.dy - s * 0.18), Offset(o.dx - s * 0.15, o.dy - s * 0.1), p);
  }

  void _drawHeart(Canvas c, Offset o, double s) {
    final p = _p;
    final path = Path()
      ..moveTo(o.dx, o.dy + s * 0.3)
      ..cubicTo(o.dx - s * 0.4, o.dy, o.dx - s * 0.4, o.dy - s * 0.3, o.dx, o.dy - s * 0.1)
      ..cubicTo(o.dx + s * 0.4, o.dy - s * 0.3, o.dx + s * 0.4, o.dy, o.dx, o.dy + s * 0.3);
    c.drawPath(path, p);
  }

  void _drawCloud(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawOval(Rect.fromCenter(center: Offset(o.dx - s * 0.15, o.dy), width: s * 0.35, height: s * 0.25), p);
    c.drawOval(Rect.fromCenter(center: Offset(o.dx + s * 0.1, o.dy - s * 0.05), width: s * 0.4, height: s * 0.3), p);
    c.drawOval(Rect.fromCenter(center: Offset(o.dx + s * 0.3, o.dy + s * 0.02), width: s * 0.3, height: s * 0.22), p);
  }

  void _drawPaw(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawOval(Rect.fromCenter(center: Offset(o.dx, o.dy + s * 0.1), width: s * 0.3, height: s * 0.25), p);
    c.drawCircle(Offset(o.dx - s * 0.15, o.dy - s * 0.12), s * 0.08, p);
    c.drawCircle(Offset(o.dx + s * 0.15, o.dy - s * 0.12), s * 0.08, p);
    c.drawCircle(Offset(o.dx - s * 0.06, o.dy - s * 0.22), s * 0.07, p);
    c.drawCircle(Offset(o.dx + s * 0.06, o.dy - s * 0.22), s * 0.07, p);
  }

  void _drawFlower(Canvas c, Offset o, double s) {
    final p = _p;
    c.drawCircle(o, s * 0.1, p);
    for (int i = 0; i < 5; i++) {
      final a = i * 2 * pi / 5 - pi / 2;
      final px = o.dx + cos(a) * s * 0.22;
      final py = o.dy + sin(a) * s * 0.22;
      c.drawCircle(Offset(px, py), s * 0.1, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
