import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../domain/entities/nav_layer.dart';
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/safety_point.dart';
import '../../../widgets/map_with_selector.dart';

class StarLearningMapWidget extends StatefulWidget {
  final Checkpoint? centralPoint;
  final Checkpoint? targetPoint;
  final List<NavBoundary> boundaries;
  final List<SafetyPoint> safetyPoints;
  final LatLng? fallbackCenter;
  final int completedPoints;
  final int totalPoints;
  final String pointLabel;
  final String timerText;
  final VoidCallback onFinishLearning;

  const StarLearningMapWidget({
    super.key,
    this.centralPoint,
    this.targetPoint,
    required this.boundaries,
    required this.safetyPoints,
    this.fallbackCenter,
    required this.completedPoints,
    required this.totalPoints,
    required this.pointLabel,
    required this.timerText,
    required this.onFinishLearning,
  });

  @override
  State<StarLearningMapWidget> createState() => _StarLearningMapWidgetState();
}

class _StarLearningMapWidgetState extends State<StarLearningMapWidget> {
  MapOptions? _cachedMapOptions;

  late List<SafetyPoint> _pointSafety;
  late List<SafetyPoint> _polygonSafety;

  @override
  void initState() {
    super.initState();
    _filterSafetyPoints();
  }

  @override
  void didUpdateWidget(StarLearningMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.safetyPoints != widget.safetyPoints) {
      _filterSafetyPoints();
    }
    if (oldWidget.targetPoint != widget.targetPoint ||
        oldWidget.centralPoint != widget.centralPoint) {
      _cachedMapOptions = null;
    }
  }

  void _filterSafetyPoints() {
    _pointSafety = widget.safetyPoints.where((sp) => sp.type == 'point' && sp.coordinates != null).toList();
    _polygonSafety = widget.safetyPoints.where((sp) => sp.type == 'polygon' && sp.polygonCoordinates != null).toList();
  }

  MapOptions _getMapOptions() {
    if (_cachedMapOptions != null) return _cachedMapOptions!;
    final boundsPoints = <LatLng>[
      if (widget.centralPoint?.coordinates != null)
        LatLng(widget.centralPoint!.coordinates!.lat, widget.centralPoint!.coordinates!.lng),
      if (widget.targetPoint?.coordinates != null)
        LatLng(widget.targetPoint!.coordinates!.lat, widget.targetPoint!.coordinates!.lng),
    ];
    _cachedMapOptions = boundsPoints.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(boundsPoints),
              padding: const EdgeInsets.all(40),
            ),
          )
        : MapOptions(
            initialCenter: boundsPoints.isNotEmpty
                ? boundsPoints.first
                : (widget.fallbackCenter ?? const LatLng(31.5, 34.8)),
            initialZoom: 15,
          );
    return _cachedMapOptions!;
  }

  @override
  Widget build(BuildContext context) {
    final central = widget.centralPoint;
    final target = widget.targetPoint;

    return Stack(
      children: [
        RepaintBoundary(
          child: MapWithTypeSelector(
            options: _getMapOptions(),
            showTypeSelector: false,
            layers: [
              // Boundary polygons
              PolygonLayer(polygons: widget.boundaries.expand((b) => b.allPolygons.map((poly) => Polygon(
                points: poly.map((c) => LatLng(c.lat, c.lng)).toList(),
                color: Colors.black.withOpacity(0.1),
                borderColor: Colors.black.withOpacity(0.7),
                borderStrokeWidth: b.strokeWidth,
              ))).toList()),
              // Safety point markers
              MarkerLayer(markers: _pointSafety.map((sp) => Marker(
                point: LatLng(sp.coordinates!.lat, sp.coordinates!.lng),
                width: 30, height: 30,
                child: Icon(Icons.warning, color: Colors.red.withOpacity(0.8), size: 30),
              )).toList()),
              // Safety point polygons
              PolygonLayer(polygons: _polygonSafety.map((sp) => Polygon(
                points: sp.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                color: Colors.red.withOpacity(0.2),
                borderColor: Colors.red.withOpacity(0.7),
                borderStrokeWidth: 2,
              )).toList()),
              // Central point (green flag + label)
              if (central?.coordinates != null)
                MarkerLayer(markers: [Marker(
                  point: LatLng(central!.coordinates!.lat, central.coordinates!.lng),
                  width: 80, height: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flag, color: Colors.green, size: 36),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          central.name.isNotEmpty ? central.name : 'מרכז',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )]),
              // Target point (blue pin + label)
              if (target?.coordinates != null)
                MarkerLayer(markers: [Marker(
                  point: LatLng(target!.coordinates!.lat, target.coordinates!.lng),
                  width: 80, height: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, color: Colors.blue, size: 36),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          target.name.isNotEmpty ? target.name : 'יעד',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )]),
            ],
          ),
        ),

        // Top overlay — progress + point name
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            color: Colors.white.withOpacity(0.9),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: widget.totalPoints > 0 ? widget.completedPoints / widget.totalPoints : 0,
                  backgroundColor: Colors.grey[200],
                  color: Colors.green,
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                Text(widget.pointLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),

        // Bottom overlay — timer + button
        Positioned(
          bottom: 16, left: 0, right: 0,
          child: Container(
            color: Colors.white.withOpacity(0.9),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.timerText,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onFinishLearning,
                    icon: const Icon(Icons.check),
                    label: const Text('סיימתי ללמוד', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
