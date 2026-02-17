import 'package:flutter/material.dart';
import '../../services/route_analysis_service.dart';

/// גרף פרופיל גובה — מציג גובה לאורך המרחק
class ElevationProfileChart extends StatelessWidget {
  final List<ElevationSegment> segments;
  final double totalAscent;
  final double totalDescent;

  const ElevationProfileChart({
    super.key,
    required this.segments,
    this.totalAscent = 0,
    this.totalDescent = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('אין נתוני גובה', style: TextStyle(color: Colors.grey))),
      );
    }

    final minElev = segments.fold<double>(
      segments.first.elevationMeters,
      (min, s) => s.elevationMeters < min ? s.elevationMeters : min,
    );
    final maxElev = segments.fold<double>(
      segments.first.elevationMeters,
      (max, s) => s.elevationMeters > max ? s.elevationMeters : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת
        Row(
          children: [
            Icon(Icons.terrain, size: 18, color: Colors.brown[400]),
            const SizedBox(width: 6),
            const Text('פרופיל גובה',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const Spacer(),
            Text(
              'מינ\' ${minElev.round()}מ\' | מקס\' ${maxElev.round()}מ\'',
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
            painter: _ElevationChartPainter(
              segments: segments,
              minElevation: minElev,
              maxElevation: maxElev,
            ),
          ),
        ),

        // ציר מרחק
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('0 ק"מ',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text('${segments.last.distanceFromStartKm.toStringAsFixed(1)} ק"מ',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),

        // סה"כ עליות + ירידות
        if (totalAscent > 0 || totalDescent > 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.arrow_upward, size: 14, color: Colors.green[700]),
              const SizedBox(width: 2),
              Text('${totalAscent.round()}מ\'',
                  style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Icon(Icons.arrow_downward, size: 14, color: Colors.red[700]),
              const SizedBox(width: 2),
              Text('${totalDescent.round()}מ\'',
                  style: TextStyle(fontSize: 11, color: Colors.red[700], fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ],
    );
  }
}

class _ElevationChartPainter extends CustomPainter {
  final List<ElevationSegment> segments;
  final double minElevation;
  final double maxElevation;

  _ElevationChartPainter({
    required this.segments,
    required this.minElevation,
    required this.maxElevation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final elevRange = maxElevation - minElevation;
    final effectiveRange = elevRange > 0 ? elevRange * 1.15 : 100.0;
    final effectiveMin = minElevation - effectiveRange * 0.05;
    final maxDist = segments.last.distanceFromStartKm;
    if (maxDist <= 0) return;

    // קווי רשת אופקיים
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 4; i++) {
      final y = h * i / 5;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // מילוי מתחת לקו — gradient חום→ירוק
    final fillPath = Path();
    for (int i = 0; i < segments.length; i++) {
      final x = (segments[i].distanceFromStartKm / maxDist) * w;
      final y = h - ((segments[i].elevationMeters - effectiveMin) / effectiveRange) * h;

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
          Colors.green.withOpacity(0.3),
          Colors.brown.withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // קו גובה
    final linePath = Path();
    for (int i = 0; i < segments.length; i++) {
      final x = (segments[i].distanceFromStartKm / maxDist) * w;
      final y = h - ((segments[i].elevationMeters - effectiveMin) / effectiveRange) * h;

      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = Colors.brown[600]!
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ElevationChartPainter old) =>
      old.segments != segments || old.minElevation != minElevation || old.maxElevation != maxElevation;
}
