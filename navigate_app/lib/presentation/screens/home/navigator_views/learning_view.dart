import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/entities/nav_layer.dart' as nav;
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/navigation_repository.dart';
import '../../../../data/repositories/area_repository.dart';
import '../../../../data/repositories/unit_repository.dart';
import '../../../../data/repositories/boundary_repository.dart';
import '../../../../data/repositories/nav_layer_repository.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../widgets/map_with_selector.dart';
import 'route_editor_screen.dart';

/// תצוגת למידה למנווט — לשוניות דינמיות לפי LearningSettings
class LearningView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final ValueChanged<domain.Navigation> onNavigationUpdated;

  const LearningView({
    super.key,
    required this.navigation,
    required this.currentUser,
    required this.onNavigationUpdated,
  });

  @override
  State<LearningView> createState() => _LearningViewState();
}

class _LearningViewState extends State<LearningView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<_LearningTab> _tabs;
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationRepository _navigationRepo = NavigationRepository();
  final AreaRepository _areaRepo = AreaRepository();
  final UnitRepository _unitRepo = UnitRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();

  /// ניווט נוכחי — mutable, מתעדכן אחרי כל שמירה
  late domain.Navigation _currentNavigation;

  /// נקודות ציון טעונות לפי sequence — לשימוש במפה
  List<Checkpoint> _routeCheckpoints = [];
  bool _checkpointsLoaded = false;

  // שמות לתצוגה
  String? _unitName;
  String? _areaName;
  String? _boundaryName;

  // נקודות התחלה/סיום/ביניים
  Checkpoint? _startCheckpoint;
  Checkpoint? _endCheckpoint;
  List<Checkpoint> _waypointCheckpoints = [];

  // שכבות מפה — גבולות ונקודות בטיחות
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

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadCheckpoints();
  }

  @override
  void didUpdateWidget(LearningView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentNavigation = widget.navigation;
    if (oldWidget.navigation.id != widget.navigation.id) {
      _buildTabs();
      _tabController.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _buildTabs() {
    final settings = widget.navigation.learningSettings;
    _tabs = [];

    if (settings.showNavigationDetails) {
      _tabs.add(_LearningTab(
        label: 'פרטי ניווט',
        icon: Icons.info_outline,
        builder: _buildDetailsTab,
      ));
    }

    if (settings.showRoutes) {
      _tabs.add(_LearningTab(
        label: 'הציר שלי',
        icon: Icons.route,
        builder: _buildRouteTab,
      ));
    }

    if (settings.allowRouteEditing) {
      _tabs.add(_LearningTab(
        label: 'עריכה ואישור',
        icon: Icons.edit,
        builder: _buildEditTab,
      ));
    }

    if (settings.allowRouteNarration) {
      _tabs.add(_LearningTab(
        label: 'סיפור דרך',
        icon: Icons.record_voice_over,
        builder: _buildNarrationTab,
      ));
    }

    // אם אין לשוניות בכלל, הוסף placeholder
    if (_tabs.isEmpty) {
      _tabs.add(_LearningTab(
        label: 'למידה',
        icon: Icons.school,
        builder: _buildEmptyTab,
      ));
    }
  }

  /// טעינת נתונים — שמות, נקודות ציון, נקודות כלליות
  Future<void> _loadCheckpoints() async {
    // טעינת שמות יחידה, אזור, גבול גזרה
    try {
      if (widget.navigation.selectedUnitId != null) {
        final unit = await _unitRepo.getById(widget.navigation.selectedUnitId!);
        if (mounted) setState(() => _unitName = unit?.name);
      }
      if (widget.navigation.areaId.isNotEmpty) {
        final area = await _areaRepo.getById(widget.navigation.areaId);
        if (mounted) setState(() => _areaName = area?.name);
      }
      if (widget.navigation.boundaryLayerId != null && widget.navigation.boundaryLayerId!.isNotEmpty) {
        final boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
        if (mounted) setState(() => _boundaryName = boundary?.name);
      }
    } catch (_) {}

    final route = widget.navigation.routes[widget.currentUser.uid];
    if (route == null || route.checkpointIds.isEmpty) {
      if (mounted) setState(() => _checkpointsLoaded = true);
      return;
    }

    try {
      // טעינת nav checkpoints למיפוי
      final navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(widget.navigation.id);
      final navCpById = <String, nav.NavCheckpoint>{};
      final navCpBySourceId = <String, nav.NavCheckpoint>{};
      for (final ncp in navCheckpoints) {
        navCpById[ncp.id] = ncp;
        navCpBySourceId[ncp.sourceId] = ncp;
      }

      Checkpoint? resolveCheckpoint(String id) {
        final navCp = navCpById[id] ?? navCpBySourceId[id];
        if (navCp != null) {
          return Checkpoint(
            id: navCp.id,
            areaId: navCp.areaId,
            name: navCp.name,
            description: navCp.description,
            type: navCp.type,
            color: navCp.color,
            coordinates: navCp.coordinates,
            sequenceNumber: navCp.sequenceNumber,
            labels: navCp.labels,
            createdBy: navCp.createdBy,
            createdAt: navCp.createdAt,
          );
        }
        return null;
      }

      Future<Checkpoint?> resolveOrFetch(String id) async {
        final resolved = resolveCheckpoint(id);
        if (resolved != null) return resolved;
        return await _checkpointRepo.getById(id);
      }

      // טעינת נקודות ציון לפי sequence
      final loaded = <Checkpoint>[];
      for (final cpId in route.sequence) {
        final cp = await resolveOrFetch(cpId);
        if (cp != null) loaded.add(cp);
      }

      // טעינת נקודת התחלה
      Checkpoint? startCp;
      if (route.startPointId != null && route.startPointId!.isNotEmpty) {
        startCp = await resolveOrFetch(route.startPointId!);
      }

      // טעינת נקודת סיום
      Checkpoint? endCp;
      if (route.endPointId != null && route.endPointId!.isNotEmpty) {
        endCp = await resolveOrFetch(route.endPointId!);
      }

      // טעינת נקודות ביניים
      final waypointCps = <Checkpoint>[];
      final waypointSettings = widget.navigation.waypointSettings;
      if (waypointSettings.enabled && waypointSettings.waypoints.isNotEmpty) {
        for (final wp in waypointSettings.waypoints) {
          final resolved = await resolveOrFetch(wp.checkpointId);
          if (resolved != null) waypointCps.add(resolved);
        }
      }

      // Load boundaries and safety points
      List<nav.NavBoundary> boundaries = [];
      List<nav.NavSafetyPoint> safetyPoints = [];
      try {
        boundaries = await _navLayerRepo.getBoundariesByNavigation(widget.navigation.id);
      } catch (_) {}
      try {
        safetyPoints = await _navLayerRepo.getSafetyPointsByNavigation(widget.navigation.id);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _routeCheckpoints = loaded;
          _startCheckpoint = startCp;
          _endCheckpoint = endCp;
          _waypointCheckpoints = waypointCps;
          _boundaries = boundaries;
          _safetyPoints = safetyPoints;
          _checkpointsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkpointsLoaded = true);
    }
  }

  // ===========================================================================
  // Tab builders
  // ===========================================================================

  /// תרגום סטטוס אישור לעברית
  String _approvalStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'מאושר';
      case 'pending_approval':
        return 'נשלח לאישור מפקד';
      case 'rejected':
        return 'ציר נפסל';
      case 'not_submitted':
      default:
        return 'מחכה לעריכת משתמש';
    }
  }

  Color _approvalStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'pending_approval':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _approvalStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'pending_approval':
        return Icons.hourglass_top;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.edit;
    }
  }

  Widget _buildDetailsTab() {
    final nav = widget.navigation;
    final route = nav.routes[widget.currentUser.uid];
    final approvalStatus = route?.approvalStatus ?? 'not_submitted';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // יחידה
          _infoCard('יחידה', _unitName ?? 'לא נבחרה'),
          // שם ניווט
          _infoCard('שם ניווט', nav.name),
          // שטח — שם ולא ID
          _infoCard('שטח', _areaName ?? nav.areaId),
          // גבול גזרה — שם ולא ID
          if (nav.boundaryLayerId != null)
            _infoCard('גבול גזרה', _boundaryName ?? nav.boundaryLayerId!),
          if (nav.routeLengthKm != null)
            _infoCard(
              'מרחק ניווט',
              '${nav.routeLengthKm!.min.toStringAsFixed(1)} - ${nav.routeLengthKm!.max.toStringAsFixed(1)} ק"מ',
            ),
          if (route != null) ...[
            const SizedBox(height: 16),
            Text(
              'הציר שלי',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _infoCard('מספר נקודות', '${route.checkpointIds.length}'),
            _infoCard('אורך ציר', '${_calculateRouteLengthKm(route).toStringAsFixed(2)} ק"מ'),
            if (_startCheckpoint != null)
              _infoCard('נקודת התחלה', _startCheckpoint!.description.isNotEmpty ? _startCheckpoint!.description : _startCheckpoint!.name),
            if (_endCheckpoint != null)
              _infoCard('נקודת סיום', _endCheckpoint!.description.isNotEmpty ? _endCheckpoint!.description : _endCheckpoint!.name),
            if (_waypointCheckpoints.isNotEmpty)
              _infoCard('נקודות ביניים', '${_waypointCheckpoints.length}'),
          ],
          const SizedBox(height: 16),

          // סטטוס אישור ציר
          Card(
            color: _approvalStatusColor(approvalStatus).withAlpha(25),
            child: ListTile(
              leading: Icon(
                _approvalStatusIcon(approvalStatus),
                color: _approvalStatusColor(approvalStatus),
                size: 32,
              ),
              title: const Text('סטטוס הציר', style: TextStyle(fontSize: 13, color: Colors.grey)),
              subtitle: Text(
                _approvalStatusLabel(approvalStatus),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _approvalStatusColor(approvalStatus),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    // בדיקה אם הציר נערך
    final bool hasPlannedPath = route.plannedPath.isNotEmpty;
    final bool sequenceChanged = route.sequence.isNotEmpty &&
        route.sequence.join(',') != route.checkpointIds.join(',');
    final bool isEdited = hasPlannedPath || sequenceChanged;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // מידע ראשוני/ערוך
          Card(
            color: isEdited ? Colors.amber[50] : Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    isEdited ? Icons.edit : Icons.info_outline,
                    color: isEdited ? Colors.amber[800] : Colors.blue[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdited ? 'ציר ערוך' : 'ציר ראשוני',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isEdited ? Colors.amber[900] : Colors.blue[900],
                          ),
                        ),
                        Text(
                          isEdited
                              ? 'הציר נערך על ידך — מוצג הציר המעודכן'
                              : 'הציר כפי שחולק — טרם נערך',
                          style: TextStyle(
                            fontSize: 12,
                            color: isEdited ? Colors.amber[800] : Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // מפת ציר
          _buildRouteMap(),
          const SizedBox(height: 16),

          Text(
            'נקודות הציר',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          // רשימת נקודות מלאה — התחלה + נקודות ציון + ביניים + סיום
          Card(
            child: Column(
              children: [
                // נקודת התחלה
                if (_startCheckpoint != null)
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(_startCheckpoint!.description.isNotEmpty ? _startCheckpoint!.description : _startCheckpoint!.name),
                    subtitle: const Text('נקודת התחלה', style: TextStyle(color: Colors.green)),
                  ),
                if (_startCheckpoint != null && (_routeCheckpoints.isNotEmpty || _endCheckpoint != null))
                  const Divider(height: 1),

                // נקודות ציון
                ...List.generate(_routeCheckpoints.length, (index) {
                  final cp = _routeCheckpoints[index];
                  return Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text('${index + 1}', style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(cp.description.isNotEmpty ? cp.description : cp.name),
                        subtitle: cp.sequenceNumber > 0 ? Text('נקודה ${cp.sequenceNumber}') : null,
                      ),
                      if (index < _routeCheckpoints.length - 1 || _endCheckpoint != null)
                        const Divider(height: 1),
                    ],
                  );
                }),

                // נקודת סיום
                if (_endCheckpoint != null)
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.red,
                      child: Text('S', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(_endCheckpoint!.description.isNotEmpty ? _endCheckpoint!.description : _endCheckpoint!.name),
                    subtitle: const Text('נקודת סיום', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _infoCard('אורך ציר', '${_calculateRouteLengthKm(route).toStringAsFixed(2)} ק"מ'),
          _infoCard('נקודות ציון', '${route.checkpointIds.length}'),
        ],
      ),
    );
  }

  /// בניית מפה עם נקודות ציון, polyline, שכבות גבולות ונקודות בטיחות
  Widget _buildRouteMap() {
    if (!_checkpointsLoaded) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_routeCheckpoints.isEmpty) {
      return SizedBox(
        height: 250,
        child: Card(
          color: Colors.grey[100],
          child: const Center(child: Text('אין נתוני מיקום לנקודות')),
        ),
      );
    }

    // שימוש ב-_currentNavigation לקריאת ציר עדכני
    final currentRoute = _currentNavigation.routes[widget.currentUser.uid];

    final points = _routeCheckpoints
        .map((cp) => cp.coordinates.toLatLng())
        .toList();

    // חישוב bounds כולל נקודות התחלה/סיום
    final allBoundsPoints = <LatLng>[...points];
    if (_startCheckpoint != null) allBoundsPoints.add(_startCheckpoint!.coordinates.toLatLng());
    if (_endCheckpoint != null) allBoundsPoints.add(_endCheckpoint!.coordinates.toLatLng());
    final bounds = LatLngBounds.fromPoints(allBoundsPoints.isNotEmpty ? allBoundsPoints : points);

    // === שכבת גבולות גזרה (PolygonLayer) ===
    final boundaryPolygons = <Polygon>[];
    if (_showBoundary) {
      for (final boundary in _boundaries) {
        if (boundary.coordinates.length >= 3) {
          boundaryPolygons.add(Polygon(
            points: boundary.coordinates.map((c) => c.toLatLng()).toList(),
            color: Colors.black.withOpacity(0.1 * _boundaryOpacity),
            borderColor: Colors.black.withOpacity(_boundaryOpacity),
            borderStrokeWidth: boundary.strokeWidth,
            isFilled: true,
          ));
        }
      }
    }

    // === שכבת נקודות בטיחות — פוליגונים ונקודות ===
    final safetyPolygons = <Polygon>[];
    final safetyMarkers = <Marker>[];
    if (_showSafetyPoints) {
      for (final sp in _safetyPoints) {
        final sColor = _severityColor(sp.severity);
        if (sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.length >= 3) {
          safetyPolygons.add(Polygon(
            points: sp.polygonCoordinates!.map((c) => c.toLatLng()).toList(),
            color: sColor.withOpacity(0.2 * _safetyPointsOpacity),
            borderColor: sColor.withOpacity(_safetyPointsOpacity),
            borderStrokeWidth: 2.0,
            isFilled: true,
          ));
        } else if (sp.coordinates != null) {
          safetyMarkers.add(Marker(
            point: sp.coordinates!.toLatLng(),
            width: 28,
            height: 28,
            child: Tooltip(
              message: sp.name,
              child: Icon(
                Icons.warning,
                color: sColor.withOpacity(_safetyPointsOpacity),
                size: 28,
              ),
            ),
          ));
        }
      }
    }

    // === markers לנקודות ציון ===
    final markers = <Marker>[];

    // נקודת התחלה
    if (_startCheckpoint != null) {
      markers.add(Marker(
        point: _startCheckpoint!.coordinates.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: _startCheckpoint!.name,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Text(
                'H',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // נקודת סיום
    if (_endCheckpoint != null) {
      markers.add(Marker(
        point: _endCheckpoint!.coordinates.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: _endCheckpoint!.name,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Text(
                'S',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // נקודות ביניים
    for (final wp in _waypointCheckpoints) {
      markers.add(Marker(
        point: wp.coordinates.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: wp.name,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.purple,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Text(
                'B',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // נקודות ציון (route checkpoints)
    for (var i = 0; i < _routeCheckpoints.length; i++) {
      final cp = _routeCheckpoints[i];
      markers.add(Marker(
        point: cp.coordinates.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: cp.name,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // === Polyline — ציר נוכחי (מ-plannedPath אם ערוך, אחרת מנקודות ציון כולל התחלה/סיום) ===
    final List<LatLng> polylinePoints;
    if (currentRoute != null && currentRoute.plannedPath.isNotEmpty) {
      polylinePoints = currentRoute.plannedPath.map((c) => c.toLatLng()).toList();
    } else {
      // ציר ראשוני — כולל נקודת התחלה וסיום
      final fullRoute = <LatLng>[];
      if (_startCheckpoint != null) {
        fullRoute.add(_startCheckpoint!.coordinates.toLatLng());
      }
      fullRoute.addAll(points);
      if (_endCheckpoint != null) {
        fullRoute.add(_endCheckpoint!.coordinates.toLatLng());
      }
      polylinePoints = fullRoute;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 250,
        child: Stack(
          children: [
            MapWithTypeSelector(
              options: MapOptions(
                initialCenter: bounds.center,
                initialZoom: 14.0,
                initialCameraFit: points.length > 1
                    ? CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(40),
                      )
                    : null,
                onTap: _measureMode ? (tapPosition, latlng) => _onMeasureTap(latlng) : null,
              ),
              layers: [
                // שכבת גבולות גזרה
                if (boundaryPolygons.isNotEmpty)
                  PolygonLayer(polygons: boundaryPolygons),
                // שכבת נ"ב פוליגונים
                if (safetyPolygons.isNotEmpty)
                  PolygonLayer(polygons: safetyPolygons),
                // קו ציר
                if (polylinePoints.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: polylinePoints,
                      color: Colors.blue,
                      strokeWidth: 3.0,
                    ),
                  ]),
                // קו מדידה
                if (_measurePointA != null && _measurePointB != null)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [_measurePointA!, _measurePointB!],
                      color: Colors.yellow,
                      strokeWidth: 2.0,
                    ),
                  ]),
                // נ"ב markers
                if (safetyMarkers.isNotEmpty)
                  MarkerLayer(markers: safetyMarkers),
                // כל ה-markers
                MarkerLayer(markers: markers),
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
            // בקרת שכבות
            Positioned(top: 8, left: 56, child: _buildLayerControls()),
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
    );
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
        // לחיצה ראשונה — או איפוס
        _measurePointA = point;
        _measurePointB = null;
      } else {
        // לחיצה שנייה
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

  /// בקרת שכבות מפה — מתכווץ/מתרחב
  Widget _buildLayerControls() {
    if (!_layerControlsExpanded) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _layerControlsExpanded = true),
            child: const Icon(Icons.layers, color: Colors.black87),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white.withOpacity(0.95),
      borderRadius: BorderRadius.circular(8),
      elevation: 4,
      child: SizedBox(
        width: 220,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // כותרת + כפתור סגירה
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.layers, size: 18),
                  const SizedBox(width: 4),
                  const Expanded(child: Text('שכבות', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _layerControlsExpanded = false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ג"ג — גבול גזרה
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('ג"ג', style: TextStyle(fontSize: 12))),
                  Switch(
                    value: _showBoundary,
                    onChanged: (v) => setState(() => _showBoundary = v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
            if (_showBoundary)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    const Text('שקיפות', style: TextStyle(fontSize: 11)),
                    Expanded(
                      child: Slider(
                        value: _boundaryOpacity,
                        min: 0.1,
                        max: 1.0,
                        onChanged: (v) => setState(() => _boundaryOpacity = v),
                      ),
                    ),
                  ],
                ),
              ),
            // נת"ב — נקודות בטיחות
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('נת"ב', style: TextStyle(fontSize: 12))),
                  Switch(
                    value: _showSafetyPoints,
                    onChanged: (v) => setState(() => _showSafetyPoints = v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
            if (_showSafetyPoints)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    const Text('שקיפות', style: TextStyle(fontSize: 11)),
                    Expanded(
                      child: Slider(
                        value: _safetyPointsOpacity,
                        min: 0.1,
                        max: 1.0,
                        onChanged: (v) => setState(() => _safetyPointsOpacity = v),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// צבע לפי חומרה
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

  void _openRouteEditor() {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteEditorScreen(
          navigation: _currentNavigation,
          navigatorUid: widget.currentUser.uid,
          checkpoints: _routeCheckpoints,
          startCheckpoint: _startCheckpoint,
          endCheckpoint: _endCheckpoint,
          waypointCheckpoints: _waypointCheckpoints,
          onNavigationUpdated: (updatedNav) {
            // If route was rejected, reset to not_submitted after editing
            final updatedRoute = updatedNav.routes[widget.currentUser.uid];
            if (updatedRoute != null && updatedRoute.approvalStatus == 'rejected') {
              final resetRoute = updatedRoute.copyWith(
                approvalStatus: 'not_submitted',
                rejectionNotes: '',
              );
              final resetRoutes = Map<String, domain.AssignedRoute>.from(updatedNav.routes);
              resetRoutes[widget.currentUser.uid] = resetRoute;
              final resetNav = updatedNav.copyWith(routes: resetRoutes, updatedAt: DateTime.now());
              _navigationRepo.update(resetNav);
              setState(() => _currentNavigation = resetNav);
              widget.onNavigationUpdated(resetNav);
            } else {
              setState(() => _currentNavigation = updatedNav);
              widget.onNavigationUpdated(updatedNav);
            }
          },
        ),
      ),
    );
  }

  Future<void> _submitRouteForApproval() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final updatedRoute = route.copyWith(approvalStatus: 'pending_approval');
    final updatedRoutes = Map<String, domain.AssignedRoute>.from(
      _currentNavigation.routes,
    );
    updatedRoutes[widget.currentUser.uid] = updatedRoute;

    final updatedNav = _currentNavigation.copyWith(
      routes: updatedRoutes,
      updatedAt: DateTime.now(),
    );

    try {
      await _navigationRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);
      widget.onNavigationUpdated(updatedNav);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הציר נשלח לאישור המפקד')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשליחה: $e')),
        );
      }
    }
  }

  Widget _buildEditTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    final approvalStatus = route.approvalStatus;

    // צבע, אייקון וטקסט לפי סטטוס
    final Color statusColor;
    final IconData statusIcon;
    final String statusTitle;
    final String statusSubtitle;
    switch (approvalStatus) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusTitle = 'הציר מאושר';
        statusSubtitle = 'שינויים נוספים ידרשו שליחה מחדש';
        break;
      case 'pending_approval':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        statusTitle = 'ממתין לאישור';
        statusSubtitle = 'הציר נשלח למפקד — ממתין לאישור';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusTitle = 'ציר נפסל';
        statusSubtitle = 'לחץ למטה לקריאת הערות המפקד';
        break;
      default: // not_submitted
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        statusTitle = 'הציר טרם נשלח';
        statusSubtitle = 'סקור את הציר ושלח לאישור המפקד';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // סטטוס אישור
          Card(
            color: statusColor.withValues(alpha: 0.1),
            child: ListTile(
              leading: Icon(statusIcon, color: statusColor),
              title: Text(statusTitle),
              subtitle: Text(statusSubtitle),
            ),
          ),
          const SizedBox(height: 16),

          // כפתור עריכת ציר על המפה
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _checkpointsLoaded ? _openRouteEditor : null,
              icon: const Icon(Icons.map),
              label: Text(
                route.plannedPath.isEmpty
                    ? 'ערוך ציר על המפה'
                    : 'ערוך ציר על המפה (${route.plannedPath.length} נקודות)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // רשימת נקודות מלאה — כולל התחלה, סיום, ביניים
          Text(
            'סדר נקודות',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                // נקודת התחלה
                if (_startCheckpoint != null) ...[
                  ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green[700],
                      child: const Text('H', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(_startCheckpoint!.description.isNotEmpty ? _startCheckpoint!.description : _startCheckpoint!.name),
                    subtitle: const Text('התחלה', style: TextStyle(color: Colors.green, fontSize: 12)),
                  ),
                  const Divider(height: 1),
                ],

                // נקודות ציון לפי sequence
                ...List.generate(route.sequence.length, (index) {
                  final cpId = route.sequence[index];
                  final loadedCp = _routeCheckpoints.length > index ? _routeCheckpoints[index] : null;
                  final displayName = loadedCp != null
                      ? (loadedCp.description.isNotEmpty ? loadedCp.description : loadedCp.name)
                      : cpId;
                  final pointNum = loadedCp != null && loadedCp.sequenceNumber > 0
                      ? 'נקודה ${loadedCp.sequenceNumber}'
                      : null;

                  return Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(displayName),
                        subtitle: pointNum != null ? Text(pointNum, style: const TextStyle(fontSize: 12)) : null,
                      ),
                      if (index < route.sequence.length - 1 || _endCheckpoint != null || _waypointCheckpoints.isNotEmpty)
                        const Divider(height: 1),
                    ],
                  );
                }),

                // נקודות ביניים
                ..._waypointCheckpoints.map((wp) => Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.purple,
                        child: const Text('B', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(wp.description.isNotEmpty ? wp.description : wp.name),
                      subtitle: const Text('ביניים', style: TextStyle(color: Colors.purple, fontSize: 12)),
                    ),
                    const Divider(height: 1),
                  ],
                )),

                // נקודת סיום
                if (_endCheckpoint != null)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.red[700],
                      child: const Text('S', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(_endCheckpoint!.description.isNotEmpty ? _endCheckpoint!.description : _endCheckpoint!.name),
                    subtitle: const Text('סיום', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // כפתור שליחה / פסילה
          if (approvalStatus == 'rejected') ...[
            // כפתור אדום — ציר נפסל
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showRejectionNotes(route),
                icon: const Icon(Icons.error_outline),
                label: const Text('ציר נפסל — לחץ לקריאת הערות'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ] else ...[
            // כפתור 3-מצבים
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: approvalStatus == 'not_submitted'
                    ? _submitRouteForApproval
                    : null,
                icon: Icon(
                  approvalStatus == 'approved'
                      ? Icons.check_circle
                      : approvalStatus == 'pending_approval'
                          ? Icons.hourglass_top
                          : Icons.send,
                ),
                label: Text(
                  approvalStatus == 'approved'
                      ? 'ציר מאושר'
                      : approvalStatus == 'pending_approval'
                          ? 'ממתין לאישור'
                          : 'שלח ציר לאישור',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: approvalStatus == 'approved'
                      ? Colors.green
                      : approvalStatus == 'pending_approval'
                          ? Colors.orange
                          : Colors.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: approvalStatus == 'approved'
                      ? Colors.green.withValues(alpha: 0.7)
                      : Colors.orange.withValues(alpha: 0.7),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showRejectionNotes(domain.AssignedRoute route) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הערות המפקד'),
        content: Text(route.rejectionNotes.isNotEmpty ? route.rejectionNotes : 'אין הערות'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportNarrationCsv() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final rows = <List<String>>[
      ['#', 'נקודה', 'פעולה', 'הערות'],
    ];

    for (var i = 0; i < route.sequence.length; i++) {
      final cpName = route.sequence[i];
      final isFirst = i == 0;
      final isLast = i == route.sequence.length - 1;
      final action = isFirst
          ? 'התחלה'
          : isLast
              ? 'סיום'
              : 'מעבר';
      rows.add(['${i + 1}', cpName, action, '']);
    }

    final csvData = const ListToCsvConverter().convert(rows);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/narration_${_currentNavigation.id}_${widget.currentUser.uid}.csv',
      );
      await file.writeAsString('\uFEFF$csvData'); // BOM for Hebrew in Excel

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הקובץ נשמר: ${file.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא: $e')),
        );
      }
    }
  }

  Widget _buildNarrationTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת
          Row(
            children: [
              const Icon(Icons.record_voice_over, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(
                'סיפור דרך — כרונולוגיה',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'סדר הנקודות לאורך הציר — רשום הערות לכל תחנה',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // טבלת כרונולוגיה
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // כותרת טבלה
                Container(
                  color: Colors.deepPurple[50],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: const Row(
                    children: [
                      SizedBox(width: 32, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('נקודה', style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('פעולה', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                // שורות
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: route.sequence.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final cpName = route.sequence[index];
                    final isFirst = index == 0;
                    final isLast = index == route.sequence.length - 1;

                    final actionLabel = isFirst
                        ? 'התחלה'
                        : isLast
                            ? 'סיום'
                            : 'מעבר';
                    final actionColor = isFirst
                        ? Colors.green
                        : isLast
                            ? Colors.red
                            : Colors.blue;
                    final actionIcon = isFirst
                        ? Icons.play_arrow
                        : isLast
                            ? Icons.flag
                            : Icons.arrow_forward;

                    // חיפוש ה-checkpoint הטעון כדי להציג קואורדינטות
                    final loadedCp = _routeCheckpoints.length > index
                        ? _routeCheckpoints[index]
                        : null;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: actionColor,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cpName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                if (loadedCp != null)
                                  Text(
                                    '${loadedCp.coordinates.lat.toStringAsFixed(5)}, ${loadedCp.coordinates.lng.toStringAsFixed(5)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                Icon(actionIcon, size: 16, color: actionColor),
                                const SizedBox(width: 4),
                                Text(
                                  actionLabel,
                                  style: TextStyle(color: actionColor, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // סיכום
          _infoCard('סה"כ נקודות', '${route.sequence.length}'),
          _infoCard('אורך ציר', '${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),

          const SizedBox(height: 16),

          // כפתור ייצוא CSV
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportNarrationCsv,
              icon: const Icon(Icons.download),
              label: const Text('ייצוא לקובץ CSV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'שלב הלמידה פעיל',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'המפקד לא הפעיל הגדרות למידה נוספות',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// חישוב אורך ציר — מ-plannedPath אם נערך, אחרת routeLengthKm המקורי
  double _calculateRouteLengthKm(domain.AssignedRoute route) {
    if (route.plannedPath.isNotEmpty) {
      return GeometryUtils.calculatePathLengthKm(route.plannedPath);
    }
    return route.routeLengthKm;
  }

  Widget _infoCard(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: _tabs.length > 3,
          tabs: _tabs.map((t) => Tab(text: t.label, icon: Icon(t.icon))).toList(),
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _tabs.map((t) => t.builder()).toList(),
          ),
        ),
      ],
    );
  }
}

class _LearningTab {
  final String label;
  final IconData icon;
  final Widget Function() builder;

  _LearningTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
}
