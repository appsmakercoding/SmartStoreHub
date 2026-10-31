import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ui.dart';

class LogoPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    c.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * .24)),
      Paint()
        ..shader = const LinearGradient(colors: [C.teal, C.dark], begin: Alignment.topLeft, end: Alignment.bottomRight)
            .createShader(Offset.zero & s),
    );
    final bag = Path()
      ..moveTo(w * .28, w * .38)
      ..lineTo(w * .72, w * .38)
      ..lineTo(w * .78, w * .76)
      ..quadraticBezierTo(w * .78, w * .8, w * .72, w * .8)
      ..lineTo(w * .28, w * .8)
      ..quadraticBezierTo(w * .22, w * .8, w * .22, w * .76)
      ..close();
    c.drawPath(bag, Paint()..color = Colors.white);
    c.drawArc(
      Rect.fromLTWH(w * .36, w * .2, w * .28, w * .36),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .045
        ..strokeCap = StrokeCap.round
        ..color = C.gold,
    );
    final a = Offset(w * .38, w * .52), b = Offset(w * .62, w * .52), m = Offset(w * .5, w * .68);
    final line = Paint()
      ..color = C.teal
      ..strokeWidth = w * .02;
    c.drawLine(a, m, line);
    c.drawLine(b, m, line);
    c.drawLine(a, b, line);
    c.drawCircle(a, w * .04, Paint()..color = C.teal);
    c.drawCircle(b, w * .04, Paint()..color = C.teal);
    c.drawCircle(m, w * .045, Paint()..color = C.gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 100});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: LogoPainter());
}
