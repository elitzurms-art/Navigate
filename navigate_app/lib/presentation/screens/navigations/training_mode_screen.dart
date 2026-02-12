import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../core/utils/geometry_utils.dart';
import 'routes_edit_screen.dart';
import '../../widgets/map_with_selector.dart';

/// מסך מצב למידה לניווט
class TrainingModeScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool isCommander; // האם המשתמש הנוכחי הוא מפקד

  const TrainingModeScreen({
    super.key,
    required this.navigation,
    this.isCommander = true, // ברירת מחדל למפקד (נשנה לפי הרשאות)
  });

  @override
  State<TrainingModeScreen> createState() => _TrainingModeScreenState();
}

class _TrainingModeScreenState extends State<TrainingModeScreen> with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;
  List<Checkpoint> _checkpoints = [];
  Boundary? _boundary;
  Map<String, bool> _selectedNavigators = {};
  Map<String, bool> _routeApprovals = {}; // סטטוס אישור לכל ציר
  bool _isLoading = false;
  bool _learningStarted = false;

  // עותק מקומי של הניווט שנשמר ומתעדכן עם כל שינוי
  late domain.Navigation _currentNavigation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentNavigation = widget.navigation;
    _learningStarted = widget.navigation.status == 'learning';
    _loadData();
    _reloadNavigationFromDb();

    // אתחול בחירת מנווטים וסטטוסי אישור מהאובייקט שהתקבל
    for (final navigatorId in widget.navigation.routes.keys) {
      _selectedNavigators[navigatorId] = true;
      _routeApprovals[navigatorId] = widget.navigation.routes[navigatorId]?.isApproved ?? false;
    }
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

      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
      }

      setState(() {
        _checkpoints = checkpoints;
        _boundary = boundary;
        _isLoading = false;
      });

      // התמקד במרכז הגבול — דחייה עד שהמפה נבנית
      if (boundary != null && boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(LatLng(center.lat, center.lng), 13.0);
          } catch (_) {
            // MapController עדיין לא מאותחל — נתעלם
          }
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינה: $e')),
        );
      }
    }
  }

  /// טעינת הניווט העדכני מה-DB — מחזירה אישורים שנשמרו קודם
  Future<void> _reloadNavigationFromDb() async {
    try {
      final fresh = await _navRepo.getById(widget.navigation.id);
      if (fresh != null && mounted) {
        setState(() {
          _currentNavigation = fresh;
          for (final navigatorId in fresh.routes.keys) {
            _routeApprovals[navigatorId] = fresh.routes[navigatorId]?.isApproved ?? false;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _approveRoute(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אישור ציר'),
        content: Text('האם לאשר את הציר של $navigatorId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('אשר'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _routeApprovals[navigatorId] = true;
      });

      // שמירת סטטוס האישור ב-database — שימוש ב-_currentNavigation כדי לא לאבד אישורים קודמים
      final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
      updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(isApproved: true);
      final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
      await _navRepo.update(updatedNav);
      _currentNavigation = updatedNav;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הציר של $navigatorId אושר'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _rejectRoute(String navigatorId) async {
    setState(() {
      _routeApprovals[navigatorId] = false;
    });

    // שמירת סטטוס הדחייה ב-database
    final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
    updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(isApproved: false);
    final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
    await _navRepo.update(updatedNav);
    _currentNavigation = updatedNav;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הציר של $navigatorId נדחה - דורש תיקון'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _editNavigatorRoute(String navigatorId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoutesEditScreen(navigation: _currentNavigation),
      ),
    ).then((updated) async {
      if (updated == true) {
        // הציר נערך - ביטול אישור
        setState(() {
          _routeApprovals[navigatorId] = false;
        });

        // טעינה מחדש מה-DB כדי לקבל את הציר המעודכן
        await _reloadNavigationFromDb();
        // עדכון ביטול האישור
        final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
        updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(isApproved: false);
        final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
        await _navRepo.update(updatedNav);
        _currentNavigation = updatedNav;

        _loadData();
      }
    });
  }

  Future<void> _startLearning() async {
    final updatedNav = _currentNavigation.copyWith(
      status: 'learning',
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNav);
    _currentNavigation = updatedNav;

    if (mounted) {
      setState(() => _learningStarted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('מצב למידה הופעל — המנווטים יראו את המסך שלהם'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _finishLearning() async {
    final allApproved = _routeApprovals.values.every((v) => v);

    if (!allApproved) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('לא כל הצירים אושרו'),
          content: const Text('חלק מהצירים עדיין לא אושרו. האם ברצונך לסיים את הלמידה בכל זאת?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('סיים בכל זאת'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // עדכון הניווט - סימון שהלמידה הסתיימה + החזרת סטטוס להכנה
    final updatedNav = _currentNavigation.copyWith(
      status: 'preparation',
      trainingStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNav);
    _currentNavigation = updatedNav;

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteNavigation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת ניווט'),
        content: const Text('פעולה זו בלתי הפיכה!\nכל נתוני הניווט יימחקו לצמיתות.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _navRepo.delete(_currentNavigation.id);
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            Text(
              'מצב למידה',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (widget.isCommander)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'מחיקת ניווט',
              onPressed: _deleteNavigation,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.table_chart), text: 'טבלה'),
            Tab(icon: Icon(Icons.map), text: 'מפה'),
          ],
        ),
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
      bottomNavigationBar: widget.isCommander
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // כפתור התחלת למידה
                    ElevatedButton.icon(
                      onPressed: _learningStarted ? null : _startLearning,
                      icon: Icon(_learningStarted ? Icons.check : Icons.play_arrow),
                      label: Text(
                        _learningStarted ? 'למידה פעילה' : 'התחלת למידה',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _learningStarted ? Colors.grey : Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // כפתור סיום למידה
                    ElevatedButton.icon(
                      onPressed: _learningStarted ? _finishLearning : null,
                      icon: const Icon(Icons.check_circle),
                      label: const Text(
                        'סיום למידה',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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

  Widget _buildTableView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת
          Row(
            children: [
              Icon(Icons.school, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                'צירי מנווטים - מצב למידה',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'המנווטים עורכים את הצירים. מפקדים יכולים לאשר או לדחות.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // מקרא
          if (widget.isCommander) _buildLegend(),
          const SizedBox(height: 16),

          // טבלת צירים
          ...widget.navigation.routes.entries.map((entry) {
            final navigatorId = entry.key;
            final route = entry.value;
            final isApproved = _routeApprovals[navigatorId] ?? false;

            return _buildRouteCard(navigatorId, route, isApproved);
          }),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Card(
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildLegendItem('ממתין לאישור', Colors.orange),
            _buildLegendItem('מאושר', Colors.green),
            _buildLegendItem('דורש תיקון', Colors.red),
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
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildRouteCard(String navigatorId, domain.AssignedRoute route, bool isApproved) {
    final statusColor = isApproved ? Colors.green : Colors.orange;
    final statusText = isApproved ? 'מאושר' : 'ממתין לאישור';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // שורה עליונה: מנווט + סטטוס
            Row(
              children: [
                Expanded(
                  child: Text(
                    navigatorId,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isApproved ? Icons.check_circle : Icons.pending,
                        size: 16,
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // פרטי הציר
            Row(
              children: [
                Icon(Icons.route, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'אורך ציר: ${route.routeLengthKm.toStringAsFixed(2)} ק"מ',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(width: 16),
                Icon(Icons.place, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${route.sequence.length} נקודות',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),

            // כפתורי פעולה - רק למפקדים
            if (widget.isCommander) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (!isApproved)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _approveRoute(navigatorId),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('אשר ציר'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                        ),
                      ),
                    ),
                  if (isApproved) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rejectRoute(navigatorId),
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('בטל אישור'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editNavigatorRoute(navigatorId),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('ערוך'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
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
                final isApproved = _routeApprovals[navigatorId] ?? false;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(navigatorId),
                        const SizedBox(width: 6),
                        Icon(
                          isApproved ? Icons.check_circle : Icons.pending,
                          size: 14,
                          color: isApproved ? Colors.green : Colors.orange,
                        ),
                      ],
                    ),
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
          child: MapWithTypeSelector(
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
            ),
            layers: [
              // גבול גזרה
              if (_boundary != null && _boundary!.coordinates.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _boundary!.coordinates
                          .map((coord) => LatLng(coord.lat, coord.lng))
                          .toList(),
                      color: Colors.blue.withOpacity(0.2),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                      isFilled: true,
                    ),
                  ],
                ),

              // צירי המנווטים
              ..._buildRoutePolylines(),

              // נקודות ציון
              MarkerLayer(
                markers: (_boundary != null && _boundary!.coordinates.isNotEmpty
                        ? GeometryUtils.filterPointsInPolygon(
                            points: _checkpoints,
                            getCoordinate: (cp) => cp.coordinates,
                            polygon: _boundary!.coordinates,
                          )
                        : _checkpoints)
                    .map((cp) {
                  return Marker(
                    point: LatLng(cp.coordinates.lat, cp.coordinates.lng),
                    width: 40,
                    height: 40,
                    child: Column(
                      children: [
                        Icon(
                          Icons.place,
                          color: Colors.blue,
                          size: 32,
                        ),
                        Text(
                          '${cp.sequenceNumber}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
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

      if (_selectedNavigators[navigatorId] != true) continue;

      // צבע לפי סטטוס אישור
      final isApproved = _routeApprovals[navigatorId] ?? false;
      final color = isApproved ? Colors.green : Colors.orange;

      // בניית הציר המלא
      List<LatLng> points = [];

      // נקודת התחלה
      if (route.startPointId != null) {
        final startPoint = _checkpoints.firstWhere(
          (cp) => cp.id == route.startPointId,
          orElse: () => _checkpoints.first,
        );
        points.add(LatLng(startPoint.coordinates.lat, startPoint.coordinates.lng));
      }

      // נקודות המנווט
      for (final checkpointId in route.sequence) {
        final checkpoint = _checkpoints.firstWhere(
          (cp) => cp.id == checkpointId,
          orElse: () => _checkpoints.first,
        );
        points.add(LatLng(checkpoint.coordinates.lat, checkpoint.coordinates.lng));
      }

      // נקודת הסיום
      if (route.endPointId != null && route.endPointId != route.startPointId) {
        final endPoint = _checkpoints.firstWhere(
          (cp) => cp.id == route.endPointId,
          orElse: () => _checkpoints.last,
        );
        points.add(LatLng(endPoint.coordinates.lat, endPoint.coordinates.lng));
      }

      if (points.isNotEmpty) {
        polylines.add(
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: isApproved ? 4 : 3,
                color: color,
              ),
            ],
          ),
        );
      }
    }

    return polylines;
  }
}
