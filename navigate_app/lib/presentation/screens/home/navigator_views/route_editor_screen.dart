import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../data/repositories/navigation_repository.dart';
import '../../../widgets/map_with_selector.dart';

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

  late List<LatLng> _waypoints;
  bool _isSaving = false;
  bool _wasApproved = false;
  bool _approvalWarningShown = false;

  @override
  void initState() {
    super.initState();
    // טעינת נתיב קיים אם יש
    final route = widget.navigation.routes[widget.navigatorUid];
    _wasApproved = route?.isApproved ?? false;
    if (route != null && route.plannedPath.isNotEmpty) {
      _waypoints = route.plannedPath
          .map((c) => LatLng(c.lat, c.lng))
          .toList();
    } else {
      _waypoints = [];
    }
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

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final plannedPath = _waypoints.map((ll) {
        return Coordinate(lat: ll.latitude, lng: ll.longitude, utm: '');
      }).toList();

      final route = widget.navigation.routes[widget.navigatorUid]!;
      final updatedRoute = route.copyWith(
        plannedPath: plannedPath,
        isApproved: _wasApproved && !_approvalWarningShown
            ? route.isApproved
            : false,
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
    // חישוב bounds מנקודות הציון
    final cpPoints = widget.checkpoints
        .map((cp) => cp.coordinates.toLatLng())
        .toList();
    final allPoints = [...cpPoints, ..._waypoints];
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
            child: MapWithTypeSelector(
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
                // נקודות ציר של המנווט
                MarkerLayer(markers: wpMarkers),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
