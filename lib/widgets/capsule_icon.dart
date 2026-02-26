import 'package:flutter/material.dart';

class CapsuleIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const CapsuleIcon({
    super.key,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: CapsulePainter(color ?? Colors.white),
    );
  }
}

class CapsulePainter extends CustomPainter {
  final Color color;

  CapsulePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final radius = width * 0.15;

    // Cápsula superior (roja)
    final topPaint = Paint()..color = Colors.red;
    final topRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(width * 0.2, height * 0.1, width * 0.6, height * 0.4),
      topLeft: Radius.circular(radius),
      topRight: Radius.circular(radius),
    );
    canvas.drawRRect(topRect, topPaint);

    // Cápsula inferior (azul)
    final bottomPaint = Paint()..color = Colors.blue;
    final bottomRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(width * 0.2, height * 0.5, width * 0.6, height * 0.4),
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );
    canvas.drawRRect(bottomRect, bottomPaint);

    // Línea divisoria
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(width * 0.2, height * 0.5),
      Offset(width * 0.8, height * 0.5),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
