import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../core/utils/geometry_utils.dart';
import 'routes_edit_screen.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';

/// שלב 3 - וידוא צירים
class RoutesVerificationScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesVerificationScreen({super.key, required this.navigation});

  @override
  State<RoutesVerificationScreen> createState() => _RoutesVerificationScreenState();
}

class _RoutesVerificationScreenState extends State<RoutesVerificationScreen> with SingleTickerProviderStateMixin {
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;
  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  Boundary? _boundary;
  Map<String, bool> _selectedNavigators = {};
  bool _isLoading = false;

  bool _showGG = true;
  double _ggOpacity = 1.0;
  bool _showNZ = true;
  double _nzOpacity = 1.0;
  bool _showNB = false;
  double _nbOpacity = 1.0;
  bool _showRoutes = true;
  double _routesOpacity = 1.0;
  bool _showWaypoints = true;
  double _waypointsOpacity = 1.0;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // נקודות משותפות
  Set<String> _sharedCheckpointIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCheckpoints();
    // בחר את כל המנווטים כברירת מחדל
    for (final navigatorId in widget.navigation.routes.keys) {
      _selectedNavigators[navigatorId] = true;
    }
    // חישוב נקודות משותפות
    _calculateSharedCheckpoints();
  }

  void _calculateSharedCheckpoints() {
    final checkpointCount = <String, int>{};
    for (final route in widget.navigation.routes.values) {
      for (final cpId in route.checkpointIds) {
        checkpointCount[cpId] = (checkpointCount[cpId] ?? 0) + 1;
      }
    }
    _sharedCheckpointIds = checkpointCount.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toSet();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCheckpoints() async {
    setState(() => _isLoading = true);
    try {
      // טעינת נקודות ציון מהשכבות הניווטיות (כבר מסוננות לפי גבול גזרה)
      final navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
        widget.navigation.id,
      );
      final checkpoints = navCheckpoints.map((nc) => Checkpoint(
        id: nc.sourceId,
        areaId: nc.areaId,
        name: nc.name,
        description: nc.description,
        type: nc.type,
        color: nc.color,
        coordinates: nc.coordinates,
        sequenceNumber: nc.sequenceNumber,
        labels: nc.labels,
        createdBy: nc.createdBy,
        createdAt: nc.createdAt,
      )).toList();

      // טעינת גבול גזרה ניווטי (לתצוגה על המפה)
      Boundary? boundary;
      final navBoundaries = await _navLayerRepo.getBoundariesByNavigation(
        widget.navigation.id,
      );
      if (navBoundaries.isNotEmpty) {
        final nb = navBoundaries.first;
        boundary = Boundary(
          id: nb.sourceId,
          areaId: nb.areaId,
          name: nb.name,
          description: nb.description,
          coordinates: nb.coordinates,
          color: nb.color,
          strokeWidth: nb.strokeWidth,
          createdAt: nb.createdAt,
          updatedAt: nb.updatedAt,
        );
      }

      final safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);

      setState(() {
        _checkpoints = checkpoints;
        _safetyPoints = safetyPoints;
        _boundary = boundary;
        _isLoading = false;
      });

      // התמקד במרכז הגבול אם קיים (עטוף ב-try כי המפה עשויה לא להיות מוכנה)
      try {
        if (boundary != null && boundary.coordinates.isNotEmpty) {
          final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
          _mapController.move(LatLng(center.lat, center.lng), 13.0);
        } else if (checkpoints.where((c) => !c.isPolygon && c.coordinates != null).isNotEmpty) {
          final pointCps = checkpoints.where((c) => !c.isPolygon && c.coordinates != null).toList();
          final latitudes = pointCps.map((c) => c.coordinates!.lat).toList();
          final longitudes = pointCps.map((c) => c.coordinates!.lng).toList();
          final minLat = latitudes.reduce((a, b) => a < b ? a : b);
          final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
          final minLng = longitudes.reduce((a, b) => a < b ? a : b);
          final maxLng = longitudes.reduce((a, b) => a > b ? a : b);
          final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
          _mapController.move(center, 13.0);
        }
      } catch (_) {
        // המפה עשויה לא להיות מוכנה אם הלשונית הנוכחית היא טבלה
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת נתונים: $e')),
        );
      }
    }
  }

  /// איסוף כל מזהי waypoints מכל הצירים
  Set<String> get _allWaypointIds {
    final ids = <String>{};
    for (final route in widget.navigation.routes.values) {
      ids.addAll(route.waypointIds);
    }
    // גם מהגדרות ה-navigation
    if (widget.navigation.waypointSettings.enabled) {
      for (final wp in widget.navigation.waypointSettings.waypoints) {
        ids.add(wp.checkpointId);
      }
    }
    return ids;
  }

  Future<void> _finishVerification() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום וידוא'),
        content: const Text('האם אישרת את כל הצירים?\nניתן לעבור לשלב הבא או לערוך צירים.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('לשלב הבא'),
          ),
        ],
      ),
    );

    if (result == true) {
      // הצגת spinner
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('שומר ומעביר לשלב הבא...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final updatedNavigation = widget.navigation.copyWith(
        routesStage: 'ready',
        updatedAt: DateTime.now(),
      );
      await _navRepo.update(updatedNavigation);

      if (mounted) {
        // סגירת spinner
        Navigator.pop(context);

        // חזרה למסך הכנת ניווט עם עדכון
        Navigator.pop(context, true);
      }
    }
  }

  void _editRoutes() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoutesEditScreen(navigation: widget.navigation),
      ),
    ).then((updated) {
      if (updated == true) {
        // רענון הנתונים
        Navigator.pop(context, true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('וידוא צירים'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.table_chart), text: 'טבלה'),
            Tab(icon: Icon(Icons.map), text: 'מפה'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'ערוך צירים',
            onPressed: _editRoutes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTableView(),
                _buildMapView(),
              ],
            ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _editRoutes,
                  icon: const Icon(Icons.edit),
                  label: const Text('עריכת צירים'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _finishVerification,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('אישור וסיום'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'סיכום צירים',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // מקרא
          _buildLegend(),
          const SizedBox(height: 16),

          // הודעה על שיתוף נקודות
          if (_sharedCheckpointIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.people, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_sharedCheckpointIds.length} נקודות משותפות בין מנווטים',
                          style: TextStyle(color: Colors.orange[700]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // טבלה
          _buildRoutesTable(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Card(
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem('קצר חריג', Colors.yellow[700]!),
                _buildLegendItem('בטווח', Colors.blue),
                _buildLegendItem('ארוך מדי', Colors.red),
              ],
            ),
            if (_allWaypointIds.isNotEmpty || _sharedCheckpointIds.isNotEmpty) ...[
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (_allWaypointIds.isNotEmpty)
                    _buildLegendIconItem('נקודת ביניים', Icons.star, Colors.purple),
                  if (_sharedCheckpointIds.isNotEmpty)
                    _buildLegendIconItem('נקודה משותפת', Icons.people, Colors.orange),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildLegendIconItem(String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildRoutesTable() {
    final routes = widget.navigation.routes;
    if (routes.isEmpty) {
      return const Center(
        child: Text('אין צירים'),
      );
    }

    return Table(
      border: TableBorder.all(color: Colors.grey[300]!),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      children: [
        // כותרות
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: const [
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('מנווט', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('נקודות', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('אורך (ק"מ)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('ביניים', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        // שורות
        ...routes.entries.map((entry) {
          final navigatorId = entry.key;
          final route = entry.value;
          final color = _getRouteColor(route.status);
          final hasShared = route.checkpointIds.any((id) => _sharedCheckpointIds.contains(id));

          return TableRow(
            decoration: BoxDecoration(color: color.withOpacity(0.1)),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: Text(navigatorId)),
                    if (hasShared)
                      Icon(Icons.people, size: 14, color: Colors.orange[700]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${route.checkpointIds.length}'),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(route.routeLengthKm.toStringAsFixed(2)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${route.waypointIds.length}'),
              ),
            ],
          );
        }),
      ],
    );
  }

  Color _getRouteColor(String status) {
    switch (status) {
      case 'too_short':
        return Colors.yellow[700]!;
      case 'optimal':
        return Colors.blue;
      case 'too_long':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildMapView() {
    final waypointIds = _allWaypointIds;

    return Column(
      children: [
        // בורר מנווטים
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.navigation.routes.keys.map((navigatorId) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(navigatorId),
                    selected: _selectedNavigators[navigatorId] ?? false,
                    onSelected: (selected) {
                      setState(() {
                        _selectedNavigators[navigatorId] = selected;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // מפה
        Expanded(
          child: Stack(
            children: [
              MapWithTypeSelector(
                showTypeSelector: false,
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.navigation.displaySettings.openingLat != null &&
                          widget.navigation.displaySettings.openingLng != null
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
                  // גבול גזרה (אם קיים)
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

                  // ציור הצירים
                  if (_showRoutes) ..._buildRoutePolylines(),

                  // נקודות ציון — רגילות
                  if (_showNZ)
                    MarkerLayer(
                      markers: (_boundary != null && _boundary!.coordinates.isNotEmpty
                              ? GeometryUtils.filterPointsInPolygon(
                                  points: _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).toList(),
                                  getCoordinate: (cp) => cp.coordinates!,
                                  polygon: _boundary!.coordinates,
                                )
                              : _checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).toList())
                          .where((cp) => !waypointIds.contains(cp.id)) // סנן waypoints — יוצגו בנפרד
                          .map((cp) {
                        final isShared = _sharedCheckpointIds.contains(cp.id);
                        final markerColor = isShared
                            ? Colors.orange
                            : (cp.color == 'green' ? Colors.green : Colors.blue);

                        return Marker(
                          point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                          width: 36,
                          height: 36,
                          child: Opacity(
                            opacity: _nzOpacity,
                            child: Container(
                              decoration: BoxDecoration(
                                color: markerColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isShared ? Colors.orange[900]! : Colors.white,
                                  width: isShared ? 3 : 2,
                                ),
                              ),
                              child: Center(
                                child: isShared
                                    ? const Icon(Icons.people, size: 14, color: Colors.white)
                                    : Text(
                                        '${cp.sequenceNumber}',
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

                  // נקודות ביניים (waypoints) — אייקון כוכב סגול
                  if (_showWaypoints && waypointIds.isNotEmpty)
                    MarkerLayer(
                      markers: _checkpoints
                          .where((cp) => waypointIds.contains(cp.id) && !cp.isPolygon && cp.coordinates != null)
                          .map((cp) {
                        return Marker(
                          point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                          width: 40,
                          height: 40,
                          child: Opacity(
                            opacity: _waypointsOpacity,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.purple,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.purple.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.star, size: 20, color: Colors.white),
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
                    id: 'waypoints', label: 'נקודות ביניים', color: Colors.purple,
                    visible: _showWaypoints,
                    onVisibilityChanged: (v) => setState(() => _showWaypoints = v),
                    opacity: _waypointsOpacity,
                    onOpacityChanged: (v) => setState(() => _waypointsOpacity = v),
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
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRoutePolylines() {
    List<Widget> polylines = [];

    for (final entry in widget.navigation.routes.entries) {
      final navigatorId = entry.key;
      final route = entry.value;

      // בדיקה אם המנווט נבחר
      if (_selectedNavigators[navigatorId] != true) continue;

      // בניית הציר המלא: התחלה → נקודות → סיום
      List<LatLng> points = [];

      if (_checkpoints.isEmpty) continue;

      // 1. נקודת התחלה (אם קיימת)
      if (route.startPointId != null) {
        try {
          final startPoint = _checkpoints.firstWhere(
            (cp) => cp.id == route.startPointId,
          );
          if (!startPoint.isPolygon && startPoint.coordinates != null) {
            points.add(LatLng(startPoint.coordinates!.lat, startPoint.coordinates!.lng));
          }
        } catch (_) {}
      }

      // 2. נקודות המנווט (לפי הרצף)
      for (final checkpointId in route.sequence) {
        try {
          final checkpoint = _checkpoints.firstWhere(
            (cp) => cp.id == checkpointId,
          );
          if (!checkpoint.isPolygon && checkpoint.coordinates != null) {
            points.add(LatLng(checkpoint.coordinates!.lat, checkpoint.coordinates!.lng));
          }
        } catch (_) {}
      }

      // 3. נקודת הסיום (אם קיימת ושונה מההתחלה)
      if (route.endPointId != null && route.endPointId != route.startPointId) {
        try {
          final endPoint = _checkpoints.firstWhere(
            (cp) => cp.id == route.endPointId,
          );
          if (!endPoint.isPolygon && endPoint.coordinates != null) {
            points.add(LatLng(endPoint.coordinates!.lat, endPoint.coordinates!.lng));
          }
        } catch (_) {}
      }

      if (points.isNotEmpty) {
        final color = _getRouteColor(route.status);
        polylines.add(
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 3,
                color: color.withValues(alpha: _routesOpacity),
              ),
            ],
          ),
        );
      }
    }

    return polylines;
  }
}
