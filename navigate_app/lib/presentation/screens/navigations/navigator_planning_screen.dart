import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/nav_layer.dart' as nav;
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../services/auth_service.dart';
import '../../widgets/map_with_selector.dart';

/// מסך תכנון למנווט (סטטוס learning)
class NavigatorPlanningScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const NavigatorPlanningScreen({
    super.key,
    required this.navigation,
  });

  @override
  State<NavigatorPlanningScreen> createState() => _NavigatorPlanningScreenState();
}

class _NavigatorPlanningScreenState extends State<NavigatorPlanningScreen> with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final AuthService _authService = AuthService();
  late TabController _tabController;

  List<Checkpoint> _myCheckpoints = [];
  List<String> _routeSequence = [];
  List<nav.NavBoundary> _boundaries = [];
  bool _isLoading = true;
  String? _navigatorId;

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
      final user = await _authService.getCurrentUser();
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('שגיאה: משתמש לא מחובר')),
          );
        }
        return;
      }

      _navigatorId = user.uid;

      final route = widget.navigation.routes[_navigatorId];
      if (route == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('לא נמצא ציר למנווט זה')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // טעינת גבולות גזרה (GG) של הניווט
      List<nav.NavBoundary> boundaries = [];
      try {
        boundaries = await _navLayerRepo.getBoundariesByNavigation(widget.navigation.id);
      } catch (e) {
        print('DEBUG: Error loading nav boundaries: $e');
      }

      // נסיון טעינת נקודות מהשכבות הניווטיות (nav_layers_nz) תחילה
      final List<Checkpoint> checkpoints = [];
      final navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(widget.navigation.id);

      if (navCheckpoints.isNotEmpty) {
        // מיפוי NavCheckpoints לפי sourceId וגם לפי id לחיפוש מהיר
        final navCheckpointBySourceId = <String, nav.NavCheckpoint>{};
        final navCheckpointById = <String, nav.NavCheckpoint>{};
        for (final ncp in navCheckpoints) {
          navCheckpointBySourceId[ncp.sourceId] = ncp;
          navCheckpointById[ncp.id] = ncp;
        }

        for (final id in route.checkpointIds) {
          // חיפוש לפי id ישירות, ואז לפי sourceId (תאימות לשני המקרים)
          final navCp = navCheckpointById[id] ?? navCheckpointBySourceId[id];
          if (navCp != null) {
            // המרת NavCheckpoint ל-Checkpoint לתאימות עם שאר הממשק
            checkpoints.add(Checkpoint(
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
            ));
          }
        }
      }

      // אם לא נמצאו נקודות ניווטיות, ננסה מהשכבה הגלובלית כ-fallback
      if (checkpoints.isEmpty) {
        for (final id in route.checkpointIds) {
          final cp = await _checkpointRepo.getById(id);
          if (cp != null) checkpoints.add(cp);
        }
      }

      setState(() {
        _myCheckpoints = checkpoints;
        _routeSequence = List.from(route.sequence);
        _boundaries = boundaries;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינה: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRoute() async {
    if (_navigatorId == null) return;

    try {
      final currentRoute = widget.navigation.routes[_navigatorId!]!;
      final updatedRoute = currentRoute.copyWith(sequence: _routeSequence);

      final updatedRoutes = Map<String, domain.AssignedRoute>.from(widget.navigation.routes);
      updatedRoutes[_navigatorId!] = updatedRoute;

      final updatedNavigation = widget.navigation.copyWith(
        routes: updatedRoutes,
        updatedAt: DateTime.now(),
      );

      await _navRepo.update(updatedNavigation);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הציר נשמר בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    }
  }

  /// חילוץ X מ-UTM (6 ספרות ראשונות)
  String _getUtmX(String utm) {
    if (utm.length >= 6) return utm.substring(0, 6);
    return utm;
  }

  /// חילוץ Y מ-UTM (6 ספרות אחרונות)
  String _getUtmY(String utm) {
    if (utm.length >= 12) return utm.substring(6, 12);
    if (utm.length > 6) return utm.substring(6);
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.navigation.name),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'טבלת נקודות'),
            Tab(icon: Icon(Icons.map), text: 'מפה'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveRoute,
            tooltip: 'שמור ציר',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCheckpointsTable(),
                _buildMap(),
              ],
            ),
    );
  }

  Widget _buildCheckpointsTable() {
    if (_myCheckpoints.isEmpty) {
      return const Center(child: Text('אין נקודות'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'הנקודות שלי',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Table(
                  border: TableBorder.all(color: Colors.grey[300]!),
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey[200]),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('מס\'', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('X (UTM)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('Y (UTM)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    ..._myCheckpoints.asMap().entries.map((entry) {
                      final index = entry.key + 1;
                      final checkpoint = entry.value;
                      final utmX = _getUtmX(checkpoint.coordinates.utm);
                      final utmY = _getUtmY(checkpoint.coordinates.utm);

                      return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(8.0), child: Text('$index', textAlign: TextAlign.center)),
                          Padding(padding: const EdgeInsets.all(8.0), child: Text(utmX, textAlign: TextAlign.center)),
                          Padding(padding: const EdgeInsets.all(8.0), child: Text(utmY, textAlign: TextAlign.center)),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('עבור למפה כדי לערוך את סדר הציר', style: TextStyle(color: Colors.blue[900])),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    if (_myCheckpoints.isEmpty && _boundaries.isEmpty) {
      return const Center(child: Text('אין נקודות להצגה'));
    }

    // חישוב מרכז המפה - מנקודות או מגבול
    LatLng center;
    if (_myCheckpoints.isNotEmpty) {
      center = LatLng(
        _myCheckpoints.map((c) => c.coordinates.lat).reduce((a, b) => a + b) / _myCheckpoints.length,
        _myCheckpoints.map((c) => c.coordinates.lng).reduce((a, b) => a + b) / _myCheckpoints.length,
      );
    } else if (_boundaries.isNotEmpty && _boundaries.first.coordinates.isNotEmpty) {
      final boundaryCoords = _boundaries.first.coordinates;
      center = LatLng(
        boundaryCoords.map((c) => c.lat).reduce((a, b) => a + b) / boundaryCoords.length,
        boundaryCoords.map((c) => c.lng).reduce((a, b) => a + b) / boundaryCoords.length,
      );
    } else {
      center = const LatLng(32.0853, 34.7818); // ברירת מחדל - תל אביב
    }

    final List<LatLng> routePoints = _myCheckpoints.isNotEmpty
        ? _routeSequence
            .map((id) => _myCheckpoints.firstWhere((c) => c.id == id, orElse: () => _myCheckpoints.first))
            .map((c) => LatLng(c.coordinates.lat, c.coordinates.lng))
            .toList()
        : [];

    return Stack(
      children: [
        MapWithTypeSelector(
          options: MapOptions(initialCenter: center, initialZoom: 14.0),
          layers: [
            // גבול גזרה (GG)
            if (_boundaries.isNotEmpty)
              PolygonLayer(
                polygons: _boundaries
                    .where((b) => b.coordinates.isNotEmpty)
                    .map((b) => Polygon(
                          points: b.coordinates
                              .map((coord) => LatLng(coord.lat, coord.lng))
                              .toList(),
                          color: Colors.black.withOpacity(0.1),
                          borderColor: Colors.black,
                          borderStrokeWidth: b.strokeWidth,
                          isFilled: true,
                        ))
                    .toList(),
              ),
            // קו הציר
            if (routePoints.length > 1)
              PolylineLayer(
                polylines: [Polyline(points: routePoints, color: Colors.blue, strokeWidth: 3.0)],
              ),
            // נקודות ציון
            MarkerLayer(
              markers: _myCheckpoints.asMap().entries.map((entry) {
                final index = entry.key + 1;
                final checkpoint = entry.value;
                return Marker(
                  point: LatLng(checkpoint.coordinates.lat, checkpoint.coordinates.lng),
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text('$index', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        Positioned(
          bottom: 16, left: 16, right: 16,
          child: Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('לעריכת הציר: גרור את הנקודות על המפה (בפיתוח)',
                  style: TextStyle(color: Colors.blue[900]), textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}
