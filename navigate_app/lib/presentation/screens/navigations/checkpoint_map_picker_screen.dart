import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../widgets/map_with_selector.dart';

/// מסך בחירת נקודת ציון מתוך מפה
/// מחזיר את ה-ID של הנקודה שנבחרה (או null אם בוטל)
class CheckpointMapPickerScreen extends StatefulWidget {
  final List<Checkpoint> checkpoints;
  final Boundary? boundary;
  final Set<String> excludeIds;

  const CheckpointMapPickerScreen({
    super.key,
    required this.checkpoints,
    this.boundary,
    this.excludeIds = const {},
  });

  @override
  State<CheckpointMapPickerScreen> createState() =>
      _CheckpointMapPickerScreenState();
}

class _CheckpointMapPickerScreenState
    extends State<CheckpointMapPickerScreen> {
  final MapController _mapController = MapController();

  LatLngBounds? _computeBounds() {
    final points = <LatLng>[];

    // boundary points
    if (widget.boundary != null) {
      for (final c in widget.boundary!.coordinates) {
        points.add(c.toLatLng());
      }
    }

    // checkpoint points
    for (final cp in widget.checkpoints) {
      if (cp.coordinates != null) {
        points.add(cp.coordinates!.toLatLng());
      }
    }

    if (points.isEmpty) return null;
    return LatLngBounds.fromPoints(points);
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // Find nearest checkpoint within screen tolerance
    const maxDistanceDegrees = 0.001; // ~100m at mid latitudes
    Checkpoint? nearest;
    double nearestDist = double.infinity;

    for (final cp in widget.checkpoints) {
      if (cp.coordinates == null) continue;
      if (widget.excludeIds.contains(cp.id)) continue;

      final dx = cp.coordinates!.lat - point.latitude;
      final dy = cp.coordinates!.lng - point.longitude;
      final dist = dx * dx + dy * dy;

      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = cp;
      }
    }

    if (nearest != null && nearestDist < maxDistanceDegrees * maxDistanceDegrees) {
      Navigator.pop(context, nearest.id);
    }
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    for (final cp in widget.checkpoints) {
      if (cp.coordinates == null) continue;
      final isExcluded = widget.excludeIds.contains(cp.id);

      markers.add(Marker(
        point: cp.coordinates!.toLatLng(),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: isExcluded
              ? null
              : () => Navigator.pop(context, cp.id),
          child: Container(
            decoration: BoxDecoration(
              color: isExcluded ? Colors.grey : Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${cp.sequenceNumber}',
                style: TextStyle(
                  color: isExcluded ? Colors.grey[300] : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  List<Polygon> _buildBoundaryPolygon() {
    if (widget.boundary == null) return [];
    final points = widget.boundary!.coordinates
        .map((c) => c.toLatLng())
        .toList();
    if (points.isEmpty) return [];
    return [
      Polygon(
        points: points,
        color: Colors.black.withValues(alpha: 0.08),
        borderColor: Colors.black,
        borderStrokeWidth: 2,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _computeBounds();

    return Scaffold(
      appBar: AppBar(
        title: const Text('בחר נקודת ציון'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: bounds?.center ?? const LatLng(31.5, 34.8),
              initialZoom: 14,
              onTap: _onMapTap,
              onMapReady: () {
                if (bounds != null) {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(40),
                    ),
                  );
                }
              },
            ),
            layers: [
              PolygonLayer(polygons: _buildBoundaryPolygon()),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          // Instruction banner
          Positioned(
            top: 8,
            left: 60,
            right: 60,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Text(
                'לחץ על נקודה לבחירה',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
