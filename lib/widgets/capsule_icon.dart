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
    final theme = Theme.of(context);
    final topColor = color ?? theme.colorScheme.primary;
    final bottomColor = color ?? theme.colorScheme.secondary;

    return CustomPaint(
      size: Size(size, size),
      painter: CapsulePainter(topColor, bottomColor),
    );
  }
}

class CapsulePainter extends CustomPainter {
  final Color topColor;
  final Color bottomColor;

  CapsulePainter(this.topColor, this.bottomColor);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final radius = width * 0.15;

    // Cápsula superior
    final topPaint = Paint()..color = topColor;
    final topRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(width * 0.2, height * 0.1, width * 0.6, height * 0.4),
      topLeft: Radius.circular(radius),
      topRight: Radius.circular(radius),
    );
    canvas.drawRRect(topRect, topPaint);

    // Cápsula inferior
    final bottomPaint = Paint()..color = bottomColor;
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
