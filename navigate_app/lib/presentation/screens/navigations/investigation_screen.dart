import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/navigation_score.dart';
import '../../../domain/entities/boundary.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../services/gps_tracking_service.dart';
import '../../../services/scoring_service.dart';
import '../../../services/auth_service.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../domain/entities/safety_point.dart';

/// מסך תחקור ניווט (למידה מניווטים קודמים)
class InvestigationScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final String? navigatorId; // null = כל המנווטים
  final bool isNavigator;

  const InvestigationScreen({
    super.key,
    required this.navigation,
    this.navigatorId,
    this.isNavigator = false,
  });

  @override
  State<InvestigationScreen> createState() => _InvestigationScreenState();
}

class _InvestigationScreenState extends State<InvestigationScreen>
    with SingleTickerProviderStateMixin {
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final MapController _mapController = MapController();

  late TabController _tabController;

  List<Checkpoint> _checkpoints = [];
  Boundary? _boundary;
  List<SafetyPoint> _safetyPoints = [];
  bool _isLoading = false;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = false;
  bool _showRoutes = true;
  bool _showPunches = true;

  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _routesOpacity = 1.0;
  double _punchesOpacity = 1.0;

  late domain.Navigation _currentNavigation;

  // נתוני תחקור (סימולציה - בפועל יטען מDB)
  Map<String, NavigatorInvestigationData> _navigatorData = {};
  String? _selectedNavigatorId;

  // למנווט
  final AuthService _authService = AuthService();
  final ScoringService _scoringService = ScoringService();
  List<Checkpoint> _myCheckpoints = [];
  List<LatLng> _plannedRoute = [];
  List<LatLng> _actualRoute = [];
  NavigationScore? _myScore;

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    if (!widget.isNavigator) {
      _tabController = TabController(length: 3, vsync: this);
    }
    _loadData();
    if (!widget.isNavigator) {
      _initializeInvestigationData();
    } else {
      _loadNavigatorData();
    }
  }

  Future<void> _loadNavigatorData() async {
    setState(() => _isLoading = true);

    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;

      final route = widget.navigation.routes[user.uid];
      if (route == null) return;

      // טעינת הנקודות אחד אחד
      final List<Checkpoint> checkpoints = [];
      for (final id in route.checkpointIds) {
        final cp = await _checkpointRepo.getById(id);
        if (cp != null) checkpoints.add(cp);
      }

      // יצירת מסלול מתוכנן
      final planned = route.sequence
          .map((id) => checkpoints.firstWhere((c) => c.id == id, orElse: () => checkpoints.first))
          .map((c) => LatLng(c.coordinates.lat, c.coordinates.lng))
          .toList();

      // TODO: טעינת מסלול בפועל ו ציון מהמסד נתונים
      // בינתיים - סימולציה
      final demoScore = NavigationScore(
        id: 'demo_${widget.navigation.id}_${user.uid}',
        navigationId: widget.navigation.id,
        navigatorId: user.uid,
        totalScore: 85,
        checkpointScores: {},
        calculatedAt: DateTime.now(),
      );

      setState(() {
        _myCheckpoints = checkpoints;
        _plannedRoute = planned;
        _actualRoute = []; // TODO
        _myScore = demoScore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    if (!widget.isNavigator) {
      _tabController.dispose();
    }
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

      List<SafetyPoint> safetyPoints = [];
      try {
        safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);
      } catch (_) {}

      setState(() {
        _checkpoints = checkpoints;
        _boundary = boundary;
        _safetyPoints = safetyPoints;
        _isLoading = false;
      });

      if (boundary != null && boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        _mapController.move(LatLng(center.lat, center.lng), 13.0);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _initializeInvestigationData() {
    // TODO: בפועל יטען מ-DB
    for (final navigatorId in widget.navigation.routes.keys) {
      _navigatorData[navigatorId] = NavigatorInvestigationData(
        navigatorId: navigatorId,
        trackPoints: [], // TODO: טעינה מDB
        punches: [], // TODO: טעינה מDB
        score: null, // TODO: טעינה מDB
        totalDistance: 0,
        totalTime: const Duration(hours: 2),
        avgSpeed: 0,
      );
    }

    _selectedNavigatorId = widget.navigatorId ?? widget.navigation.routes.keys.first;
  }

  Future<void> _exportGPX() async {
    final data = _navigatorData[_selectedNavigatorId];
    if (data == null || data.trackPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין נתוני מסלול')),
      );
      return;
    }

    try {
      final gpsService = GPSTrackingService();
      // בניית GPX מהנתונים
      final gpxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Navigate App">
  <trk>
    <name>${widget.navigation.name} - $_selectedNavigatorId</name>
    <trkseg>
${data.trackPoints.map((tp) => '      <trkpt lat="${tp.coordinate.lat}" lon="${tp.coordinate.lng}">\n        <time>${tp.timestamp.toIso8601String()}</time>\n      </trkpt>').join('\n')}
    </trkseg>
  </trk>
</gpx>''';

      // שמירה
      final fileName = 'GPX_${widget.navigation.name}_$_selectedNavigatorId.gpx';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'שמור GPX',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['gpx'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(gpxContent);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('GPX נשמר\n$result'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _returnToPreparation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('חזרה להכנה'),
        content: const Text('האם להחזיר את הניווט למצב הכנה?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('חזרה להכנה'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updatedNav = _currentNavigation.copyWith(
        status: 'preparation',
        updatedAt: DateTime.now(),
      );
      await _navRepo.update(updatedNav);
      _currentNavigation = updatedNav;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
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
    // תצוגה למנווט
    if (widget.isNavigator) {
      return _buildNavigatorView();
    }

    // תצוגה למפקד
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'תחקור ניווט',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.map), text: 'מפה'),
            Tab(icon: Icon(Icons.analytics), text: 'נתונים'),
            Tab(icon: Icon(Icons.grade), text: 'ציון'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'ייצא GPX',
            onPressed: _exportGPX,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // בחירת מנווט
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[100],
                  child: DropdownButton<String>(
                    value: _selectedNavigatorId,
                    isExpanded: true,
                    items: widget.navigation.routes.keys.map((id) {
                      return DropdownMenuItem(
                        value: id,
                        child: Text(id),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedNavigatorId = value);
                    },
                  ),
                ),

                // תוכן
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMapView(),
                      _buildDataView(),
                      _buildScoreView(),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _returnToPreparation,
                  icon: const Icon(Icons.undo),
                  label: const Text('חזרה להכנה'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _deleteNavigation,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('מחיקת ניווט'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapView() {
    final data = _navigatorData[_selectedNavigatorId];
    if (data == null) return const Center(child: Text('אין נתונים'));

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

            // מסלול המנווט
            if (_showRoutes && data.trackPoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: data.trackPoints
                        .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
                        .toList(),
                    strokeWidth: 3,
                    color: Colors.green.withValues(alpha: _routesOpacity),
                  ),
                ],
              ),

            // דקירות
            if (_showPunches && data.punches.isNotEmpty)
              MarkerLayer(
                markers: data.punches.map((punch) {
                  Color color;
                  if (punch.isApproved) {
                    color = Colors.green;
                  } else if (punch.isRejected) {
                    color = Colors.red;
                  } else {
                    color = Colors.orange;
                  }

                  return Marker(
                    point: LatLng(punch.punchLocation.lat, punch.punchLocation.lng),
                    width: 30,
                    height: 30,
                    child: Opacity(opacity: _punchesOpacity, child: Icon(Icons.flag, color: color, size: 30)),
                  );
                }).toList(),
              ),

            // נקודות ציון
            if (_showNZ)
              MarkerLayer(
                markers: _checkpoints.map((cp) {
                  final markerColor = cp.color == 'green' ? Colors.green : Colors.blue;
                  return Marker(
                    point: LatLng(cp.coordinates.lat, cp.coordinates.lng),
                    width: 36,
                    height: 36,
                    child: Opacity(
                      opacity: _nzOpacity,
                      child: Container(
                        decoration: BoxDecoration(
                          color: markerColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
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
            MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, onVisibilityChanged: (v) => setState(() => _showGG = v), opacity: _ggOpacity, onOpacityChanged: (v) => setState(() => _ggOpacity = v)),
            MapLayerConfig(id: 'nz', label: 'נקודות ציון', color: Colors.blue, visible: _showNZ, onVisibilityChanged: (v) => setState(() => _showNZ = v), opacity: _nzOpacity, onOpacityChanged: (v) => setState(() => _nzOpacity = v)),
            MapLayerConfig(id: 'nb', label: 'נקודות בטיחות', color: Colors.red, visible: _showNB, onVisibilityChanged: (v) => setState(() => _showNB = v), opacity: _nbOpacity, onOpacityChanged: (v) => setState(() => _nbOpacity = v)),
            MapLayerConfig(id: 'routes', label: 'מסלולים', color: Colors.orange, visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v), opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v)),
            MapLayerConfig(id: 'punches', label: 'דקירות', color: Colors.green, visible: _showPunches, onVisibilityChanged: (v) => setState(() => _showPunches = v), opacity: _punchesOpacity, onOpacityChanged: (v) => setState(() => _punchesOpacity = v)),
          ],
        ),
      ],
    );
  }

  Widget _buildDataView() {
    final data = _navigatorData[_selectedNavigatorId];
    if (data == null) return const Center(child: Text('אין נתונים'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'נתוני מסלול',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        _buildDataCard(
          icon: Icons.route,
          title: 'אורך מסלול',
          value: '${data.totalDistance.toStringAsFixed(2)} ק"מ',
          color: Colors.blue,
        ),

        _buildDataCard(
          icon: Icons.timer,
          title: 'משך זמן',
          value: _formatDuration(data.totalTime),
          color: Colors.purple,
        ),

        _buildDataCard(
          icon: Icons.speed,
          title: 'מהירות ממוצעת',
          value: '${data.avgSpeed.toStringAsFixed(1)} קמ"ש',
          color: Colors.orange,
        ),

        _buildDataCard(
          icon: Icons.place,
          title: 'דקירות',
          value: '${data.punches.length}',
          color: Colors.green,
        ),

        _buildDataCard(
          icon: Icons.navigation,
          title: 'נקודות מסלול',
          value: '${data.trackPoints.length}',
          color: Colors.teal,
        ),

        const SizedBox(height: 16),

        // כפתור ייצוא
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _exportGPX,
            icon: const Icon(Icons.download),
            label: const Text('ייצא GPX'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreView() {
    final data = _navigatorData[_selectedNavigatorId];
    if (data == null || data.score == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grade, size: 100, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'אין ציון זמין',
              style: TextStyle(fontSize: 20, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final score = data.score!;
    final grade = ScoringService().getGrade(score.totalScore);
    final color = ScoringService.getScoreColor(score.totalScore);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ציון כולל
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
              border: Border.all(color: color, width: 8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${score.totalScore}',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  grade,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // פירוט
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'פירוט ציון',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _buildScoreRow('נקודות שאושרו',
                      '${score.checkpointScores.values.where((s) => s.approved).length}/${score.checkpointScores.length}'),
                  _buildScoreRow(
                      'שיטת חישוב', score.isManual ? 'ידני' : 'אוטומטי'),
                  _buildScoreRow('תאריך חישוב',
                      score.calculatedAt.toString().split(' ')[0]),
                  if (score.isPublished)
                    _buildScoreRow('תאריך הפצה',
                        score.publishedAt?.toString().split(' ')[0] ?? '-'),
                  if (score.notes != null && score.notes!.isNotEmpty) ...[
                    const Divider(),
                    const Text(
                      'הערות:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(score.notes!),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ציונים לכל נקודה
          const Text(
            'ציון לפי נקודה:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ...score.checkpointScores.entries.map((entry) {
            final cpScore = entry.value;
            final checkpoint = _checkpoints.firstWhere(
              (cp) => cp.id == cpScore.checkpointId,
              orElse: () => _checkpoints.first,
            );

            return Card(
              child: ListTile(
                leading: Icon(
                  cpScore.approved ? Icons.check_circle : Icons.cancel,
                  color: cpScore.approved ? Colors.green : Colors.red,
                ),
                title: Text(checkpoint.name),
                subtitle: Text(
                  'מרחק: ${cpScore.distanceMeters.toStringAsFixed(1)}m',
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ScoringService.getScoreColor(cpScore.score).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${cpScore.score}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: ScoringService.getScoreColor(cpScore.score),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDataCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildScoreRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}ש ${minutes}ד';
  }

  /// תצוגה למנווט - צפייה במסלול עם ציון
  Widget _buildNavigatorView() {
    if (_myCheckpoints.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.navigation.name),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('אין נקודות להצגה'),
        ),
      );
    }

    // חישוב מרכז המפה
    final center = LatLng(
      _myCheckpoints.map((c) => c.coordinates.lat).reduce((a, b) => a + b) / _myCheckpoints.length,
      _myCheckpoints.map((c) => c.coordinates.lng).reduce((a, b) => a + b) / _myCheckpoints.length,
    );

    // צבע לפי ציון
    Color scoreColor = Colors.grey;
    if (_myScore != null) {
      if (_myScore!.totalScore >= 80) {
        scoreColor = Colors.green;
      } else if (_myScore!.totalScore >= 60) {
        scoreColor = Colors.orange;
      } else {
        scoreColor = Colors.red;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'תחקור ניווט',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // כרטיס ציון
                if (_myScore != null)
                  Card(
                    margin: const EdgeInsets.all(16),
                    color: scoreColor.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: scoreColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${_myScore!.totalScore}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'הציון שלך',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _myScore!.totalScore >= 80
                                      ? 'כל הכבוד! ביצוע מעולה'
                                      : _myScore!.totalScore >= 60
                                          ? 'ביצוע טוב'
                                          : 'נדרש שיפור',
                                  style: TextStyle(
                                    color: scoreColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          initialCenter: center,
                          initialZoom: 14.0,
                          onTap: (tapPosition, point) {
                            if (_measureMode) {
                              setState(() => _measurePoints.add(point));
                              return;
                            }
                          },
                        ),
                        layers: [

                          // ג"ג
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

                          // מסלול מתוכנן (כחול מקווקו)
                          if (_showRoutes && _plannedRoute.length > 1)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _plannedRoute,
                                  color: Colors.blue.withValues(alpha: _routesOpacity),
                                  strokeWidth: 3.0,
                                ),
                              ],
                            ),

                          // מסלול בפועל (ירוק)
                          if (_showRoutes && _actualRoute.length > 1)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _actualRoute,
                                  color: Colors.green.withValues(alpha: _routesOpacity),
                                  strokeWidth: 3.0,
                                ),
                              ],
                            ),

                          // נקודות
                          if (_showNZ)
                            MarkerLayer(
                              markers: _myCheckpoints.asMap().entries.map((entry) {
                                final index = entry.key + 1;
                                final checkpoint = entry.value;
                                return Marker(
                                  point: LatLng(checkpoint.coordinates.lat, checkpoint.coordinates.lng),
                                  width: 40,
                                  height: 40,
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
                          MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, onVisibilityChanged: (v) => setState(() => _showGG = v), opacity: _ggOpacity, onOpacityChanged: (v) => setState(() => _ggOpacity = v)),
                          MapLayerConfig(id: 'nz', label: 'נקודות ציון', color: Colors.blue, visible: _showNZ, onVisibilityChanged: (v) => setState(() => _showNZ = v), opacity: _nzOpacity, onOpacityChanged: (v) => setState(() => _nzOpacity = v)),
                          MapLayerConfig(id: 'nb', label: 'נקודות בטיחות', color: Colors.red, visible: _showNB, onVisibilityChanged: (v) => setState(() => _showNB = v), opacity: _nbOpacity, onOpacityChanged: (v) => setState(() => _nbOpacity = v)),
                          MapLayerConfig(id: 'routes', label: 'מסלולים', color: Colors.orange, visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v), opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v)),
                          MapLayerConfig(id: 'punches', label: 'דקירות', color: Colors.green, visible: _showPunches, onVisibilityChanged: (v) => setState(() => _showPunches = v), opacity: _punchesOpacity, onOpacityChanged: (v) => setState(() => _punchesOpacity = v)),
                        ],
                      ),
                    ],
                  ),
                ),

                // מקרא
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              border: Border.all(color: Colors.blue),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('מסלול מתוכנן'),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 3,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          const Text('מסלול בפועל'),
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

/// נתוני תחקור למנווט
class NavigatorInvestigationData {
  final String navigatorId;
  final List<TrackPoint> trackPoints;
  final List<CheckpointPunch> punches;
  final NavigationScore? score;
  final double totalDistance;
  final Duration totalTime;
  final double avgSpeed;

  NavigatorInvestigationData({
    required this.navigatorId,
    required this.trackPoints,
    required this.punches,
    this.score,
    required this.totalDistance,
    required this.totalTime,
    required this.avgSpeed,
  });
}
