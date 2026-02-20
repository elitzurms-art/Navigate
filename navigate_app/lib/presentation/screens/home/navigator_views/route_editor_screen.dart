import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../data/repositories/boundary_repository.dart';
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/cluster_repository.dart';
import '../../../../data/repositories/navigation_repository.dart';
import '../../../../data/repositories/safety_point_repository.dart';
import '../../../../domain/entities/safety_point.dart';
import '../../../../domain/entities/boundary.dart';
import '../../../../domain/entities/cluster.dart';
import '../../../widgets/map_with_selector.dart';
import '../../../widgets/map_controls.dart';
import '../../../../core/map_config.dart';
import '../../../../services/elevation_service.dart';

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
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final ClusterRepository _clusterRepo = ClusterRepository();

  late List<LatLng> _waypoints;
  bool _isSaving = false;
  bool _wasApproved = false;
  bool _approvalWarningShown = false;
  Checkpoint? _startCheckpoint;
  Checkpoint? _endCheckpoint;

  final ElevationService _elevationService = ElevationService();
  int _routeAscent = 0;
  int _routeDescent = 0;
  final Map<int, int?> _waypointElevations = {};

  int? _selectedWaypointIndex; // נקודה נבחרת להזזה

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];
  List<Cluster> _clusters = [];
  Boundary? _navigationBoundary;

  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = true;
  bool _showBA = false;
  bool _showRoutes = true;

  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _baOpacity = 1.0;
  double _routesOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    // טעינת נתיב קיים אם יש
    final route = widget.navigation.routes[widget.navigatorUid];
    _wasApproved = route?.approvalStatus == 'approved' || route?.approvalStatus == 'pending_approval';
    if (route != null && route.plannedPath.isNotEmpty) {
      _waypoints = route.plannedPath
          .map((c) => LatLng(c.lat, c.lng))
          .toList();
    } else {
      _waypoints = [];
    }
    _loadStartEndCheckpoints();
    _loadMapLayers();
    if (_waypoints.length >= 2) _computeRouteElevation();
  }

  /// טעינת שכבות מפה: ג"ג, נת"ב, א"ב
  Future<void> _loadMapLayers() async {
    try {
      final safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);
      final boundaries = await _boundaryRepo.getByArea(widget.navigation.areaId);
      final clusters = await _clusterRepo.getByArea(widget.navigation.areaId);

      // טעינת הג"ג הספציפי של הניווט
      Boundary? navBoundary;
      final boundaryId = widget.navigation.boundaryLayerId;
      if (boundaryId != null && boundaryId.isNotEmpty) {
        navBoundary = await _boundaryRepo.getById(boundaryId);
      }

      if (mounted) {
        setState(() {
          _safetyPoints = safetyPoints;
          _boundaries = boundaries;
          _clusters = clusters;
          _navigationBoundary = navBoundary;
        });
      }
    } catch (_) {}
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
    if (_waypoints.isEmpty && _startCheckpoint != null && _startCheckpoint!.coordinates != null) {
      _waypoints.add(_startCheckpoint!.coordinates!.toLatLng());
    }

    if (mounted) setState(() {});
  }

  /// חישוב עליות/ירידות מצטברות מנקודות הציר
  void _computeRouteElevation() {
    if (_waypoints.length < 2) {
      setState(() { _routeAscent = 0; _routeDescent = 0; _waypointElevations.clear(); });
      return;
    }
    Future.wait(
      _waypoints.map((p) => _elevationService.getElevation(p.latitude, p.longitude)),
    ).then((elevations) {
      if (!mounted) return;
      int ascent = 0, descent = 0;
      int? prev;
      for (int i = 0; i < elevations.length; i++) {
        final e = elevations[i];
        _waypointElevations[i] = e;
        if (e == null) { prev = null; continue; }
        if (prev != null) {
          final diff = e - prev;
          if (diff > 0) ascent += diff;
          else descent += -diff;
        }
        prev = e;
      }
      setState(() { _routeAscent = ascent; _routeDescent = descent; });
    }).catchError((_) {});
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
      if (_selectedWaypointIndex != null) {
        // מצב הזזה — מזיז את הנקודה הנבחרת למיקום החדש
        _waypoints[_selectedWaypointIndex!] = point;
        _selectedWaypointIndex = null;
      } else {
        _waypoints.add(point);
      }
    });
    _computeRouteElevation();
  }

  Future<void> _undoLastWaypoint() async {
    if (_waypoints.isEmpty) return;
    if (!await _confirmEditAfterApproval()) return;
    setState(() {
      _selectedWaypointIndex = null;
      _waypoints.removeLast();
    });
    _computeRouteElevation();
  }

  Future<void> _clearWaypoints() async {
    if (!await _confirmEditAfterApproval()) return;
    setState(() {
      _selectedWaypointIndex = null;
      _waypoints.clear();
      _routeAscent = 0;
      _routeDescent = 0;
    });
  }

  /// מחיקת נקודת ציר לפי אינדקס
  Future<void> _deleteWaypoint(int index) async {
    if (!await _confirmEditAfterApproval()) return;
    setState(() {
      _waypoints.removeAt(index);
      _selectedWaypointIndex = null;
    });
    _computeRouteElevation();
  }

  /// הוספת נקודה באמצע — בין waypoint[index] ל-waypoint[index+1]
  Future<void> _insertMidpoint(int afterIndex) async {
    if (!await _confirmEditAfterApproval()) return;
    final a = _waypoints[afterIndex];
    final b = _waypoints[afterIndex + 1];
    final mid = LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
    setState(() {
      _waypoints.insert(afterIndex + 1, mid);
      _selectedWaypointIndex = afterIndex + 1; // בוחר את הנקודה החדשה להזזה
    });
    _computeRouteElevation();
  }

  /// ולידציה: התחלה/סיום + מעבר בכל נקודות הציון
  String? _validateRoute() {
    const threshold = 50.0; // מטרים

    // בדיקת התחלה
    if (_startCheckpoint != null && _waypoints.isNotEmpty) {
      final dist = GeometryUtils.distanceBetweenMeters(
        Coordinate(lat: _waypoints.first.latitude, lng: _waypoints.first.longitude, utm: ''),
        _startCheckpoint!.coordinates!,
      );
      if (dist > threshold) {
        return 'הציר חייב להתחיל בנקודת ההתחלה. יש להזיז את תחילת הציר לנקודה המסומנת בירוק.';
      }
    }

    // בדיקת סיום
    if (_endCheckpoint != null && _waypoints.isNotEmpty) {
      final dist = GeometryUtils.distanceBetweenMeters(
        Coordinate(lat: _waypoints.last.latitude, lng: _waypoints.last.longitude, utm: ''),
        _endCheckpoint!.coordinates!,
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
          if (cp.isPolygon || cp.coordinates == null) continue;
          final dist = GeometryUtils.distanceFromPointToSegmentMeters(
            cp.coordinates!,
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

    // בדיקת ג"ג — הציר חייב להישאר בתוך גבול הגזרה
    if (_navigationBoundary != null &&
        _navigationBoundary!.coordinates.length >= 3 &&
        _waypoints.isNotEmpty) {
      final boundaryCoords = _navigationBoundary!.coordinates;

      // בדיקת כל waypoint בתוך הפוליגון
      for (final wp in _waypoints) {
        final coord = Coordinate(lat: wp.latitude, lng: wp.longitude, utm: '');
        if (!GeometryUtils.isPointInPolygon(coord, boundaryCoords)) {
          return 'הציר חורג מגבול הגזרה. יש לוודא שכל הציר נמצא בתוך הגבול.';
        }
      }

    }

    // בדיקת נת"ב — הציר לא עובר דרך נקודות בטיחות בחומרה בינונית+
    if (_waypoints.length >= 2) {
      const dangerousSeverities = {'medium', 'high', 'critical'};
      const safetyThreshold = 25.0; // מטרים

      final dangerousSafetyPoints = _safetyPoints
          .where((sp) => dangerousSeverities.contains(sp.severity))
          .toList();

      for (final sp in dangerousSafetyPoints) {
        if (sp.type == 'point' && sp.coordinates != null) {
          // נת"ב נקודה — בדיקת מרחק מכל מקטע
          for (int i = 0; i < _waypoints.length - 1; i++) {
            final segA = Coordinate(lat: _waypoints[i].latitude, lng: _waypoints[i].longitude, utm: '');
            final segB = Coordinate(lat: _waypoints[i + 1].latitude, lng: _waypoints[i + 1].longitude, utm: '');
            final dist = GeometryUtils.distanceFromPointToSegmentMeters(
              sp.coordinates!,
              segA,
              segB,
            );
            if (dist <= safetyThreshold) {
              return 'הציר עובר דרך אזור מסוכן: ${sp.name}. יש לתכנן מסלול שעוקף אזורים מסוכנים.';
            }
          }
        } else if (sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.length >= 3) {
          // נת"ב פוליגון — בדיקה אם מקטע כלשהו חותך/נכנס לפוליגון
          for (int i = 0; i < _waypoints.length - 1; i++) {
            final segA = Coordinate(lat: _waypoints[i].latitude, lng: _waypoints[i].longitude, utm: '');
            final segB = Coordinate(lat: _waypoints[i + 1].latitude, lng: _waypoints[i + 1].longitude, utm: '');
            if (GeometryUtils.doesSegmentIntersectPolygon(segA, segB, sp.polygonCoordinates!)) {
              return 'הציר עובר דרך אזור מסוכן: ${sp.name}. יש לתכנן מסלול שעוקף אזורים מסוכנים.';
            }
          }
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

      // חישוב אורך ציר מעודכן מהנתיב שצויר
      final pathLengthKm = GeometryUtils.calculatePathLengthKm(plannedPath);

      final route = widget.navigation.routes[widget.navigatorUid]!;
      final updatedRoute = route.copyWith(
        plannedPath: plannedPath,
        routeLengthKm: pathLengthKm,
        approvalStatus: _wasApproved && !_approvalWarningShown
            ? route.approvalStatus
            : 'not_submitted',
        clearRejectionNotes: true,
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
            () {
              var s = 'מקטע: ${segmentBearing.round()}° / ${segmentDistance.round()}מ\'';
              final fromElev = _waypointElevations[_waypoints.length - 2];
              final toElev = _waypointElevations[_waypoints.length - 1];
              if (fromElev != null && toElev != null) {
                final diff = toElev - fromElev;
                final sign = diff >= 0 ? '+' : '';
                s += ' ${sign}${diff}מ\'';
              }
              return s;
            }(),
            style: TextStyle(fontSize: 12, color: Colors.orange[800], fontWeight: FontWeight.w500),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(width: 12),
          Text(
            'כולל: ${totalMeters}מ\'',
            style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
            textDirection: TextDirection.rtl,
          ),
          if (_routeAscent > 0 || _routeDescent > 0) ...[
            const SizedBox(width: 12),
            Icon(Icons.arrow_upward, size: 13, color: Colors.green[700]),
            Text('${_routeAscent}מ\'',
                style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_downward, size: 13, color: Colors.red[700]),
            Text('${_routeDescent}מ\'',
                style: TextStyle(fontSize: 11, color: Colors.red[700], fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // חישוב bounds מנקודות הציון
    final cpPoints = widget.checkpoints
        .where((cp) => !cp.isPolygon && cp.coordinates != null)
        .map((cp) => cp.coordinates!.toLatLng())
        .toList();
    final allPoints = [...cpPoints, ..._waypoints];
    // עדיפות לגבול גזרה אם קיים
    final boundaryPoints = _boundaries.isNotEmpty && _boundaries.first.coordinates.isNotEmpty
        ? _boundaries.first.coordinates.map((c) => LatLng(c.lat, c.lng)).toList()
        : <LatLng>[];
    final boundsPoints = boundaryPoints.isNotEmpty
        ? boundaryPoints
        : allPoints;
    final hasBounds = boundsPoints.length > 1;
    final bounds = hasBounds ? LatLngBounds.fromPoints(boundsPoints) : null;
    final center = bounds?.center ?? (cpPoints.isNotEmpty ? cpPoints.first : const LatLng(31.5, 34.75));

    // markers לנקודות ציון קבועות (עיגול כחול עם מספר)
    final cpMarkers = <Marker>[];
    for (var i = 0; i < widget.checkpoints.length; i++) {
      final cp = widget.checkpoints[i];
      if (cp.isPolygon || cp.coordinates == null) continue;

      cpMarkers.add(Marker(
        point: cp.coordinates!.toLatLng(),
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
    if (_startCheckpoint != null && !_startCheckpoint!.isPolygon && _startCheckpoint!.coordinates != null) {
      startEndMarkers.add(Marker(
        point: _startCheckpoint!.coordinates!.toLatLng(),
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
    if (_endCheckpoint != null && !_endCheckpoint!.isPolygon && _endCheckpoint!.coordinates != null) {
      startEndMarkers.add(Marker(
        point: _endCheckpoint!.coordinates!.toLatLng(),
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

    // markers לנקודות ציר שצייר המנווט — לחיצה לבחירה, לחיצה ארוכה למחיקה
    final wpMarkers = _waypoints.asMap().entries.map((entry) {
      final isSelected = _selectedWaypointIndex == entry.key;
      return Marker(
        point: entry.value,
        width: isSelected ? 30 : 24,
        height: isSelected ? 30 : 24,
        child: GestureDetector(
          onTap: () {
            setState(() {
              if (_selectedWaypointIndex == entry.key) {
                _selectedWaypointIndex = null; // ביטול בחירה
              } else {
                _selectedWaypointIndex = entry.key; // בחירת נקודה
              }
            });
          },
          onLongPress: () => _deleteWaypoint(entry.key),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.greenAccent : Colors.white,
                width: isSelected ? 3 : 2,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)]
                  : null,
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
        ),
      );
    }).toList();

    // markers לנקודות אמצע — "+" בין כל שתי נקודות עוקבות להוספת נקודה חדשה
    final midpointMarkers = <Marker>[];
    if (_waypoints.length >= 2) {
      for (int i = 0; i < _waypoints.length - 1; i++) {
        final a = _waypoints[i];
        final b = _waypoints[i + 1];
        final midLat = (a.latitude + b.latitude) / 2;
        final midLng = (a.longitude + b.longitude) / 2;
        final idx = i;
        midpointMarkers.add(Marker(
          point: LatLng(midLat, midLng),
          width: 22,
          height: 22,
          child: GestureDetector(
            onTap: () => _insertMidpoint(idx),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.add, size: 14, color: Colors.white),
              ),
            ),
          ),
        ));
      }
    }

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
                    Icon(
                      _selectedWaypointIndex != null ? Icons.open_with : Icons.touch_app,
                      size: 20,
                      color: _selectedWaypointIndex != null ? Colors.green[700] : Colors.grey[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedWaypointIndex != null
                            ? 'לחץ על המפה להזיז נקודה ${_selectedWaypointIndex! + 1}'
                            : _waypoints.isEmpty
                                ? 'לחץ על המפה לציור הציר'
                                : 'נקודות ציר: ${_waypoints.length}',
                        style: TextStyle(
                          color: _selectedWaypointIndex != null ? Colors.green[700] : Colors.grey[700],
                          fontWeight: _selectedWaypointIndex != null ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (_selectedWaypointIndex != null)
                      IconButton(
                        icon: Icon(Icons.close, size: 20, color: Colors.green[700]),
                        onPressed: () => setState(() => _selectedWaypointIndex = null),
                        tooltip: 'בטל בחירה',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
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
                  initialMapType: MapConfig.resolveMapType(widget.navigation.displaySettings.defaultMap),
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
                    // polyline של הנתיב שצייר המנווט (תמיד מוצג — מטרת העריכה)
                    if (_waypoints.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: _waypoints,
                          color: Colors.blue,
                          strokeWidth: 3.0,
                        ),
                      ]),
                    // קו בין נקודות ציון (רפרנס)
                    if (_showRoutes && cpPoints.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: cpPoints,
                          color: Colors.blue.withValues(alpha: 0.3 * _routesOpacity),
                          strokeWidth: 2.0,
                        ),
                      ]),
                    // נקודות ציון קבועות
                    if (_showNZ)
                      MarkerLayer(markers: cpMarkers.map((m) => Marker(
                        point: m.point,
                        width: m.width,
                        height: m.height,
                        child: Opacity(opacity: _nzOpacity, child: m.child),
                      )).toList()),
                    // נקודות התחלה/סיום (תמיד מוצג)
                    if (startEndMarkers.isNotEmpty)
                      MarkerLayer(markers: startEndMarkers),
                    // נקודות אמצע — כפתורי "+" להוספת נקודה חדשה
                    if (midpointMarkers.isNotEmpty)
                      MarkerLayer(markers: midpointMarkers),
                    // נקודות ציר של המנווט (תמיד מוצג — מטרת העריכה)
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
                  layers: [
                    MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, onVisibilityChanged: (v) => setState(() => _showGG = v), opacity: _ggOpacity, onOpacityChanged: (v) => setState(() => _ggOpacity = v)),
                    MapLayerConfig(id: 'nz', label: 'נקודות ציון', color: Colors.blue, visible: _showNZ, onVisibilityChanged: (v) => setState(() => _showNZ = v), opacity: _nzOpacity, onOpacityChanged: (v) => setState(() => _nzOpacity = v)),
                    MapLayerConfig(id: 'nb', label: 'נקודות בטיחות', color: Colors.red, visible: _showNB, onVisibilityChanged: (v) => setState(() => _showNB = v), opacity: _nbOpacity, onOpacityChanged: (v) => setState(() => _nbOpacity = v)),
                    MapLayerConfig(id: 'ba', label: 'ביצי אזור', color: Colors.green, visible: _showBA, onVisibilityChanged: (v) => setState(() => _showBA = v), opacity: _baOpacity, onOpacityChanged: (v) => setState(() => _baOpacity = v)),
                    MapLayerConfig(id: 'routes', label: 'מסלול', color: Colors.orange, visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v), opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
