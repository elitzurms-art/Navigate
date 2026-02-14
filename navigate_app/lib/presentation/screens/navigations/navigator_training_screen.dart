import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// מסך למידה למנווט - רק הציר שלו
class NavigatorTrainingScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final String navigatorId;

  const NavigatorTrainingScreen({
    super.key,
    required this.navigation,
    required this.navigatorId,
  });

  @override
  State<NavigatorTrainingScreen> createState() => _NavigatorTrainingScreenState();
}

class _NavigatorTrainingScreenState extends State<NavigatorTrainingScreen>
    with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;

  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  Boundary? _boundary;
  bool _isLoading = false;
  bool _routeApproved = false; // האם הציר אושר
  bool _routeSubmitted = false; // האם הוגש לאישור

  bool _showGG = true;
  double _ggOpacity = 1.0;
  bool _showNZ = true;
  double _nzOpacity = 1.0;
  bool _showNB = false;
  double _nbOpacity = 1.0;
  bool _showRoutes = true;
  double _routesOpacity = 1.0;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      final safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);

      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
      }

      setState(() {
        _checkpoints = checkpoints;
        _safetyPoints = safetyPoints;
        _boundary = boundary;
        _isLoading = false;
      });

      if (boundary != null && boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(LatLng(center.lat, center.lng), 13.0);
          } catch (_) {}
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitForApproval() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('הגשה לאישור בטיחותי'),
        content: const Text(
          'האם להגיש את הציר לאישור מפקד?\n\n'
          'לאחר אישור, כל שינוי ידרוש אישור מחדש.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('הגש לאישור'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _routeSubmitted = true);

      // TODO: שמירה ב-DB

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הציר הוגש לאישור מפקד'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _editRoute() async {
    if (_routeApproved) {
      // אזהרה - ציר מאושר
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 12),
              Text('ציר מאושר'),
            ],
          ),
          content: const Text(
            'הציר כבר אושר בטיחותית!\n\n'
            'שינוי ידרוש אישור מפקד מחדש.\n'
            'האם להמשיך?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('המשך לעריכה'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        _routeApproved = false;
        _routeSubmitted = false;
      });
    }

    // TODO: מעבר למסך עריכת ציר
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('עריכת ציר - בפיתוח')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myRoute = widget.navigation.routes[widget.navigatorId];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            Text(
              'מצב למידה - ${widget.navigatorId}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.table_chart), text: 'נקודות'),
            Tab(icon: Icon(Icons.map), text: 'מפה'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : myRoute == null
              ? const Center(
                  child: Text('אין ציר מוקצה'),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTableView(myRoute),
                    _buildMapView(myRoute),
                  ],
                ),
      bottomNavigationBar: myRoute != null
          ? BottomAppBar(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _editRoute,
                        icon: const Icon(Icons.edit),
                        label: const Text('ערוך ציר'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!_routeSubmitted)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _submitForApproval,
                          icon: const Icon(Icons.check_circle),
                          label: const Text('הגש לאישור'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      )
                    else if (_routeApproved)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              '✓ ציר אושר',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              '⏳ ממתין לאישור',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTableView(domain.AssignedRoute route) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // סיכום
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'הציר שלי',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '${route.sequence.length} נקודות',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${route.routeLengthKm.toStringAsFixed(2)} ק"מ',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // רשימת נקודות
        ...route.sequence.asMap().entries.map((entry) {
          final index = entry.key;
          final checkpointId = entry.value;
          final checkpoint = _checkpoints.firstWhere(
            (cp) => cp.id == checkpointId,
            orElse: () => _checkpoints.first,
          );

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue,
                child: Text('${index + 1}'),
              ),
              title: Text(checkpoint.name),
              subtitle: Text('מספר: ${checkpoint.sequenceNumber}'),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMapView(domain.AssignedRoute route) {
    return Stack(
      children: [
        MapWithTypeSelector(
          showTypeSelector: false,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.navigation.displaySettings.openingLat != null
                ? LatLng(
                    widget.navigation.displaySettings.openingLat!,
                    widget.navigation.displaySettings.openingLng!,
                  )
                : const LatLng(32.0853, 34.7818),
            initialZoom: 13.0,
            onTap: (tapPosition, point) {
              if (_measureMode) {
                setState(() => _measurePoints.add(point));
                return;
              }
            },
          ),
          layers: [
            // פוליגון ג"ג
            if (_showGG && _boundary != null && _boundary!.coordinates.isNotEmpty)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _boundary!.coordinates
                        .map((coord) => LatLng(coord.lat, coord.lng))
                        .toList(),
                    color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                    borderColor: Colors.black.withValues(alpha: _ggOpacity),
                    borderStrokeWidth: _boundary!.strokeWidth,
                    isFilled: true,
                  ),
                ],
              ),

            // הציר שלי
            if (_showRoutes)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _buildMyRoute(route),
                    strokeWidth: 3.0,
                    color: Colors.blue.withValues(alpha: _routesOpacity),
                  ),
                ],
              ),

            // הנקודות שלי בלבד
            if (_showNZ)
              MarkerLayer(
                markers: route.sequence.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final checkpointId = entry.value;
                  final checkpoint = _checkpoints.firstWhere(
                    (cp) => cp.id == checkpointId,
                    orElse: () => _checkpoints.first,
                  );
                  return Marker(
                    point: LatLng(checkpoint.coordinates.lat, checkpoint.coordinates.lng),
                    width: 36,
                    height: 36,
                    child: Opacity(
                      opacity: _nzOpacity,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '$index',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

            // נת"ב - נקודות
            if (_showNB && _safetyPoints.where((p) => p.type == 'point').isNotEmpty)
              MarkerLayer(
                markers: _safetyPoints
                    .where((p) => p.type == 'point' && p.coordinates != null)
                    .map((point) => Marker(
                          point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                          width: 30,
                          height: 30,
                          child: Opacity(
                            opacity: _nbOpacity,
                            child: const Icon(Icons.warning, color: Colors.red, size: 30),
                          ),
                        ))
                    .toList(),
              ),
            if (_showNB && _safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
              PolygonLayer(
                polygons: _safetyPoints
                    .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                    .map((point) => Polygon(
                          points: point.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                          color: Colors.red.withValues(alpha: 0.2 * _nbOpacity),
                          borderColor: Colors.red.withValues(alpha: _nbOpacity),
                          borderStrokeWidth: 2,
                          isFilled: true,
                        ))
                    .toList(),
              ),

            // שכבות מדידה
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
            MapLayerConfig(
              id: 'gg', label: 'גבול גזרה', color: Colors.black,
              visible: _showGG,
              onVisibilityChanged: (v) => setState(() => _showGG = v),
              opacity: _ggOpacity,
              onOpacityChanged: (v) => setState(() => _ggOpacity = v),
            ),
            MapLayerConfig(
              id: 'nz', label: 'נקודות ציון', color: Colors.blue,
              visible: _showNZ,
              onVisibilityChanged: (v) => setState(() => _showNZ = v),
              opacity: _nzOpacity,
              onOpacityChanged: (v) => setState(() => _nzOpacity = v),
            ),
            MapLayerConfig(
              id: 'nb', label: 'נקודות בטיחות', color: Colors.red,
              visible: _showNB,
              onVisibilityChanged: (v) => setState(() => _showNB = v),
              opacity: _nbOpacity,
              onOpacityChanged: (v) => setState(() => _nbOpacity = v),
            ),
            MapLayerConfig(
              id: 'routes', label: 'צירים', color: Colors.orange,
              visible: _showRoutes,
              onVisibilityChanged: (v) => setState(() => _showRoutes = v),
              opacity: _routesOpacity,
              onOpacityChanged: (v) => setState(() => _routesOpacity = v),
            ),
          ],
        ),
      ],
    );
  }

  List<LatLng> _buildMyRoute(domain.AssignedRoute route) {
    List<LatLng> points = [];

    // התחלה
    if (route.startPointId != null) {
      final start = _checkpoints.firstWhere(
        (cp) => cp.id == route.startPointId,
        orElse: () => _checkpoints.first,
      );
      points.add(LatLng(start.coordinates.lat, start.coordinates.lng));
    }

    // נקודות
    for (final id in route.sequence) {
      final cp = _checkpoints.firstWhere(
        (cp) => cp.id == id,
        orElse: () => _checkpoints.first,
      );
      points.add(LatLng(cp.coordinates.lat, cp.coordinates.lng));
    }

    // סיום
    if (route.endPointId != null && route.endPointId != route.startPointId) {
      final end = _checkpoints.firstWhere(
        (cp) => cp.id == route.endPointId,
        orElse: () => _checkpoints.last,
      );
      points.add(LatLng(end.coordinates.lat, end.coordinates.lng));
    }

    return points;
  }
}
