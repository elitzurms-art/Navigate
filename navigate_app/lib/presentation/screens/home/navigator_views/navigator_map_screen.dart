import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../data/repositories/boundary_repository.dart';
import '../../../../data/repositories/cluster_repository.dart';
import '../../../../data/repositories/safety_point_repository.dart';
import '../../../../domain/entities/boundary.dart';
import '../../../../domain/entities/cluster.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/safety_point.dart';
import '../../../../services/gps_service.dart';
import '../../../widgets/map_with_selector.dart';
import '../../../widgets/map_controls.dart';

/// מסך מפה מלא — נפתח מ-drawer בזמן ניווט פעיל
class NavigatorMapScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool showSelfLocation;
  final bool showRoute;

  const NavigatorMapScreen({
    super.key,
    required this.navigation,
    this.showSelfLocation = false,
    this.showRoute = false,
  });

  @override
  State<NavigatorMapScreen> createState() => _NavigatorMapScreenState();
}

class _NavigatorMapScreenState extends State<NavigatorMapScreen> {
  final MapController _mapController = MapController();
  final GpsService _gpsService = GpsService();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();

  LatLng? _currentPosition;
  StreamSubscription? _positionSubscription;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];

  bool _showGG = true;
  bool _showNB = false;
  bool _showBA = false;
  bool _showRoutes = true;

  double _ggOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _baOpacity = 1.0;
  double _routesOpacity = 1.0;

  // ברירת מחדל — מרכז ישראל
  static const _defaultCenter = LatLng(31.5, 34.8);
  static const _defaultZoom = 13.0;

  @override
  void initState() {
    super.initState();
    if (widget.showSelfLocation) {
      _startLocationTracking();
    }
    _loadMapLayers();
  }

  /// טעינת שכבות מפה: ג"ג, נת"ב, א"ב
  Future<void> _loadMapLayers() async {
    try {
      final safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);
      final boundaries = await _boundaryRepo.getByArea(widget.navigation.areaId);
      final clusters = await _clusterRepo.getByArea(widget.navigation.areaId);
      if (mounted) {
        setState(() {
          _safetyPoints = safetyPoints;
          _boundaries = boundaries;
          _clusters = clusters;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _startLocationTracking() {
    // TODO: use GpsService stream for live position updates
    // For now, get single position
    _gpsService.getCurrentPosition().then((latLng) {
      if (mounted && latLng != null) {
        setState(() {
          _currentPosition = latLng;
        });
        _mapController.move(_currentPosition!, _defaultZoom);
      }
    }).catchError((_) {});
  }

  LatLng _initialCenter() {
    final ds = widget.navigation.displaySettings;
    if (ds.openingLat != null && ds.openingLng != null) {
      return LatLng(ds.openingLat!, ds.openingLng!);
    }
    return _currentPosition ?? _defaultCenter;
  }

  // ===========================================================================
  // Map layers
  // ===========================================================================

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // מיקום עצמי
    if (widget.showSelfLocation && _currentPosition != null) {
      markers.add(Marker(
        point: _currentPosition!,
        width: 30,
        height: 30,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.my_location, size: 16, color: Colors.white),
        ),
      ));
    }

    return markers;
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];

    // TODO: build route polyline from assigned route checkpoints when showRoute is true
    // This requires loading checkpoint coordinates from NavCheckpoints table

    return polylines;
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.navigation.name),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (widget.showSelfLocation)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController.move(_currentPosition!, _defaultZoom);
                }
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            showTypeSelector: false,
            options: MapOptions(
              initialCenter: _initialCenter(),
              initialZoom: _defaultZoom,
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                  return;
                }
              },
            ),
            layers: [
              // ג"ג
              if (_showGG && _boundaries.isNotEmpty)
                PolygonLayer(
                  polygons: _boundaries.map((b) => Polygon(
                    points: b.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                    color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                    borderColor: Colors.black.withValues(alpha: _ggOpacity),
                    borderStrokeWidth: b.strokeWidth,
                    isFilled: true,
                  )).toList(),
                ),
              // נת"ב - נקודות
              if (_showNB && _safetyPoints.where((p) => p.type == 'point').isNotEmpty)
                MarkerLayer(
                  markers: _safetyPoints
                      .where((p) => p.type == 'point' && p.coordinates != null)
                      .map((point) => Marker(
                            point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                            width: 30, height: 30,
                            child: Opacity(opacity: _nbOpacity, child: const Icon(Icons.warning, color: Colors.red, size: 30)),
                          ))
                      .toList(),
                ),
              // נת"ב - פוליגונים
              if (_showNB && _safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
                PolygonLayer(
                  polygons: _safetyPoints
                      .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                      .map((point) => Polygon(
                            points: point.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                            color: Colors.red.withValues(alpha: 0.2 * _nbOpacity),
                            borderColor: Colors.red.withValues(alpha: _nbOpacity), borderStrokeWidth: 2, isFilled: true,
                          ))
                      .toList(),
                ),
              // א"ב
              if (_showBA && _clusters.isNotEmpty)
                PolygonLayer(
                  polygons: _clusters.map((cluster) => Polygon(
                    points: cluster.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                    color: Colors.green.withValues(alpha: cluster.fillOpacity * _baOpacity),
                    borderColor: Colors.green.withValues(alpha: _baOpacity),
                    borderStrokeWidth: cluster.strokeWidth,
                    isFilled: true,
                  )).toList(),
                ),
              // מסלול
              if (_showRoutes)
                PolylineLayer(polylines: _buildPolylines()),
              // מיקום עצמי — תמיד מוצג
              MarkerLayer(markers: _buildMarkers()),
              ...MapControls.buildMeasureLayers(_measurePoints),
            ],
          ),
          MapControls(
            mapController: _mapController,
            measureMode: _measureMode,
            onMeasureModeChanged: (v) => setState(() {
              _measureMode = v;
              if (!v) _measurePoints.clear();
            }),
            measurePoints: _measurePoints,
            onMeasureClear: () => setState(() => _measurePoints.clear()),
            onMeasureUndo: () => setState(() {
              if (_measurePoints.isNotEmpty) _measurePoints.removeLast();
            }),
            layers: [
              MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, onVisibilityChanged: (v) => setState(() => _showGG = v), opacity: _ggOpacity, onOpacityChanged: (v) => setState(() => _ggOpacity = v)),
              MapLayerConfig(id: 'nb', label: 'נקודות בטיחות', color: Colors.red, visible: _showNB, onVisibilityChanged: (v) => setState(() => _showNB = v), opacity: _nbOpacity, onOpacityChanged: (v) => setState(() => _nbOpacity = v)),
              MapLayerConfig(id: 'ba', label: 'ביצי אזור', color: Colors.green, visible: _showBA, onVisibilityChanged: (v) => setState(() => _showBA = v), opacity: _baOpacity, onOpacityChanged: (v) => setState(() => _baOpacity = v)),
              MapLayerConfig(id: 'routes', label: 'מסלול', color: Colors.orange, visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v), opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v)),
            ],
          ),
        ],
      ),
    );
  }
}
