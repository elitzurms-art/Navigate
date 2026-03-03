import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/nav_layer.dart' as nav;
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../core/utils/geometry_utils.dart';
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
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;
  List<Checkpoint> _checkpoints = [];
  Boundary? _boundary;
  Map<String, bool> _selectedNavigators = {};
  // _routeApprovals הוסר — סטטוס נגזר מ-approvalStatus ב-AssignedRoute
  bool _isLoading = false;
  bool _learningStarted = false;

  // שכבות ניווט
  List<nav.NavSafetyPoint> _safetyPoints = [];
  List<nav.NavCluster> _clusters = [];

  // בקרת שכבות
  bool _layerControlsExpanded = false;
  bool _showBoundary = true;
  bool _showSafetyPoints = true;
  bool _showClusters = true;
  double _boundaryOpacity = 1.0;
  double _safetyPointsOpacity = 1.0;
  double _clustersOpacity = 1.0;

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

      // טעינת שכבות ניווט
      List<nav.NavSafetyPoint> safetyPoints = [];
      try {
        safetyPoints = await _navLayerRepo.getSafetyPointsByNavigation(widget.navigation.id);
      } catch (e) {
        print('DEBUG: Error loading safety points: $e');
      }

      List<nav.NavCluster> clusters = [];
      try {
        clusters = await _navLayerRepo.getClustersByNavigation(widget.navigation.id);
      } catch (e) {
        print('DEBUG: Error loading clusters: $e');
      }

      setState(() {
        _checkpoints = checkpoints;
        _boundary = boundary;
        _safetyPoints = safetyPoints;
        _clusters = clusters;
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

  /// טעינת הניווט העדכני מה-DB
  Future<void> _reloadNavigationFromDb() async {
    try {
      final fresh = await _navRepo.getById(widget.navigation.id);
      if (fresh != null && mounted) {
        setState(() {
          _currentNavigation = fresh;
        });
      }
    } catch (_) {}
  }

  Future<void> _approveRoute(String navigatorId) async {
    final route = _currentNavigation.routes[navigatorId];
    if (route == null || route.approvalStatus != 'pending_approval') return;

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
      final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
      updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(approvalStatus: 'approved');
      final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
      await _navRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);

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
    final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
    updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(approvalStatus: 'not_submitted');
    final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
    await _navRepo.update(updatedNav);
    setState(() => _currentNavigation = updatedNav);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הציר של $navigatorId נדחה - דורש תיקון'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _viewNavigatorRoute(String navigatorId) {
    final route = _currentNavigation.routes[navigatorId];
    if (route == null) return;

    showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => _RouteViewDialog(
        navigatorId: navigatorId,
        route: route,
        checkpoints: _checkpoints,
        boundary: _boundary,
        safetyPoints: _safetyPoints,
      ),
    );
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
    final allApproved = _currentNavigation.routes.values.every((r) => r.isApproved);

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

  Future<void> _showRejectRouteDialog(String navigatorId) async {
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('פסילת ציר — $navigatorId'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('הערות ותיקונים:'),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 4,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'פרט את הסיבה לפסילת הציר והתיקונים הנדרשים...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: notesController.text.trim().isNotEmpty
                  ? () => Navigator.pop(context, true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('שלח פסילה'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final updatedRoutes = Map<String, domain.AssignedRoute>.from(_currentNavigation.routes);
      updatedRoutes[navigatorId] = updatedRoutes[navigatorId]!.copyWith(
        approvalStatus: 'rejected',
        rejectionNotes: notesController.text.trim(),
      );
      final updatedNav = _currentNavigation.copyWith(routes: updatedRoutes, updatedAt: DateTime.now());
      await _navRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הציר של $navigatorId נפסל — המנווט יקבל הודעה'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    notesController.dispose();
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // הלמידה תמשיך לרוץ ברקע — רק כפתור "סיום למידה" משנה סטטוס
        // Back button לא עושה כלום מלבד לצאת מהמסך
      },
      child: Scaffold(
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
      ),
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
          ..._currentNavigation.routes.entries.map((entry) {
            final navigatorId = entry.key;
            final route = entry.value;

            return _buildRouteCard(navigatorId, route);
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
            _buildLegendItem('לא הוגש', Colors.grey),
            _buildLegendItem('ממתין לאישור', Colors.orange),
            _buildLegendItem('מאושר', Colors.green),
            _buildLegendItem('נפסל', Colors.red),
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

  Widget _buildRouteCard(String navigatorId, domain.AssignedRoute route) {
    final approvalStatus = route.approvalStatus;

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;
    switch (approvalStatus) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'מאושר';
        break;
      case 'pending_approval':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        statusText = 'ממתין לאישור';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.block;
        statusText = 'נפסל';
        break;
      default: // not_submitted
        statusColor = Colors.grey;
        statusIcon = Icons.radio_button_unchecked;
        statusText = 'לא הוגש';
    }

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
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
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
                  'אורך ציר: ${_calculateRouteLengthKm(route).toStringAsFixed(2)} ק"מ',
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

            // הערות פסילה — אם הציר נפסל
            if (route.approvalStatus == 'rejected' && route.rejectionNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        route.rejectionNotes,
                        style: TextStyle(color: Colors.red[700], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // כפתורי פעולה - רק למפקדים
            if (widget.isCommander) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  // כפתור אישור — פעיל רק אם pending_approval
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: approvalStatus == 'pending_approval'
                          ? () => _approveRoute(navigatorId)
                          : null,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('אשר ציר'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                    ),
                  ),
                  if (approvalStatus == 'approved') ...[
                    const SizedBox(width: 8),
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
                  // כפתור פסילת ציר — ספציפי למנווט
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRejectRouteDialog(navigatorId),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('פסילת ציר'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _viewNavigatorRoute(navigatorId),
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('צפה בציר'),
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

  /// איסוף כל נקודות הציון המחולקות למנווטים
  Set<String> _collectDistributedCheckpointIds() {
    final Set<String> ids = {};
    for (final route in _currentNavigation.routes.values) {
      ids.addAll(route.checkpointIds);
      if (route.startPointId != null) ids.add(route.startPointId!);
      if (route.endPointId != null) ids.add(route.endPointId!);
    }
    // נקודות ביניים
    if (_currentNavigation.waypointSettings.enabled) {
      for (final wp in _currentNavigation.waypointSettings.waypoints) {
        ids.add(wp.checkpointId);
      }
    }
    return ids;
  }

  Widget _buildMapView() {
    final distributedIds = _collectDistributedCheckpointIds();

    // איסוף נקודות התחלה/סיום לסימון מיוחד
    final Set<String> startPointIds = {};
    final Set<String> endPointIds = {};
    for (final route in _currentNavigation.routes.values) {
      if (route.startPointId != null) startPointIds.add(route.startPointId!);
      if (route.endPointId != null) endPointIds.add(route.endPointId!);
    }

    // איסוף נקודות ביניים
    final Set<String> waypointIds = {};
    if (_currentNavigation.waypointSettings.enabled) {
      for (final wp in _currentNavigation.waypointSettings.waypoints) {
        waypointIds.add(wp.checkpointId);
      }
    }

    // סינון נקודות ציון מחולקות
    final distributedCheckpoints = _checkpoints.where(
      (cp) => distributedIds.contains(cp.id),
    ).toList();

    return Column(
      children: [
        // בורר מנווטים
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _currentNavigation.routes.entries.map((entry) {
                final navigatorId = entry.key;
                final approvalStatus = entry.value.approvalStatus;
                final Color chipColor;
                final IconData chipIcon;
                switch (approvalStatus) {
                  case 'approved':
                    chipColor = Colors.green;
                    chipIcon = Icons.check_circle;
                    break;
                  case 'pending_approval':
                    chipColor = Colors.orange;
                    chipIcon = Icons.hourglass_top;
                    break;
                  case 'rejected':
                    chipColor = Colors.red;
                    chipIcon = Icons.block;
                    break;
                  default:
                    chipColor = Colors.grey;
                    chipIcon = Icons.radio_button_unchecked;
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(navigatorId),
                        const SizedBox(width: 6),
                        Icon(chipIcon, size: 14, color: chipColor),
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
          child: Stack(
            children: [
              MapWithTypeSelector(
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
                  // גבול גזרה (גג) — שחור
                  if (_showBoundary && _boundary != null && _boundary!.coordinates.isNotEmpty)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _boundary!.coordinates
                              .map((coord) => LatLng(coord.lat, coord.lng))
                              .toList(),
                          color: Colors.black.withOpacity(0.1 * _boundaryOpacity),
                          borderColor: Colors.black.withOpacity(_boundaryOpacity),
                          borderStrokeWidth: 2,
                          isFilled: true,
                        ),
                      ],
                    ),

                  // שכבת ב"א (clusters)
                  if (_showClusters && _clusters.isNotEmpty)
                    PolygonLayer(
                      polygons: _clusters.map((cluster) {
                        final Color clusterColor = _parseColor(cluster.color);
                        return Polygon(
                          points: cluster.coordinates
                              .map((coord) => LatLng(coord.lat, coord.lng))
                              .toList(),
                          color: clusterColor.withOpacity(cluster.fillOpacity * _clustersOpacity),
                          borderColor: clusterColor.withOpacity(_clustersOpacity),
                          borderStrokeWidth: cluster.strokeWidth,
                          isFilled: true,
                        );
                      }).toList(),
                    ),

                  // שכבת נת"ב - פוליגונים
                  if (_showSafetyPoints)
                    ..._buildSafetyPointPolygonLayers(),

                  // צירי המנווטים
                  ..._buildRoutePolylines(),

                  // נקודות ציון מחולקות
                  MarkerLayer(
                    markers: distributedCheckpoints.map((cp) {
                      final bool isStart = startPointIds.contains(cp.id);
                      final bool isEnd = endPointIds.contains(cp.id);
                      final bool isWaypoint = waypointIds.contains(cp.id);

                      final Color markerColor;
                      final IconData markerIcon;
                      if (isStart) {
                        markerColor = Colors.green;
                        markerIcon = Icons.flag;
                      } else if (isEnd) {
                        markerColor = Colors.red;
                        markerIcon = Icons.flag;
                      } else if (isWaypoint) {
                        markerColor = Colors.purple;
                        markerIcon = Icons.diamond;
                      } else {
                        markerColor = Colors.blue;
                        markerIcon = Icons.place;
                      }

                      return Marker(
                        point: LatLng(cp.coordinates.lat, cp.coordinates.lng),
                        width: 40,
                        height: 40,
                        child: Column(
                          children: [
                            Icon(
                              markerIcon,
                              color: markerColor,
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

                  // שכבת נת"ב - נקודות
                  if (_showSafetyPoints)
                    ..._buildSafetyPointMarkerLayers(),
                ],
              ),

              // בקרת שכבות
              Positioned(
                top: 8,
                left: 8,
                child: _buildLayerControls(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// בניית שכבות פוליגון של נקודות בטיחות
  List<Widget> _buildSafetyPointPolygonLayers() {
    final polygonPoints = _safetyPoints
        .where((sp) => sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.isNotEmpty)
        .toList();

    if (polygonPoints.isEmpty) return [];

    return [
      PolygonLayer(
        polygons: polygonPoints.map((sp) {
          final Color severityColor = _getSeverityColor(sp.severity);
          return Polygon(
            points: sp.polygonCoordinates!
                .map((coord) => LatLng(coord.lat, coord.lng))
                .toList(),
            color: severityColor.withOpacity(0.2 * _safetyPointsOpacity),
            borderColor: severityColor.withOpacity(_safetyPointsOpacity),
            borderStrokeWidth: 2,
            isFilled: true,
          );
        }).toList(),
      ),
    ];
  }

  /// בניית שכבת סמנים של נקודות בטיחות
  List<Widget> _buildSafetyPointMarkerLayers() {
    final pointSafetyPoints = _safetyPoints
        .where((sp) => sp.type == 'point' && sp.coordinates != null)
        .toList();

    if (pointSafetyPoints.isEmpty) return [];

    return [
      MarkerLayer(
        markers: pointSafetyPoints.map((sp) {
          final Color severityColor = _getSeverityColor(sp.severity);
          return Marker(
            point: LatLng(sp.coordinates!.lat, sp.coordinates!.lng),
            width: 36,
            height: 36,
            child: Opacity(
              opacity: _safetyPointsOpacity,
              child: Icon(
                Icons.warning_rounded,
                color: severityColor,
                size: 32,
              ),
            ),
          );
        }).toList(),
      ),
    ];
  }

  /// בקרת שכבות (overlay בצד שמאל-עליון של המפה) — מתכווץ/מתרחב
  Widget _buildLayerControls() {
    if (!_layerControlsExpanded) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.white.withValues(alpha: 0.9),
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
      color: Colors.white.withValues(alpha: 0.95),
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
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ג"ג
                  _buildLayerToggle(
                    label: 'ג"ג',
                    value: _showBoundary,
                    opacity: _boundaryOpacity,
                    color: Colors.black,
                    onToggle: (v) => setState(() => _showBoundary = v),
                    onOpacity: (v) => setState(() => _boundaryOpacity = v),
                  ),
                  // נת"ב
                  _buildLayerToggle(
                    label: 'נת"ב',
                    value: _showSafetyPoints,
                    opacity: _safetyPointsOpacity,
                    color: Colors.red,
                    onToggle: (v) => setState(() => _showSafetyPoints = v),
                    onOpacity: (v) => setState(() => _safetyPointsOpacity = v),
                  ),
                  // ב"א
                  _buildLayerToggle(
                    label: 'ב"א',
                    value: _showClusters,
                    opacity: _clustersOpacity,
                    color: Colors.green,
                    onToggle: (v) => setState(() => _showClusters = v),
                    onOpacity: (v) => setState(() => _clustersOpacity = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerToggle({
    required String label,
    required bool value,
    required double opacity,
    required Color color,
    required ValueChanged<bool> onToggle,
    required ValueChanged<double> onOpacity,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                activeColor: color,
                onChanged: (v) => onToggle(v ?? false),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
        if (value)
          SizedBox(
            height: 24,
            child: Slider(
              value: opacity,
              min: 0.1,
              max: 1.0,
              activeColor: color,
              onChanged: onOpacity,
            ),
          ),
      ],
    );
  }

  /// חישוב אורך ציר — מ-plannedPath אם נערך, אחרת routeLengthKm המקורי
  double _calculateRouteLengthKm(domain.AssignedRoute route) {
    if (route.plannedPath.isNotEmpty) {
      return GeometryUtils.calculatePathLengthKm(route.plannedPath);
    }
    return route.routeLengthKm;
  }

  Color _parseColor(String colorStr) {
    switch (colorStr.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'yellow':
        return Colors.yellow;
      case 'purple':
        return Colors.purple;
      case 'black':
        return Colors.black;
      case 'brown':
        return Colors.brown;
      default:
        // ניסיון לפרסר hex color
        if (colorStr.startsWith('#') && colorStr.length == 7) {
          try {
            return Color(int.parse('FF${colorStr.substring(1)}', radix: 16));
          } catch (_) {}
        }
        return Colors.green;
    }
  }

  Color _getSeverityColor(String severity) {
    // כל הנת"ב מוצגים באדום למפקד
    return Colors.red;
  }

  List<Widget> _buildRoutePolylines() {
    List<Widget> polylines = [];

    for (final entry in _currentNavigation.routes.entries) {
      final navigatorId = entry.key;
      final route = entry.value;

      if (_selectedNavigators[navigatorId] != true) continue;

      // צבע לפי סטטוס אישור — 4 מצבים
      final Color color;
      switch (route.approvalStatus) {
        case 'approved':
          color = Colors.green;
          break;
        case 'pending_approval':
          color = Colors.orange;
          break;
        case 'rejected':
          color = Colors.red;
          break;
        default:
          color = Colors.grey;
      }

      // בניית הציר — אם המנווט ערך (plannedPath), מציגים את הציר המעודכן
      List<LatLng> points = [];

      if (route.plannedPath.isNotEmpty) {
        // ציר עדכני שהמנווט ערך
        points = route.plannedPath.map((c) => c.toLatLng()).toList();
      } else {
        // ציר מקורי מנקודות ציון
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
      }

      if (points.isNotEmpty) {
        polylines.add(
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: route.approvalStatus == 'approved' ? 4 : 3,
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

/// דיאלוג מסך מלא לצפייה בציר מנווט
class _RouteViewDialog extends StatefulWidget {
  final String navigatorId;
  final domain.AssignedRoute route;
  final List<Checkpoint> checkpoints;
  final Boundary? boundary;
  final List<nav.NavSafetyPoint> safetyPoints;

  const _RouteViewDialog({
    required this.navigatorId,
    required this.route,
    required this.checkpoints,
    this.boundary,
    this.safetyPoints = const [],
  });

  @override
  State<_RouteViewDialog> createState() => _RouteViewDialogState();
}

class _RouteViewDialogState extends State<_RouteViewDialog> {
  // בקרת שכבות
  bool _layerControlsExpanded = false;
  bool _showRoute = true;
  bool _showBoundary = true;
  bool _showSafetyPoints = true;
  double _routeOpacity = 1.0;
  double _boundaryOpacity = 1.0;
  double _safetyPointsOpacity = 1.0;

  @override
  Widget build(BuildContext context) {
    // בניית נקודות הציר — עדיפות לציר ערוך (plannedPath)
    List<LatLng> routePoints = [];

    Checkpoint? startCheckpoint;
    Checkpoint? endCheckpoint;
    List<Checkpoint> sequenceCheckpoints = [];

    if (widget.route.plannedPath.isNotEmpty) {
      // ציר עדכני שהמנווט ערך
      routePoints = widget.route.plannedPath.map((c) => c.toLatLng()).toList();
    } else {
      // ציר מקורי מנקודות ציון
      if (widget.route.startPointId != null) {
        try {
          startCheckpoint = widget.checkpoints.firstWhere((cp) => cp.id == widget.route.startPointId);
          routePoints.add(LatLng(startCheckpoint.coordinates.lat, startCheckpoint.coordinates.lng));
        } catch (_) {}
      }

      for (final cpId in widget.route.sequence) {
        try {
          final cp = widget.checkpoints.firstWhere((c) => c.id == cpId);
          sequenceCheckpoints.add(cp);
          routePoints.add(LatLng(cp.coordinates.lat, cp.coordinates.lng));
        } catch (_) {}
      }

      if (widget.route.endPointId != null && widget.route.endPointId != widget.route.startPointId) {
        try {
          endCheckpoint = widget.checkpoints.firstWhere((cp) => cp.id == widget.route.endPointId);
          routePoints.add(LatLng(endCheckpoint.coordinates.lat, endCheckpoint.coordinates.lng));
        } catch (_) {}
      }
    }

    // נקודות ציון לסמנים — תמיד מהרצף המקורי
    if (startCheckpoint == null && widget.route.startPointId != null) {
      try {
        startCheckpoint = widget.checkpoints.firstWhere((cp) => cp.id == widget.route.startPointId);
      } catch (_) {}
    }
    if (endCheckpoint == null && widget.route.endPointId != null && widget.route.endPointId != widget.route.startPointId) {
      try {
        endCheckpoint = widget.checkpoints.firstWhere((cp) => cp.id == widget.route.endPointId);
      } catch (_) {}
    }
    if (sequenceCheckpoints.isEmpty) {
      for (final cpId in widget.route.sequence) {
        try {
          final cp = widget.checkpoints.firstWhere((c) => c.id == cpId);
          sequenceCheckpoints.add(cp);
        } catch (_) {}
      }
    }

    // חישוב מרכז הציר
    LatLng center = const LatLng(32.0853, 34.7818);
    if (routePoints.isNotEmpty) {
      double avgLat = 0, avgLng = 0;
      for (final p in routePoints) {
        avgLat += p.latitude;
        avgLng += p.longitude;
      }
      center = LatLng(avgLat / routePoints.length, avgLng / routePoints.length);
    }

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('ציר של ${widget.navigatorId}'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Stack(
          children: [
            MapWithTypeSelector(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14.0,
              ),
              layers: [
                // גבול גזרה (גג) — שחור
                if (_showBoundary && widget.boundary != null && widget.boundary!.coordinates.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: widget.boundary!.coordinates
                            .map((coord) => LatLng(coord.lat, coord.lng))
                            .toList(),
                        color: Colors.black.withOpacity(0.1 * _boundaryOpacity),
                        borderColor: Colors.black.withOpacity(_boundaryOpacity),
                        borderStrokeWidth: 2,
                        isFilled: true,
                      ),
                    ],
                  ),

                // שכבת נת"ב — פוליגונים באדום
                if (_showSafetyPoints)
                  ..._buildSafetyPointLayers(),

                // קו הציר — כחול
                if (_showRoute && routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 4,
                        color: Colors.blue.withOpacity(_routeOpacity),
                      ),
                    ],
                  ),

                // סמני נקודות
                if (_showRoute)
                  MarkerLayer(
                    markers: [
                      // נקודת התחלה
                      if (startCheckpoint != null)
                        Marker(
                          point: LatLng(startCheckpoint.coordinates.lat, startCheckpoint.coordinates.lng),
                          width: 44,
                          height: 44,
                          child: Opacity(
                            opacity: _routeOpacity,
                            child: const Column(
                              children: [
                                Icon(Icons.flag, color: Colors.green, size: 34),
                                Text('התחלה', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),

                      // נקודות הרצף עם מספרי סדר
                      ...sequenceCheckpoints.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final cp = entry.value;
                        return Marker(
                          point: LatLng(cp.coordinates.lat, cp.coordinates.lng),
                          width: 40,
                          height: 40,
                          child: Opacity(
                            opacity: _routeOpacity,
                            child: Column(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${idx + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  cp.name,
                                  style: const TextStyle(fontSize: 8),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      // נקודת סיום
                      if (endCheckpoint != null)
                        Marker(
                          point: LatLng(endCheckpoint.coordinates.lat, endCheckpoint.coordinates.lng),
                          width: 44,
                          height: 44,
                          child: Opacity(
                            opacity: _routeOpacity,
                            child: const Column(
                              children: [
                                Icon(Icons.flag, color: Colors.red, size: 34),
                                Text('סיום', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),

            // בקרת שכבות
            Positioned(
              top: 8,
              left: 8,
              child: _buildDialogLayerControls(),
            ),
          ],
        ),
      ),
    );
  }

  /// בניית שכבות נת"ב באדום
  List<Widget> _buildSafetyPointLayers() {
    final List<Widget> layers = [];

    // פוליגונים
    final polygonPoints = widget.safetyPoints
        .where((sp) => sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.isNotEmpty)
        .toList();

    if (polygonPoints.isNotEmpty) {
      layers.add(
        PolygonLayer(
          polygons: polygonPoints.map((sp) {
            return Polygon(
              points: sp.polygonCoordinates!
                  .map((coord) => LatLng(coord.lat, coord.lng))
                  .toList(),
              color: Colors.red.withOpacity(0.2 * _safetyPointsOpacity),
              borderColor: Colors.red.withOpacity(_safetyPointsOpacity),
              borderStrokeWidth: 2,
              isFilled: true,
            );
          }).toList(),
        ),
      );
    }

    // נקודות
    final pointSafetyPoints = widget.safetyPoints
        .where((sp) => sp.type == 'point' && sp.coordinates != null)
        .toList();

    if (pointSafetyPoints.isNotEmpty) {
      layers.add(
        MarkerLayer(
          markers: pointSafetyPoints.map((sp) {
            return Marker(
              point: LatLng(sp.coordinates!.lat, sp.coordinates!.lng),
              width: 36,
              height: 36,
              child: Opacity(
                opacity: _safetyPointsOpacity,
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 32,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    return layers;
  }

  /// בקרת שכבות בדיאלוג — מתכווץ/מתרחב
  Widget _buildDialogLayerControls() {
    if (!_layerControlsExpanded) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.white.withValues(alpha: 0.9),
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
      color: Colors.white.withValues(alpha: 0.95),
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
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ציר
                  _buildToggle(
                    label: 'ציר',
                    value: _showRoute,
                    opacity: _routeOpacity,
                    color: Colors.blue,
                    onToggle: (v) => setState(() => _showRoute = v),
                    onOpacity: (v) => setState(() => _routeOpacity = v),
                  ),
                  // ג"ג
                  _buildToggle(
                    label: 'ג"ג',
                    value: _showBoundary,
                    opacity: _boundaryOpacity,
                    color: Colors.black,
                    onToggle: (v) => setState(() => _showBoundary = v),
                    onOpacity: (v) => setState(() => _boundaryOpacity = v),
                  ),
                  // נת"ב
                  _buildToggle(
                    label: 'נת"ב',
                    value: _showSafetyPoints,
                    opacity: _safetyPointsOpacity,
                    color: Colors.red,
                    onToggle: (v) => setState(() => _showSafetyPoints = v),
                    onOpacity: (v) => setState(() => _safetyPointsOpacity = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required double opacity,
    required Color color,
    required ValueChanged<bool> onToggle,
    required ValueChanged<double> onOpacity,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                activeColor: color,
                onChanged: (v) => onToggle(v ?? false),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
        if (value)
          SizedBox(
            height: 24,
            child: Slider(
              value: opacity,
              min: 0.1,
              max: 1.0,
              activeColor: color,
              onChanged: onOpacity,
            ),
          ),
      ],
    );
  }
}
