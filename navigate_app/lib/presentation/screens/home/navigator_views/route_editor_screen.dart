import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/navigation_repository.dart';
import '../../../widgets/map_with_selector.dart';
import '../../../widgets/map_controls.dart';

/// מסך עריכת ציר על המפה — ציור polyline בין נקודות ציון
class RouteEditorScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final String navigatorUid;
  final List<Checkpoint> checkpoints;
  final ValueChanged<domain.Navigation> onNavigationUpdated;

  const RouteEditorScreen({
    super.key,
    required this.navigation,
    required this.navigatorUid,
    required this.checkpoints,
    required this.onNavigationUpdated,
  });

  @override
  State<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends State<RouteEditorScreen> {
  final MapController _mapController = MapController();
  final NavigationRepository _navigationRepo = NavigationRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();

  late List<LatLng> _waypoints;
  bool _isSaving = false;
  bool _wasApproved = false;
  bool _approvalWarningShown = false;
  Checkpoint? _startCheckpoint;
  Checkpoint? _endCheckpoint;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

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
    _loadStartEndCheckpoints();
  }

  Future<void> _loadStartEndCheckpoints() async {
    final route = widget.navigation.routes[widget.navigatorUid];
    if (route == null) return;

    if (route.startPointId != null) {
      _startCheckpoint = await _checkpointRepo.getById(route.startPointId!);
    }
    if (route.endPointId != null) {
      _endCheckpoint = await _checkpointRepo.getById(route.endPointId!);
    }

    // אם ציר חדש (ריק) ויש נקודת התחלה — מוסיף אותה אוטומטית
    if (_waypoints.isEmpty && _startCheckpoint != null) {
      _waypoints.add(_startCheckpoint!.coordinates.toLatLng());
    }

    if (mounted) setState(() {});
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

  /// ולידציה: התחלה/סיום + מעבר בכל נקודות הציון
  String? _validateRoute() {
    const threshold = 50.0; // מטרים

    // בדיקת התחלה
    if (_startCheckpoint != null && _waypoints.isNotEmpty) {
      final dist = GeometryUtils.distanceBetweenMeters(
        Coordinate(lat: _waypoints.first.latitude, lng: _waypoints.first.longitude, utm: ''),
        _startCheckpoint!.coordinates,
      );
      if (dist > threshold) {
        return 'הציר חייב להתחיל בנקודת ההתחלה. יש להזיז את תחילת הציר לנקודה המסומנת בירוק.';
      }
    }

    // בדיקת סיום
    if (_endCheckpoint != null && _waypoints.isNotEmpty) {
      final dist = GeometryUtils.distanceBetweenMeters(
        Coordinate(lat: _waypoints.last.latitude, lng: _waypoints.last.longitude, utm: ''),
        _endCheckpoint!.coordinates,
      );
      if (dist > threshold) {
        return 'הציר חייב להסתיים בנקודת הסיום. יש להזיז את סוף הציר לנקודה המסומנת באדום.';
      }
    }

    // בדיקת מעבר בכל נקודות הציון
    if (_waypoints.length >= 2) {
      for (final cp in widget.checkpoints) {
        bool passesNear = false;
        for (int i = 0; i < _waypoints.length - 1; i++) {
          final segA = Coordinate(lat: _waypoints[i].latitude, lng: _waypoints[i].longitude, utm: '');
          final segB = Coordinate(lat: _waypoints[i + 1].latitude, lng: _waypoints[i + 1].longitude, utm: '');
          final dist = GeometryUtils.distanceFromPointToSegmentMeters(
            cp.coordinates,
            segA,
            segB,
          );
          if (dist <= threshold) {
            passesNear = true;
            break;
          }
        }
        if (!passesNear) {
          return 'הציר לא עובר ליד נקודת ציון ${cp.name}. יש לוודא שהציר עובר ליד כל הנקודות.';
        }
      }
    }

    return null; // תקין
  }

  Future<void> _save() async {
    // ולידציה לפני שמירה
    final error = _validateRoute();
    if (error != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ציר לא תקין'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
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

  /// סרגל נתוני מדידה בזמן ציור — מקטע אחרון + אורך כולל
  Widget _buildRouteInfoBar() {
    final from = Coordinate(
      lat: _waypoints[_waypoints.length - 2].latitude,
      lng: _waypoints[_waypoints.length - 2].longitude,
      utm: '',
    );
    final to = Coordinate(
      lat: _waypoints.last.latitude,
      lng: _waypoints.last.longitude,
      utm: '',
    );
    final segmentDistance = GeometryUtils.distanceBetweenMeters(from, to);
    final segmentBearing = GeometryUtils.bearingBetween(from, to);

    final coords = _waypoints
        .map((p) => Coordinate(lat: p.latitude, lng: p.longitude, utm: ''))
        .toList();
    final totalKm = GeometryUtils.calculatePathLengthKm(coords);
    final totalMeters = (totalKm * 1000).round();

    return Container(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.straighten, size: 16, color: Colors.orange[700]),
          const SizedBox(width: 6),
          Text(
            'מקטע: ${segmentBearing.round()}° / ${segmentDistance.round()}מ\'',
            style: TextStyle(fontSize: 12, color: Colors.orange[800], fontWeight: FontWeight.w500),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(width: 12),
          Text(
            'כולל: ${totalMeters}מ\'',
            style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // חישוב bounds מנקודות הציון
    final cpPoints = widget.checkpoints
        .map((cp) => cp.coordinates.toLatLng())
        .toList();
    final allPoints = [...cpPoints, ..._waypoints];
    final hasBounds = allPoints.length > 1;
    final bounds = hasBounds ? LatLngBounds.fromPoints(allPoints) : null;
    final center = bounds?.center ?? (cpPoints.isNotEmpty ? cpPoints.first : const LatLng(31.5, 34.75));

    // markers לנקודות ציון קבועות (עיגול כחול עם מספר)
    final cpMarkers = <Marker>[];
    for (var i = 0; i < widget.checkpoints.length; i++) {
      final cp = widget.checkpoints[i];

      cpMarkers.add(Marker(
        point: cp.coordinates.toLatLng(),
        width: 36,
        height: 36,
        child: Tooltip(
          message: cp.name,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
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

    // markers לנקודות התחלה/סיום
    final startEndMarkers = <Marker>[];
    if (_startCheckpoint != null) {
      startEndMarkers.add(Marker(
        point: _startCheckpoint!.coordinates.toLatLng(),
        width: 40,
        height: 40,
        child: Tooltip(
          message: 'נקודת התחלה: ${_startCheckpoint!.name}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'H',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }
    if (_endCheckpoint != null) {
      startEndMarkers.add(Marker(
        point: _endCheckpoint!.coordinates.toLatLng(),
        width: 40,
        height: 40,
        child: Tooltip(
          message: 'נקודת סיום: ${_endCheckpoint!.name}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'S',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                // נתוני מדידה בזמן ציור
                if (_waypoints.length >= 2)
                  _buildRouteInfoBar(),
              ],
            ),
          ),
          // מפה
          Expanded(
            child: Stack(
              children: [
                MapWithTypeSelector(
                  mapController: _mapController,
                  showTypeSelector: false,
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
                        setState(() => _measurePoints.add(point));
                        return;
                      }
                      await _addWaypoint(point);
                    },
                  ),
                  layers: [
                    // polyline של הנתיב שצייר המנווט
                    if (_waypoints.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: _waypoints,
                          color: Colors.orange,
                          strokeWidth: 3.0,
                        ),
                      ]),
                    // קו בין נקודות ציון (רפרנס)
                    if (cpPoints.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: cpPoints,
                          color: Colors.blue.withValues(alpha: 0.3),
                          strokeWidth: 2.0,
                        ),
                      ]),
                    // נקודות ציון קבועות
                    MarkerLayer(markers: cpMarkers),
                    // נקודות התחלה/סיום
                    if (startEndMarkers.isNotEmpty)
                      MarkerLayer(markers: startEndMarkers),
                    // נקודות ציר של המנווט
                    MarkerLayer(markers: wpMarkers),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
