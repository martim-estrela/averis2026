import 'package:flutter/material.dart';

class ReadingsChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> readings;

  ReadingsChartPainter(this.readings);

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = Colors.blue.shade400
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final paintDot = Paint()
      ..color = Colors.blue
      ..strokeCap = StrokeCap.round;

    if (readings.isEmpty) return;

    // Normaliza pontos para caber no gráfico
    final maxPower = readings
        .map((r) => r['powerW'] as double)
        .reduce((a, b) => a > b ? a : b);
    final points = readings.asMap().entries.map((entry) {
      final i = entry.key;
      final reading = entry.value;
      final x = 40 + (i * (size.width - 80) / (readings.length - 1));
      final y =
          size.height -
          40 -
          ((reading['powerW'] as double) / maxPower * (size.height - 80));
      return Offset(x, y.clamp(40, size.height - 40));
    }).toList();

    // Linha
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paintLine);

    // Pontos
    for (final point in points) {
      canvas.drawCircle(point, 4, paintDot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
