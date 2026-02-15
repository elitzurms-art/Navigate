import 'package:flutter/material.dart';
import '../../services/route_analysis_service.dart';

/// גרף פרופיל מהירות — מציג מהירות לאורך הזמן
class SpeedProfileChart extends StatelessWidget {
  final List<SpeedSegment> segments;
  final double maxSpeedKmh;
  final double? thresholdSpeedKmh;

  const SpeedProfileChart({
    super.key,
    required this.segments,
    this.maxSpeedKmh = 15.0,
    this.thresholdSpeedKmh,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('אין נתוני מהירות', style: TextStyle(color: Colors.grey))),
      );
    }

    final effectiveMax = segments.fold<double>(
      maxSpeedKmh,
      (max, s) => s.speedKmh > max ? s.speedKmh : max,
    ) * 1.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת
        Row(
          children: [
            const Icon(Icons.speed, size: 18, color: Colors.blue),
            const SizedBox(width: 6),
            const Text('פרופיל מהירות',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const Spacer(),
            Text(
              'מקס\' ${_maxSpeed.toStringAsFixed(1)} קמ"ש',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // גרף
        SizedBox(
          height: 120,
          child: CustomPaint(
            size: const Size(double.infinity, 120),
            painter: _SpeedChartPainter(
              segments: segments,
              maxSpeed: effectiveMax,
              thresholdSpeed: thresholdSpeedKmh,
            ),
          ),
        ),

        // ציר זמן
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatTime(segments.first.timestamp),
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(_formatTime(segments.last.timestamp),
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),

        // מקרא
        if (thresholdSpeedKmh != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Container(width: 16, height: 2, color: Colors.red),
              const SizedBox(width: 4),
              Text('סף מהירות (${thresholdSpeedKmh!.toStringAsFixed(0)} קמ"ש)',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ],
    );
  }

  double get _maxSpeed {
    if (segments.isEmpty) return 0;
    return segments.fold<double>(0, (max, s) => s.speedKmh > max ? s.speedKmh : max);
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _SpeedChartPainter extends CustomPainter {
  final List<SpeedSegment> segments;
  final double maxSpeed;
  final double? thresholdSpeed;

  _SpeedChartPainter({
    required this.segments,
    required this.maxSpeed,
    this.thresholdSpeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty || maxSpeed <= 0) return;

    final w = size.width;
    final h = size.height;

    // סף מהירות
    if (thresholdSpeed != null) {
      final threshY = h - (thresholdSpeed! / maxSpeed) * h;
      final threshPaint = Paint()
        ..color = Colors.red.withOpacity(0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, threshY), Offset(w, threshY), threshPaint);
    }

    // קווי רשת אופקיים
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 4; i++) {
      final y = h * i / 5;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // מילוי מתחת לקו
    final fillPath = Path();
    final startMs = segments.first.timestamp.millisecondsSinceEpoch.toDouble();
    final endMs = segments.last.timestamp.millisecondsSinceEpoch.toDouble();
    final range = endMs - startMs;
    if (range <= 0) return;

    for (int i = 0; i < segments.length; i++) {
      final x = ((segments[i].timestamp.millisecondsSinceEpoch - startMs) / range) * w;
      final y = h - (segments[i].speedKmh / maxSpeed) * h;

      if (i == 0) {
        fillPath.moveTo(x, h);
        fillPath.lineTo(x, y);
      } else {
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(w, h);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.blue.withOpacity(0.3),
          Colors.blue.withOpacity(0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // קו מהירות
    final linePath = Path();
    for (int i = 0; i < segments.length; i++) {
      final x = ((segments[i].timestamp.millisecondsSinceEpoch - startMs) / range) * w;
      final y = h - (segments[i].speedKmh / maxSpeed) * h;

      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter old) =>
      old.segments != segments || old.maxSpeed != maxSpeed;
}
