import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../data/repositories/nav_layer_repository.dart';
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/safety_point_repository.dart';
import '../../../../domain/entities/nav_layer.dart' as nav;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/safety_point.dart';
import '../../../../domain/entities/user.dart';
import '../../../../services/gps_service.dart';
import '../../../widgets/map_with_selector.dart';
import '../../../widgets/map_controls.dart';
import '../../../../core/map_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../data/sync/sync_manager.dart';

/// מסך מפה מלא — נפתח מ-drawer בזמן ניווט פעיל
class NavigatorMapScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final bool showSelfLocation;
  final bool showRoute;
  final bool openedFromEmergency;

  const NavigatorMapScreen({
    super.key,
    required this.navigation,
    required this.currentUser,
    this.showSelfLocation = false,
    this.showRoute = false,
    this.openedFromEmergency = false,
  });

  @override
  State<NavigatorMapScreen> createState() => _NavigatorMapScreenState();
}

class _NavigatorMapScreenState extends State<NavigatorMapScreen> {
  final MapController _mapController = MapController();
  final GpsService _gpsService = GpsService();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();

  LatLng? _currentPosition;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  List<SafetyPoint> _safetyPoints = [];
  List<nav.NavBoundary> _navBoundaries = [];
  StreamSubscription? _syncListener;
  List<Checkpoint> _checkpoints = [];

  bool _showGG = true;
  bool _showNB = false;
  bool _showRoutes = true;
  bool _showNZ = true;

  // מצב חירום — הצגת כל המנווטים
  bool _emergencyActive = false;
  int _emergencyMode = 0;
  List<Map<String, dynamic>> _emergencyNavigatorPositions = [];
  StreamSubscription<DocumentSnapshot>? _emergencyFlagSubscription;
  StreamSubscription<QuerySnapshot>? _emergencyTracksSubscription;

  double _ggOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _routesOpacity = 1.0;
  double _nzOpacity = 1.0;

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
    _startSyncListener();
    _startEmergencyFlagListener();
  }

  void _startSyncListener() {
    _syncListener = SyncManager().onDataChanged.listen((collection) {
      if (collection == AppConstants.navigationsCollection && mounted) {
        _reloadNavBoundaries();
      }
    });
  }

  Future<void> _reloadNavBoundaries() async {
    try {
      final navBoundaries = await _navLayerRepo.getBoundariesByNavigation(
        widget.navigation.id,
      );
      if (mounted) {
        setState(() => _navBoundaries = navBoundaries);
      }
    } catch (_) {}
  }

  /// טעינת שכבות מפה: ג"ג, נת"ב, נ"צ
  Future<void> _loadMapLayers() async {
    try {
      // סנכרון גבולות מ-Firestore לפני קריאה מקומית — מונע הצגת גבול לא עדכני
      await _navLayerRepo.syncBoundariesFromFirestore(widget.navigation.id);

      final safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);
      final navBoundaries = await _navLayerRepo.getBoundariesByNavigation(widget.navigation.id);

      // טעינת נקודות ציון — סינון לנקודות שמוקצות למנווט הנוכחי
      final allCheckpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      final route = widget.navigation.routes[widget.currentUser.uid];
      final assignedIds = <String>{};
      if (route != null) {
        assignedIds.addAll(route.checkpointIds);
        if (route.startPointId != null) assignedIds.add(route.startPointId!);
        if (route.endPointId != null) assignedIds.add(route.endPointId!);
        if (route.swapPointId != null) assignedIds.add(route.swapPointId!);
        assignedIds.addAll(route.waypointIds);
      }
      for (final wp in widget.navigation.waypointSettings.waypoints) {
        assignedIds.add(wp.checkpointId);
      }
      final checkpoints = assignedIds.isNotEmpty
          ? allCheckpoints.where((cp) => assignedIds.contains(cp.id)).toList()
          : allCheckpoints;

      if (mounted) {
        setState(() {
          _safetyPoints = safetyPoints;
          _navBoundaries = navBoundaries;
          _checkpoints = checkpoints;
        });
        // התמקד בגבול גזרה אם קיים
        if (navBoundaries.isNotEmpty && navBoundaries.first.allCoordinates.isNotEmpty) {
          final points = navBoundaries.first.allCoordinates.map((c) => LatLng(c.lat, c.lng)).toList();
          try {
            _mapController.fitCamera(CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(30),
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emergencyFlagSubscription?.cancel();
    _emergencyTracksSubscription?.cancel();
    _syncListener?.cancel();
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

  void _startEmergencyFlagListener() {
    _emergencyFlagSubscription = FirebaseFirestore.instance
        .collection('navigations')
        .doc(widget.navigation.id)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final active = snap.data()?['emergencyActive'] == true;
      final mode = snap.data()?['emergencyMode'] as int? ?? 0;

      if (active != _emergencyActive) {
        // חירום בוטל כשהמפה נפתחה מחירום → חזרה אחורה
        if (!active && _emergencyActive && widget.openedFromEmergency) {
          Navigator.of(context).pop();
          return;
        }

        setState(() {
          _emergencyActive = active;
          _emergencyMode = mode;
          if (active) _showNB = true;
        });

        if (active && mode >= 2) {
          _startEmergencyTracksListener();
        } else {
          _stopEmergencyTracksListener();
        }
      }
    });
  }

  void _startEmergencyTracksListener() {
    _emergencyTracksSubscription = FirebaseFirestore.instance
        .collection('navigation_tracks')
        .where('navigationId', isEqualTo: widget.navigation.id)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final positions = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final navigatorId = data['navigatorId'] as String? ?? '';
        if (navigatorId == widget.currentUser.uid) continue;
        try {
          final points = jsonDecode(data['trackPointsJson'] ?? '[]') as List;
          if (points.isNotEmpty) {
            final last = points.last as Map<String, dynamic>;
            final coord = last['coordinate'] as Map<String, dynamic>?;
            if (coord != null) {
              final lat = (coord['lat'] as num?)?.toDouble();
              final lng = (coord['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                positions.add({'navigatorId': navigatorId, 'lat': lat, 'lng': lng});
              }
            }
          }
        } catch (_) {}
      }
      setState(() => _emergencyNavigatorPositions = positions);
    });
  }

  void _stopEmergencyTracksListener() {
    _emergencyTracksSubscription?.cancel();
    _emergencyTracksSubscription = null;
    if (mounted) setState(() => _emergencyNavigatorPositions = []);
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

    // מצב חירום — הצגת מנווטים אחרים כנקודות כתומות
    if (_emergencyActive) {
      for (final pos in _emergencyNavigatorPositions) {
        markers.add(Marker(
          point: LatLng(pos['lat'] as double, pos['lng'] as double),
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.4),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.person, size: 18, color: Colors.white),
          ),
        ));
      }
    }

    return markers;
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];
    final route = widget.navigation.routes[widget.currentUser.uid];
    if (route == null || route.plannedPath.isEmpty) return polylines;

    polylines.add(Polyline(
      points: route.plannedPath.map((c) => LatLng(c.lat, c.lng)).toList(),
      strokeWidth: 2.5,
      color: Colors.purple.withValues(alpha: 0.7 * _routesOpacity),
    ));
    return polylines;
  }

  /// בניית מרקרים לנקודות ציון — התחלה/סיום/ביניים/רגילה
  List<Marker> _buildCheckpointMarkers() {
    final route = widget.navigation.routes[widget.currentUser.uid];

    final startIds = <String>{};
    final endIds = <String>{};
    final waypointIds = <String>{};

    final swapIds = <String>{};
    if (route != null) {
      if (route.startPointId != null) startIds.add(route.startPointId!);
      if (route.endPointId != null) endIds.add(route.endPointId!);
      if (route.swapPointId != null) swapIds.add(route.swapPointId!);
      waypointIds.addAll(route.waypointIds);
    }
    // swap point לא נחשב נקודת סיום
    endIds.removeAll(swapIds);
    for (final wp in widget.navigation.waypointSettings.waypoints) {
      waypointIds.add(wp.checkpointId);
    }

    return _checkpoints
        .where((cp) => !cp.isPolygon && cp.coordinates != null)
        .map((cp) {
      final isSwapPoint = swapIds.contains(cp.id);
      final isStart = startIds.contains(cp.id) || cp.isStart;
      final isEnd = endIds.contains(cp.id) || cp.isEnd;
      final isWaypoint = waypointIds.contains(cp.id);

      Color cpColor;
      String letter;
      if (isSwapPoint) {
        cpColor = Colors.white;
        letter = 'S';
      } else if (isStart) {
        cpColor = const Color(0xFF4CAF50);
        letter = 'H';
      } else if (isEnd) {
        cpColor = const Color(0xFFF44336);
        letter = 'F';
      } else if (isWaypoint) {
        cpColor = const Color(0xFFFFC107);
        letter = 'B';
      } else {
        cpColor = Colors.blue;
        letter = '';
      }

      final isSpecial = isStart || isEnd || isWaypoint || isSwapPoint;
      final markerSize = isSpecial ? 40.0 : 36.0;
      final label = isSpecial ? letter : '${cp.sequenceNumber}';

      return Marker(
        point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
        width: markerSize,
        height: markerSize,
        child: Tooltip(
          message: cp.name,
          child: Container(
            decoration: BoxDecoration(
              color: cpColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: cpColor.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSwapPoint ? Colors.black : Colors.white,
                  fontSize: isSpecial ? 18 : 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
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
        backgroundColor: _emergencyActive ? Colors.red : Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_emergencyActive)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  'מצב חירום',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
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
            initialMapType: MapConfig.resolveMapType(widget.navigation.displaySettings.defaultMap),
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
              if (_showGG && _navBoundaries.isNotEmpty)
                PolygonLayer(
                  polygons: _navBoundaries.expand((b) => b.allPolygons
                      .where((poly) => poly.isNotEmpty)
                      .map((poly) => Polygon(
                            points: poly.map((c) => LatLng(c.lat, c.lng)).toList(),
                            color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                            borderColor: Colors.black.withValues(alpha: _ggOpacity),
                            borderStrokeWidth: b.strokeWidth,
                            isFilled: true,
                          ))).toList(),
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
              // נקודות ציון
              if (_showNZ && _checkpoints.isNotEmpty)
                MarkerLayer(markers: _buildCheckpointMarkers()),
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
              MapLayerConfig(id: 'nz', label: 'נקודות ציון', color: Colors.blue, visible: _showNZ, onVisibilityChanged: (v) => setState(() => _showNZ = v), opacity: _nzOpacity, onOpacityChanged: (v) => setState(() => _nzOpacity = v)),
              MapLayerConfig(id: 'routes', label: 'מסלול', color: Colors.orange, visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v), opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v)),
            ],
          ),
        ],
      ),
    );
  }
}
