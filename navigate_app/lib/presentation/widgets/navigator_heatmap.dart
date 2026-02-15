import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/gps_tracking_service.dart';

/// שכבת מפת חום למנווטים — מציגה צפיפות נקודות GPS
class NavigatorHeatmapLayer extends StatelessWidget {
  final Map<String, List<TrackPoint>> navigatorTracks;
  final double radius;
  final double opacity;

  const NavigatorHeatmapLayer({
    super.key,
    required this.navigatorTracks,
    this.radius = 20.0,
    this.opacity = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    // אוסף את כל הנקודות לרשת
    final allPoints = <LatLng>[];
    for (final tracks in navigatorTracks.values) {
      for (final tp in tracks) {
        allPoints.add(LatLng(tp.coordinate.lat, tp.coordinate.lng));
      }
    }

    if (allPoints.isEmpty) return const SizedBox.shrink();

    // חישוב רשת חום
    final cells = _computeHeatCells(allPoints);
    if (cells.isEmpty) return const SizedBox.shrink();

    return CircleLayer(
      circles: cells.map((cell) {
        return CircleMarker(
          point: cell.center,
          radius: radius,
          color: _heatColor(cell.intensity).withOpacity(opacity * cell.intensity),
          borderColor: Colors.transparent,
          borderStrokeWidth: 0,
        );
      }).toList(),
    );
  }

  List<_HeatCell> _computeHeatCells(List<LatLng> points) {
    if (points.isEmpty) return [];

    // מצא גבולות
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // חלוקה לתאים (~50 מטר כל תא)
    const cellSize = 0.0005; // ~50m
    final cols = ((maxLng - minLng) / cellSize).ceil().clamp(1, 100);
    final rows = ((maxLat - minLat) / cellSize).ceil().clamp(1, 100);

    final grid = List.generate(rows, (_) => List.filled(cols, 0));

    for (final p in points) {
      final row = ((p.latitude - minLat) / cellSize).floor().clamp(0, rows - 1);
      final col = ((p.longitude - minLng) / cellSize).floor().clamp(0, cols - 1);
      grid[row][col]++;
    }

    // מצא מקסימום
    int maxCount = 0;
    for (final row in grid) {
      for (final count in row) {
        if (count > maxCount) maxCount = count;
      }
    }
    if (maxCount == 0) return [];

    // יצירת תאי חום (רק תאים עם נקודות)
    final cells = <_HeatCell>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] > 0) {
          final lat = minLat + (r + 0.5) * cellSize;
          final lng = minLng + (c + 0.5) * cellSize;
          cells.add(_HeatCell(
            center: LatLng(lat, lng),
            intensity: grid[r][c] / maxCount,
          ));
        }
      }
    }

    return cells;
  }

  Color _heatColor(double intensity) {
    if (intensity < 0.25) return Colors.blue;
    if (intensity < 0.5) return Colors.green;
    if (intensity < 0.75) return Colors.yellow;
    return Colors.red;
  }
}

class _HeatCell {
  final LatLng center;
  final double intensity; // 0.0 - 1.0

  _HeatCell({required this.center, required this.intensity});
}

/// ווידג'ט מפת חום עם מקרא
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('מפת חום',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(Colors.blue, 'נמוך'),
              const SizedBox(width: 8),
              _dot(Colors.green, 'בינוני'),
              const SizedBox(width: 8),
              _dot(Colors.yellow, 'גבוה'),
              const SizedBox(width: 8),
              _dot(Colors.red, 'צפוף'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
