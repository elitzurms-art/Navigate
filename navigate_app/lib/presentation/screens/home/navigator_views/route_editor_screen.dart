import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../domain/entities/nav_layer.dart' as nav;
import '../../../../data/repositories/navigation_repository.dart';
import '../../../../data/repositories/nav_layer_repository.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../widgets/map_with_selector.dart';

/// מסך עריכת ציר על המפה — ציור polyline בין נקודות ציון
class RouteEditorScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final String navigatorUid;
  final List<Checkpoint> checkpoints;
  final ValueChanged<domain.Navigation> onNavigationUpdated;
  final Checkpoint? startCheckpoint;
  final Checkpoint? endCheckpoint;
  final List<Checkpoint> waypointCheckpoints;

  const RouteEditorScreen({
    super.key,
    required this.navigation,
    required this.navigatorUid,
    required this.checkpoints,
    required this.onNavigationUpdated,
    this.startCheckpoint,
    this.endCheckpoint,
    this.waypointCheckpoints = const [],
  });

  @override
  State<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends State<RouteEditorScreen> {
  final MapController _mapController = MapController();
  final NavigationRepository _navigationRepo = NavigationRepository();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();

  late List<LatLng> _waypoints;
  bool _isSaving = false;
  bool _wasApproved = false;
  bool _approvalWarningShown = false;

  // שכבות ניווט
  List<nav.NavBoundary> _boundaries = [];
  List<nav.NavSafetyPoint> _safetyPoints = [];
  bool _showBoundary = true;
  bool _showSafetyPoints = true;
  double _boundaryOpacity = 1.0;
  double _safetyPointsOpacity = 1.0;
  bool _layerControlsExpanded = false;

  // מדידה על המפה
  bool _measureMode = false;
  LatLng? _measurePointA;
  LatLng? _measurePointB;

  // נקודות התחלה/סיום/ביניים
  Checkpoint? _startCheckpoint;
  Checkpoint? _endCheckpoint;
  List<Checkpoint> _waypointCheckpoints = [];

  @override
  void initState() {
    super.initState();
    // טעינת נתיב קיים אם יש
    final route = widget.navigation.routes[widget.navigatorUid];
    _wasApproved = route?.approvalStatus != 'not_submitted';
    if (route != null && route.plannedPath.isNotEmpty) {
      _waypoints = route.plannedPath
          .map((c) => LatLng(c.lat, c.lng))
          .toList();
    } else {
      _waypoints = [];
    }
    _loadLayers();
    _resolveStartEndWaypoints();
  }

  /// טעינת שכבות ג"ג ונת"ב
  Future<void> _loadLayers() async {
    // טעינת גבולות גזרה
    try {
      final boundaries = await _navLayerRepo.getBoundariesByNavigation(widget.navigation.id);
      if (mounted) setState(() => _boundaries = boundaries);
    } catch (_) {}
    // טעינת נקודות בטיחות
    try {
      final safetyPoints = await _navLayerRepo.getSafetyPointsByNavigation(widget.navigation.id);
      if (mounted) setState(() => _safetyPoints = safetyPoints);
    } catch (_) {}
  }

  /// שימוש בנקודות התחלה/סיום/ביניים שהועברו מ-LearningView
  void _resolveStartEndWaypoints() {
    _startCheckpoint = widget.startCheckpoint;
    _endCheckpoint = widget.endCheckpoint;
    _waypointCheckpoints = widget.waypointCheckpoints;
  }

  Future<bool> _confirmEditAfterApproval() async {
    if (!_wasApproved || _approvalWarningShown) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('הציר כבר אושר'),
        content: const Text(
          'שינוי הציר יבטל את האישור הקיים.\nהאם להמשיך?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('המשך עריכה'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _approvalWarningShown = true;
      return true;
    }
    return false;
  }

  Future<void> _addWaypoint(LatLng point) async {
    if (!await _confirmEditAfterApproval()) return;
    setState(() {
      _waypoints.add(point);
    });
  }

  Future<void> _undoLastWaypoint() async {
    if (_waypoints.isEmpty) return;
    if (!await _confirmEditAfterApproval()) return;
    setState(() {
      _waypoints.removeLast();
    });
  }

  Future<void> _clearWaypoints() async {
    if (!await _confirmEditAfterApproval()) return;
    setState(() {
      _waypoints.clear();
    });
  }

  /// תרגום חומרה לעברית
  String _severityLabel(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return 'גבוהה';
      case 'medium':
        return 'בינונית';
      default:
        return severity;
    }
  }

  /// ולידציית ציר — בדיקת ג"ג ונת"ב
  /// מחזיר null אם תקין, או הודעת שגיאה אם לא
  String? _validateRoute() {
    if (_waypoints.length < 2) return null; // אין ציר לולידציה

    final coords = _waypoints
        .map((ll) => Coordinate(lat: ll.latitude, lng: ll.longitude, utm: ''))
        .toList();

    // 1. ציר בתוך ג"ג
    if (_boundaries.isNotEmpty) {
      final boundary = _boundaries.first;
      if (boundary.coordinates.isNotEmpty) {
        final poly = boundary.coordinates;

        // בדיקה שכל נקודת ציר בתוך הגבול
        for (final wp in coords) {
          if (!GeometryUtils.isPointInPolygon(wp, poly)) {
            return 'הציר חורג מגבול הגזרה. יש לערוך את הציר כך שישאר בתוך הג"ג.';
          }
        }

        // בדיקה שאף קטע לא חוצה צלעות הגבול
        for (int i = 0; i < coords.length - 1; i++) {
          if (GeometryUtils.doesSegmentCrossPolygonEdge(
              coords[i], coords[i + 1], poly)) {
            return 'הציר חורג מגבול הגזרה. יש לערוך את הציר כך שישאר בתוך הג"ג.';
          }
        }
      }
    }

    // 2. לא עובר דרך פוליגון נת"ב (medium/high)
    final dangerousPolygons = _safetyPoints.where((sp) =>
        sp.type == 'polygon' &&
        sp.polygonCoordinates != null &&
        sp.polygonCoordinates!.length >= 3 &&
        (sp.severity.toLowerCase() == 'medium' ||
            sp.severity.toLowerCase() == 'high'));

    for (final sp in dangerousPolygons) {
      final poly = sp.polygonCoordinates!;

      // בדיקה שאף waypoint לא בתוך הפוליגון
      for (final wp in coords) {
        if (GeometryUtils.isPointInPolygon(wp, poly)) {
          return 'הציר עובר דרך אזור נת"ב (${sp.name}) בחומרה ${_severityLabel(sp.severity)}. יש לעקוף אזור זה.';
        }
      }

      // בדיקה שאף segment לא חוצה צלעות הפוליגון
      for (int i = 0; i < coords.length - 1; i++) {
        if (GeometryUtils.doesSegmentCrossPolygonEdge(
            coords[i], coords[i + 1], poly)) {
          return 'הציר עובר דרך אזור נת"ב (${sp.name}) בחומרה ${_severityLabel(sp.severity)}. יש לעקוף אזור זה.';
        }
      }
    }

    // 3. לא עובר על נקודת נת"ב (medium/high)
    final dangerousPoints = _safetyPoints.where((sp) =>
        sp.type == 'point' &&
        sp.coordinates != null &&
        (sp.severity.toLowerCase() == 'medium' ||
            sp.severity.toLowerCase() == 'high'));

    for (final sp in dangerousPoints) {
      for (int i = 0; i < coords.length - 1; i++) {
        final dist = GeometryUtils.distanceFromPointToSegmentMeters(
            sp.coordinates!, coords[i], coords[i + 1]);
        if (dist <= 50) {
          return 'הציר עובר בקרבת נקודת נת"ב (${sp.name}) בחומרה ${_severityLabel(sp.severity)}. יש להתרחק מנקודה זו.';
        }
      }
    }

    return null; // תקין
  }

  Future<void> _save() async {
    // ולידציית ציר לפני שמירה
    final validationError = _validateRoute();
    if (validationError != null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('לא ניתן לשמור את הציר'),
          content: Text(validationError),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('הבנתי'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final plannedPath = _waypoints.map((ll) {
        return Coordinate(lat: ll.latitude, lng: ll.longitude, utm: '');
      }).toList();

      final route = widget.navigation.routes[widget.navigatorUid]!;
      final updatedRoute = route.copyWith(
        plannedPath: plannedPath,
        approvalStatus: _wasApproved && !_approvalWarningShown
            ? route.approvalStatus
            : 'not_submitted',
      );

      final updatedRoutes = Map<String, domain.AssignedRoute>.from(
        widget.navigation.routes,
      );
      updatedRoutes[widget.navigatorUid] = updatedRoute;

      final updatedNav = widget.navigation.copyWith(
        routes: updatedRoutes,
        updatedAt: DateTime.now(),
      );

      await _navigationRepo.update(updatedNav);
      widget.onNavigationUpdated(updatedNav);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הציר נשמר בהצלחה')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // חישוב bounds מנקודות הציון כולל התחלה/סיום
    final cpPoints = widget.checkpoints
        .map((cp) => cp.coordinates.toLatLng())
        .toList();
    final allPoints = [...cpPoints, ..._waypoints];
    if (_startCheckpoint != null) allPoints.add(_startCheckpoint!.coordinates.toLatLng());
    if (_endCheckpoint != null) allPoints.add(_endCheckpoint!.coordinates.toLatLng());
    final hasBounds = allPoints.length > 1;
    final bounds = hasBounds ? LatLngBounds.fromPoints(allPoints) : null;
    final center = bounds?.center ?? (cpPoints.isNotEmpty ? cpPoints.first : const LatLng(31.5, 34.75));

    // markers לנקודות ציון קבועות
    final cpMarkers = <Marker>[];
    for (var i = 0; i < widget.checkpoints.length; i++) {
      final cp = widget.checkpoints[i];
      final isFirst = i == 0;
      final isLast = i == widget.checkpoints.length - 1;

      cpMarkers.add(Marker(
        point: cp.coordinates.toLatLng(),
        width: 36,
        height: 36,
        child: Tooltip(
          message: cp.name,
          child: Container(
            decoration: BoxDecoration(
              color: isFirst
                  ? Colors.green
                  : isLast
                      ? Colors.red
                      : Colors.blue,
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
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // markers לנקודות ציר שצייר המנווט
    final wpMarkers = _waypoints.asMap().entries.map((entry) {
      return Marker(
        point: entry.value,
        width: 24,
        height: 24,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              '${entry.key + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('עריכת ציר'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
              tooltip: 'שמור',
            ),
        ],
      ),
      body: Column(
        children: [
          // toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[200],
            child: Row(
              children: [
                Icon(Icons.touch_app, size: 20, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _waypoints.isEmpty
                        ? 'לחץ על המפה לציור הציר'
                        : 'נקודות ציר: ${_waypoints.length}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
                if (_waypoints.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: _undoLastWaypoint,
                    tooltip: 'בטל נקודה אחרונה',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: _clearWaypoints,
                    tooltip: 'נקה הכל',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
          ),
          // מפה
          Expanded(
            child: Stack(
              children: [
                MapWithTypeSelector(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14.0,
                    initialCameraFit: hasBounds
                        ? CameraFit.bounds(
                            bounds: bounds!,
                            padding: const EdgeInsets.all(50),
                          )
                        : null,
                    onTap: (tapPosition, point) async {
                      if (_measureMode) {
                        _onMeasureTap(point);
                      } else {
                        await _addWaypoint(point);
                      }
                    },
                  ),
                  layers: [
                    // גבול גזרה (ג"ג)
                    if (_showBoundary && _boundaries.isNotEmpty)
                      PolygonLayer(
                        polygons: _boundaries
                            .where((b) => b.coordinates.isNotEmpty)
                            .map((b) => Polygon(
                                  points: b.coordinates
                                      .map((coord) => LatLng(coord.lat, coord.lng))
                                      .toList(),
                                  color: Colors.black.withOpacity(0.1 * _boundaryOpacity),
                                  borderColor: Colors.black.withOpacity(_boundaryOpacity),
                                  borderStrokeWidth: b.strokeWidth,
                                  isFilled: true,
                                ))
                            .toList(),
                      ),
                    // נקודות בטיחות (נת"ב) — פוליגונים
                    if (_showSafetyPoints)
                      PolygonLayer(
                        polygons: _safetyPoints
                            .where((sp) =>
                                sp.type == 'polygon' &&
                                sp.polygonCoordinates != null &&
                                sp.polygonCoordinates!.isNotEmpty)
                            .map((sp) => Polygon(
                                  points: sp.polygonCoordinates!
                                      .map((coord) => LatLng(coord.lat, coord.lng))
                                      .toList(),
                                  color: _severityColor(sp.severity)
                                      .withOpacity(0.2 * _safetyPointsOpacity),
                                  borderColor: _severityColor(sp.severity)
                                      .withOpacity(_safetyPointsOpacity),
                                  borderStrokeWidth: 2.0,
                                  isFilled: true,
                                ))
                            .toList(),
                      ),
                    // polyline של הנתיב שצייר המנווט
                    if (_waypoints.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: _waypoints,
                          color: Colors.orange,
                          strokeWidth: 3.0,
                        ),
                      ]),
                    // קו בין נקודות ציון כולל התחלה/סיום (רפרנס)
                    if (cpPoints.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: [
                            if (_startCheckpoint != null) _startCheckpoint!.coordinates.toLatLng(),
                            ...cpPoints,
                            if (_endCheckpoint != null) _endCheckpoint!.coordinates.toLatLng(),
                          ],
                          color: Colors.blue.withOpacity(0.3),
                          strokeWidth: 2.0,
                        ),
                      ]),
                    // נקודות בטיחות (נת"ב) — נקודות (markers)
                    if (_showSafetyPoints)
                      MarkerLayer(
                        markers: _safetyPoints
                            .where((sp) => sp.type == 'point' && sp.coordinates != null)
                            .map((sp) => Marker(
                                  point: LatLng(sp.coordinates!.lat, sp.coordinates!.lng),
                                  width: 36,
                                  height: 36,
                                  child: Opacity(
                                    opacity: _safetyPointsOpacity,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _severityColor(sp.severity),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.warning, color: Colors.white, size: 18),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    // נקודת התחלה
                    if (_startCheckpoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _startCheckpoint!.coordinates.toLatLng(),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Center(
                                child: Text('H',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    // נקודת סיום
                    if (_endCheckpoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _endCheckpoint!.coordinates.toLatLng(),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Center(
                                child: Text('S',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    // נקודות ביניים (waypoints)
                    if (_waypointCheckpoints.isNotEmpty)
                      MarkerLayer(
                        markers: _waypointCheckpoints.map((wp) {
                          return Marker(
                            point: wp.coordinates.toLatLng(),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.purple,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Center(
                                child: Text('B',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    // נקודות ציון קבועות
                    MarkerLayer(markers: cpMarkers),
                    // נקודות ציר של המנווט
                    MarkerLayer(markers: wpMarkers),
                    // קו מדידה
                    if (_measurePointA != null && _measurePointB != null)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: [_measurePointA!, _measurePointB!],
                          color: Colors.yellow,
                          strokeWidth: 2.0,
                        ),
                      ]),
                    // סמני מדידה
                    if (_measurePointA != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _measurePointA!,
                          width: 12, height: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.yellow,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 1.5),
                            ),
                          ),
                        ),
                        if (_measurePointB != null)
                          Marker(
                            point: _measurePointB!,
                            width: 12, height: 12,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.yellow,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 1.5),
                              ),
                            ),
                          ),
                      ]),
                  ],
                ),
                // חץ צפון
                Positioned(top: 8, left: 8, child: _buildNorthArrow()),
                // פקדי שכבות
                Positioned(
                  top: 8,
                  left: 56,
                  child: _buildLayerControls(),
                ),
                // כפתור מדידה
                Positioned(top: 8, right: 8, child: _buildMeasureButton()),
                // תוצאת מדידה
                if (_measurePointA != null && _measurePointB != null)
                  Positioned(
                    bottom: 8, left: 8, right: 8,
                    child: _buildMeasurementResult(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===================== שכבות — helper methods =====================

  /// קבלת צבע לפי חומרת נקודת בטיחות
  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.yellow[700]!;
      default:
        return Colors.orange;
    }
  }

  /// חץ צפון
  Widget _buildNorthArrow() {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('N', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red[700])),
              Icon(Icons.navigation, size: 18, color: Colors.red[700]),
            ],
          ),
        ),
      ),
    );
  }

  /// כפתור מצב מדידה
  Widget _buildMeasureButton() {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: _measureMode ? Colors.yellow[100] : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _measureMode = !_measureMode;
              if (!_measureMode) {
                _measurePointA = null;
                _measurePointB = null;
              }
            });
          },
          child: Icon(
            Icons.straighten,
            size: 20,
            color: _measureMode ? Colors.orange[800] : Colors.black87,
          ),
        ),
      ),
    );
  }

  /// טיפול בלחיצה על המפה במצב מדידה
  void _onMeasureTap(LatLng point) {
    setState(() {
      if (_measurePointA == null || _measurePointB != null) {
        _measurePointA = point;
        _measurePointB = null;
      } else {
        _measurePointB = point;
      }
    });
  }

  /// תצוגת תוצאת מדידה
  Widget _buildMeasurementResult() {
    if (_measurePointA == null || _measurePointB == null) return const SizedBox.shrink();

    final from = Coordinate(lat: _measurePointA!.latitude, lng: _measurePointA!.longitude, utm: '');
    final to = Coordinate(lat: _measurePointB!.latitude, lng: _measurePointB!.longitude, utm: '');
    final distanceM = GeometryUtils.distanceBetweenMeters(from, to);
    final bearing = GeometryUtils.bearingBetween(from, to);

    final String distanceStr;
    if (distanceM >= 1000) {
      distanceStr = '${(distanceM / 1000).toStringAsFixed(2)} ק"מ';
    } else {
      distanceStr = '${distanceM.toStringAsFixed(0)} מ\'';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.straighten, size: 16, color: Colors.yellow),
          const SizedBox(width: 6),
          Text(distanceStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 12),
          const Icon(Icons.explore, size: 16, color: Colors.yellow),
          const SizedBox(width: 6),
          Text('${bearing.toStringAsFixed(1)}°', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() { _measurePointA = null; _measurePointB = null; }),
            child: const Icon(Icons.close, size: 16, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerControls() {
    return Card(
      elevation: 4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _layerControlsExpanded ? 220 : 48,
        child: _layerControlsExpanded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // כותרת + כפתור סגירה
                  InkWell(
                    onTap: () => setState(() => _layerControlsExpanded = false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('שכבות', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Icon(Icons.close, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  // ג"ג — גבול גזרה
                  _buildLayerRow(
                    label: 'ג"ג',
                    color: Colors.black,
                    enabled: _showBoundary,
                    opacity: _boundaryOpacity,
                    onToggle: (val) => setState(() => _showBoundary = val),
                    onOpacity: (val) => setState(() => _boundaryOpacity = val),
                  ),
                  // נת"ב — נקודות בטיחות
                  _buildLayerRow(
                    label: 'נת"ב',
                    color: Colors.orange,
                    enabled: _showSafetyPoints,
                    opacity: _safetyPointsOpacity,
                    onToggle: (val) => setState(() => _showSafetyPoints = val),
                    onOpacity: (val) => setState(() => _safetyPointsOpacity = val),
                  ),
                  const SizedBox(height: 4),
                ],
              )
            : InkWell(
                onTap: () => setState(() => _layerControlsExpanded = true),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.layers, size: 24),
                ),
              ),
      ),
    );
  }

  Widget _buildLayerRow({
    required String label,
    required Color color,
    required bool enabled,
    required double opacity,
    required ValueChanged<bool> onToggle,
    required ValueChanged<double> onOpacity,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.6),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Switch(
                  value: enabled,
                  onChanged: onToggle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (enabled)
            SizedBox(
              height: 24,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: opacity,
                  min: 0.1,
                  max: 1.0,
                  onChanged: onOpacity,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
