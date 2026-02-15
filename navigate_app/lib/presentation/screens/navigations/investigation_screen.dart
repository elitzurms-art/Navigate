import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/nav_layer.dart' as nav;
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/navigation_score.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../services/gps_tracking_service.dart';
import '../../../services/scoring_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/route_export_service.dart';
import '../../../services/route_analysis_service.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/speed_profile_chart.dart';
import '../../widgets/route_playback_widget.dart';
import '../../widgets/navigator_heatmap.dart';
import '../../widgets/navigator_comparison_widget.dart';
import '../../widgets/map_image_export.dart';

/// צבעי מסלול
const _kPlannedRouteColor = Color(0xFFF44336); // אדום — מתוכנן
const _kActualRouteColor = Color(0xFF2196F3); // כחול — בפועל
const _kStartColor = Color(0xFF4CAF50); // ירוק — H (התחלה)
const _kEndColor = Color(0xFFF44336); // אדום — S (סיום)
const _kCheckpointColor = Color(0xFFFFC107); // צהוב — B (ביניים)
const _kBoundaryColor = Colors.black;
const _kSafetyColor = Color(0xFFFF9800); // כתום

/// פלטת צבעים למנווטים מרובים
const _kNavigatorColors = [
  Color(0xFF2196F3),
  Color(0xFF4CAF50),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFF00BCD4),
  Color(0xFFFF5722),
  Color(0xFF3F51B5),
  Color(0xFFE91E63),
  Color(0xFF009688),
  Color(0xFF795548),
];

/// מסך תחקור ניווט — מפקד (פר-מנווט + כולם) ומנווט
class InvestigationScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final String? navigatorId;
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
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationTrackRepository _trackRepo = NavigationTrackRepository();
  final CheckpointPunchRepository _punchRepo = CheckpointPunchRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final RouteExportService _exportService = RouteExportService();
  final ScoringService _scoringService = ScoringService();
  final RouteAnalysisService _analysisService = RouteAnalysisService();
  final MapController _mapController = MapController();
  final GlobalKey _mapCaptureKey = GlobalKey();

  TabController? _tabController;

  bool _isLoading = true;

  // שכבות ניווט
  List<nav.NavCheckpoint> _navCheckpoints = [];
  List<nav.NavSafetyPoint> _navSafetyPoints = [];
  List<nav.NavBoundary> _navBoundaries = [];

  // נתוני מנווטים
  final Map<String, _NavigatorData> _navigatorDataMap = {};
  String? _selectedNavigatorId;
  bool _allNavigatorsMode = false;

  // שכבות מפה
  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = false;
  bool _showPlanned = true;
  bool _showRoutes = true;
  bool _showPunches = true;

  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _plannedOpacity = 1.0;
  double _routesOpacity = 1.0;
  double _punchesOpacity = 1.0;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // חותינ תואצות
  RouteStatistics? _selectedNavStats;
  List<SpeedSegment> _selectedSpeedProfile = [];
  List<DeviationSegment> _selectedDeviations = [];
  List<NavigatorComparison> _navigatorComparisons = [];
  bool _showDeviations = true;
  bool _showHeatmap = false;
  bool _showPlayback = false;

  late domain.Navigation _currentNavigation;

  // Navigator view data
  List<nav.NavCheckpoint> _myCheckpoints = [];
  List<LatLng> _myPlannedRoute = [];
  List<LatLng> _myActualRoute = [];
  List<CheckpointPunch> _myPunches = [];
  NavigationScore? _myScore;

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    if (!widget.isNavigator) {
      _tabController = TabController(length: 3, vsync: this);
    }
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      // טעינת שכבות ניווט
      _navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
          widget.navigation.id);
      _navSafetyPoints = await _navLayerRepo.getSafetyPointsByNavigation(
          widget.navigation.id);
      _navBoundaries = await _navLayerRepo.getBoundariesByNavigation(
          widget.navigation.id);

      if (widget.isNavigator) {
        await _loadNavigatorViewData();
      } else {
        await _loadCommanderData();
      }

      // חישוב ניתוח
      _computeAnalysis();

      // Center map on boundary or checkpoints
      _centerMapOnData();
    } catch (e) {
      print('DEBUG InvestigationScreen: Error loading data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadNavigatorViewData() async {
    final user = await AuthService().getCurrentUser();
    if (user == null) return;

    final route = widget.navigation.routes[user.uid];
    if (route == null) return;

    // Checkpoints for this navigator's route
    _myCheckpoints = [];
    for (final cpId in route.checkpointIds) {
      final cp = _navCheckpoints.where((c) =>
          c.id == cpId || c.sourceId == cpId).toList();
      if (cp.isNotEmpty && !_myCheckpoints.contains(cp.first)) {
        _myCheckpoints.add(cp.first);
      }
    }
    if (_myCheckpoints.isEmpty) _myCheckpoints = _navCheckpoints;

    // Planned route
    _myPlannedRoute = route.plannedPath
        .map((c) => LatLng(c.lat, c.lng))
        .toList();
    if (_myPlannedRoute.isEmpty) {
      _myPlannedRoute = _myCheckpoints
          .where((c) => !c.isPolygon && c.coordinates != null)
          .map((c) => LatLng(c.coordinates!.lat, c.coordinates!.lng))
          .toList();
    }

    // Actual route from track
    final track = await _trackRepo.getByNavigatorAndNavigation(
        user.uid, widget.navigation.id);
    if (track != null && track.trackPointsJson.isNotEmpty) {
      try {
        final points = (jsonDecode(track.trackPointsJson) as List)
            .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
            .toList();
        _myActualRoute = points
            .map((p) => LatLng(p.coordinate.lat, p.coordinate.lng))
            .toList();
      } catch (_) {}
    }

    // Punches
    _myPunches = await _punchRepo.getByNavigator(user.uid);
    _myPunches = _myPunches
        .where((p) => p.navigationId == widget.navigation.id)
        .toList();

    // Score
    try {
      final scores = await _navRepo.fetchScoresFromFirestore(
          widget.navigation.id);
      final myScoreMap = scores
          .where((s) => s['navigatorId'] == user.uid)
          .toList();
      if (myScoreMap.isNotEmpty) {
        _myScore = NavigationScore.fromMap(myScoreMap.first);
      }
    } catch (_) {}
  }

  Future<void> _loadCommanderData() async {
    final navigatorIds = widget.navigation.routes.keys.toList();
    int colorIdx = 0;

    for (final navId in navigatorIds) {
      final route = widget.navigation.routes[navId]!;
      final color = _kNavigatorColors[colorIdx % _kNavigatorColors.length];
      colorIdx++;

      // Track points
      List<TrackPoint> trackPoints = [];
      final track = await _trackRepo.getByNavigatorAndNavigation(
          navId, widget.navigation.id);
      if (track != null && track.trackPointsJson.isNotEmpty) {
        try {
          trackPoints = (jsonDecode(track.trackPointsJson) as List)
              .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      // Punches
      List<CheckpointPunch> punches = [];
      try {
        punches = await _punchRepo.getByNavigationFromFirestore(
            widget.navigation.id);
        punches = punches.where((p) => p.navigatorId == navId).toList();
      } catch (_) {
        punches = (await _punchRepo.getByNavigator(navId))
            .where((p) => p.navigationId == widget.navigation.id)
            .toList();
      }

      // Planned route
      final plannedRoute = route.plannedPath
          .map((c) => LatLng(c.lat, c.lng))
          .toList();

      // Route checkpoints
      List<nav.NavCheckpoint> routeCps = [];
      for (final cpId in route.checkpointIds) {
        final matches = _navCheckpoints.where((c) =>
            c.id == cpId || c.sourceId == cpId).toList();
        if (matches.isNotEmpty && !routeCps.contains(matches.first)) {
          routeCps.add(matches.first);
        }
      }

      // Score
      NavigationScore? score;
      try {
        final scores = await _navRepo.fetchScoresFromFirestore(
            widget.navigation.id);
        final match = scores.where((s) => s['navigatorId'] == navId).toList();
        if (match.isNotEmpty) {
          score = NavigationScore.fromMap(match.first);
        }
      } catch (_) {}

      // Compute stats
      final actualCoords = trackPoints
          .map((tp) => Coordinate(
              lat: tp.coordinate.lat, lng: tp.coordinate.lng, utm: ''))
          .toList();
      final actualDistKm = GeometryUtils.calculatePathLengthKm(actualCoords);
      final totalDuration = trackPoints.length >= 2
          ? trackPoints.last.timestamp
              .difference(trackPoints.first.timestamp)
          : Duration.zero;
      final avgSpeedKmh = totalDuration.inSeconds > 0
          ? actualDistKm / (totalDuration.inSeconds / 3600.0)
          : 0.0;

      final activePunches = punches.where((p) => !p.isDeleted).toList();

      _navigatorDataMap[navId] = _NavigatorData(
        navigatorId: navId,
        trackPoints: trackPoints,
        punches: activePunches,
        plannedRoute: plannedRoute,
        routeCheckpoints: routeCps,
        score: score,
        plannedDistanceKm: route.routeLengthKm,
        actualDistanceKm: actualDistKm,
        totalDuration: totalDuration.isNegative ? Duration.zero : totalDuration,
        avgSpeedKmh: avgSpeedKmh,
        checkpointsHit: activePunches.length,
        totalCheckpoints: route.checkpointIds.length,
        color: color,
      );
    }

    _selectedNavigatorId = widget.navigatorId ??
        (navigatorIds.isNotEmpty ? navigatorIds.first : null);
  }

  void _centerMapOnData() {
    if (_navBoundaries.isNotEmpty) {
      final boundary = _navBoundaries.first;
      if (boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        _mapController.move(LatLng(center.lat, center.lng), 13.0);
        return;
      }
    }
    final pointCps = _navCheckpoints
        .where((c) => !c.isPolygon && c.coordinates != null)
        .toList();
    if (pointCps.isNotEmpty) {
      final lat = pointCps.map((c) => c.coordinates!.lat).reduce((a, b) => a + b) / pointCps.length;
      final lng = pointCps.map((c) => c.coordinates!.lng).reduce((a, b) => a + b) / pointCps.length;
      _mapController.move(LatLng(lat, lng), 14.0);
    }
  }

  void _computeAnalysis() {
    // ניתוח למנווט נבחר
    final navId = widget.isNavigator ? null : _selectedNavigatorId;
    if (navId != null && _navigatorDataMap.containsKey(navId)) {
      final data = _navigatorDataMap[navId]!;
      final route = widget.navigation.routes[navId];
      if (route != null) {
        _selectedNavStats = _analysisService.calculateStatistics(
          trackPoints: data.trackPoints,
          checkpoints: data.routeCheckpoints,
          punches: data.punches,
          route: route,
          plannedRoute: data.plannedRoute.length >= 2 ? data.plannedRoute : null,
        );
        _selectedSpeedProfile = _selectedNavStats?.speedProfile ?? [];
        _selectedDeviations = data.plannedRoute.length >= 2
            ? _analysisService.analyzeDeviations(
                plannedRoute: data.plannedRoute,
                actualTrack: data.trackPoints,
              )
            : [];
      }
    } else if (widget.isNavigator && _myActualRoute.length >= 2) {
      // ניתוח למנווט עצמו
      final user = widget.navigation.routes.keys.isNotEmpty
          ? widget.navigation.routes.keys.first
          : null;
      if (user != null) {
        final route = widget.navigation.routes[user];
        if (route != null) {
          final trackPts = <TrackPoint>[];
          // Track points already decoded in _myActualRoute
          _selectedSpeedProfile = _analysisService.calculateSpeedProfile(
              trackPoints: trackPts);
        }
      }
    }

    // השוואת מנווטים
    if (!widget.isNavigator) {
      final inputs = _navigatorDataMap.entries.map((e) {
        return NavigatorComparisonInput(
          navigatorId: e.key,
          navigatorName: _getNavigatorDisplayName(e.key),
          trackPoints: e.value.trackPoints,
          checkpoints: e.value.routeCheckpoints,
          punches: e.value.punches,
        );
      }).toList();
      _navigatorComparisons = _analysisService.compareNavigators(
        navigation: widget.navigation,
        navigatorData: inputs,
      );
    }
  }

  void _onNavigatorChanged(String? newId) {
    setState(() {
      _selectedNavigatorId = newId;
      _computeAnalysis();
    });
  }

  String _getNavigatorDisplayName(String navigatorId) {
    return navigatorId.length > 4
        ? '...${navigatorId.substring(navigatorId.length - 4)}'
        : navigatorId;
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

  void _onExport() {
    if (widget.isNavigator) {
      _exportNavigatorData();
    } else {
      _exportCommanderData();
    }
  }

  Future<void> _exportNavigatorData() async {
    final user = await AuthService().getCurrentUser();
    if (user == null) return;
    final route = widget.navigation.routes[user.uid];

    // אוסף track points מה-raw data
    List<TrackPoint> exportTrackPts = [];
    try {
      final track = await _trackRepo.getByNavigatorAndNavigation(
          user.uid, widget.navigation.id);
      if (track != null && track.trackPointsJson.isNotEmpty) {
        exportTrackPts = (jsonDecode(track.trackPointsJson) as List)
            .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;
    _exportService.showExportDialog(context, data: ExportData(
      navigationName: widget.navigation.name,
      navigatorName: user.fullName,
      trackPoints: exportTrackPts,
      checkpoints: _myCheckpoints,
      punches: _myPunches,
      plannedPath: route?.plannedPath,
    ));
  }

  Future<void> _exportCommanderData() async {
    final navId = _selectedNavigatorId;
    if (navId == null) return;
    final data = _navigatorDataMap[navId];
    if (data == null) return;
    final route = widget.navigation.routes[navId];

    _exportService.showExportDialog(context, data: ExportData(
      navigationName: widget.navigation.name,
      navigatorName: _getNavigatorDisplayName(navId),
      trackPoints: data.trackPoints,
      checkpoints: data.routeCheckpoints,
      punches: data.punches,
      plannedPath: route?.plannedPath,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isNavigator) return _buildNavigatorView();
    return _buildCommanderView();
  }

  // ===========================================================================
  // Commander View
  // ===========================================================================

  Widget _buildCommanderView() {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text('תחקור ניווט', style: TextStyle(fontSize: 14)),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.map), text: 'מפה'),
            Tab(icon: Icon(Icons.analytics), text: 'סטטיסטיקות'),
            Tab(icon: Icon(Icons.grade), text: 'ציונים'),
          ],
        ),
        actions: [
          MapExportButton(
            captureKey: _mapCaptureKey,
            navigationName: widget.navigation.name,
            navigatorName: _selectedNavigatorId != null
                ? _getNavigatorDisplayName(_selectedNavigatorId!)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'ייצוא',
            onPressed: _onExport,
          ),
          IconButton(
            icon: Icon(_allNavigatorsMode ? Icons.person : Icons.people),
            tooltip: _allNavigatorsMode ? 'מנווט בודד' : 'כל המנווטים',
            onPressed: () =>
                setState(() => _allNavigatorsMode = !_allNavigatorsMode),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Navigator selector
                if (!_allNavigatorsMode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    color: Colors.grey[100],
                    child: Row(
                      children: [
                        const Text('מנווט: ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _selectedNavigatorId,
                            isExpanded: true,
                            items: _navigatorDataMap.keys.map((id) {
                              final data = _navigatorDataMap[id]!;
                              return DropdownMenuItem(
                                value: id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: data.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(_getNavigatorDisplayName(id)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                _onNavigatorChanged(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMapTab(),
                      _buildStatisticsTab(),
                      _buildScoresTab(),
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
                        borderRadius: BorderRadius.circular(12)),
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Map Tab
  // ===========================================================================

  Widget _buildMapTab() {
    return Stack(
      children: [
        MapWithTypeSelector(
          showTypeSelector: false,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(32.0853, 34.7818),
            initialZoom: 13.0,
            onTap: (tapPosition, point) {
              if (_measureMode) {
                setState(() => _measurePoints.add(point));
              }
            },
          ),
          layers: [
            // Boundary
            ..._buildBoundaryLayers(),
            // Safety points
            ..._buildSafetyLayers(),
            // Routes
            if (_allNavigatorsMode)
              ..._buildAllNavigatorsRouteLayers()
            else
              ..._buildSingleNavigatorRouteLayers(),
            // Checkpoints
            if (_showNZ) ..._buildCheckpointMarkers(_navCheckpoints),
            // Measure layers
            ...MapControls.buildMeasureLayers(_measurePoints),
          ],
        ),
        _buildMapControls(),
      ],
    );
  }

  List<Widget> _buildBoundaryLayers() {
    if (!_showGG || _navBoundaries.isEmpty) return [];
    return [
      PolygonLayer(
        polygons: _navBoundaries
            .where((b) => b.coordinates.isNotEmpty)
            .map((b) => Polygon(
                  points: b.coordinates
                      .map((c) => LatLng(c.lat, c.lng))
                      .toList(),
                  color: _kBoundaryColor.withValues(alpha: 0.1 * _ggOpacity),
                  borderColor: _kBoundaryColor.withValues(alpha: _ggOpacity),
                  borderStrokeWidth: 2.0,
                  isFilled: true,
                ))
            .toList(),
      ),
    ];
  }

  List<Widget> _buildSafetyLayers() {
    if (!_showNB || _navSafetyPoints.isEmpty) return [];
    final pointSafety = _navSafetyPoints
        .where((p) => p.coordinates != null)
        .toList();
    final result = <Widget>[];
    if (pointSafety.isNotEmpty) {
      result.add(MarkerLayer(
        markers: pointSafety
            .map((p) => Marker(
                  point: LatLng(p.coordinates!.lat, p.coordinates!.lng),
                  width: 30,
                  height: 30,
                  child: Opacity(
                    opacity: _nbOpacity,
                    child: const Icon(Icons.warning_amber,
                        color: _kSafetyColor, size: 28),
                  ),
                ))
            .toList(),
      ));
    }
    return result;
  }

  List<Widget> _buildCheckpointMarkers(List<nav.NavCheckpoint> checkpoints) {
    final pointCps = checkpoints
        .where((c) => !c.isPolygon && c.coordinates != null)
        .toList();
    if (pointCps.isEmpty) return [];

    return [
      MarkerLayer(
        markers: pointCps.map((cp) {
          Color bgColor;
          String letter;
          if (cp.type == 'start') {
            bgColor = _kStartColor;
            letter = 'H';
          } else if (cp.type == 'end') {
            bgColor = _kEndColor;
            letter = 'S';
          } else {
            bgColor = _kCheckpointColor;
            letter = 'B';
          }

          final label = '${cp.sequenceNumber}$letter';

          return Marker(
            point: LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
            width: 38,
            height: 38,
            child: Opacity(
              opacity: _nzOpacity,
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ];
  }

  List<Widget> _buildSingleNavigatorRouteLayers() {
    final navId = _selectedNavigatorId;
    if (navId == null) return [];
    final data = _navigatorDataMap[navId];
    if (data == null) return [];

    final layers = <Widget>[];

    // Planned route (RED)
    if (_showPlanned && data.plannedRoute.length > 1) {
      layers.add(PolylineLayer(
        polylines: [
          Polyline(
            points: data.plannedRoute,
            color: _kPlannedRouteColor.withValues(alpha: _plannedOpacity),
            strokeWidth: 4.0,
          ),
        ],
      ));
    }

    // Actual route (BLUE)
    if (_showRoutes && data.trackPoints.isNotEmpty) {
      final actualPoints = data.trackPoints
          .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
          .toList();
      if (actualPoints.length > 1) {
        layers.add(PolylineLayer(
          polylines: [
            Polyline(
              points: actualPoints,
              color: _kActualRouteColor.withValues(alpha: _routesOpacity),
              strokeWidth: 3.0,
            ),
          ],
        ));
      }
    }

    // Deviation segments (RED overlay)
    if (_showDeviations && _selectedDeviations.isNotEmpty && data.trackPoints.isNotEmpty) {
      for (final dev in _selectedDeviations) {
        final devColor = _analysisService.getDeviationColor(dev.maxDeviation);
        final start = dev.startIndex.clamp(0, data.trackPoints.length - 1);
        final end = (dev.endIndex + 1).clamp(0, data.trackPoints.length);
        final devPoints = data.trackPoints
            .sublist(start, end)
            .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
            .toList();
        if (devPoints.length > 1) {
          layers.add(PolylineLayer(
            polylines: [
              Polyline(
                points: devPoints,
                color: devColor.withValues(alpha: 0.8),
                strokeWidth: 6.0,
              ),
            ],
          ));
        }
      }
    }

    // Punches
    if (_showPunches && data.punches.isNotEmpty) {
      layers.add(MarkerLayer(
        markers: data.punches.map((p) => _buildPunchMarker(p)).toList(),
      ));
    }

    return layers;
  }

  List<Widget> _buildAllNavigatorsRouteLayers() {
    final layers = <Widget>[];

    // Heatmap layer
    if (_showHeatmap) {
      final heatTracks = <String, List<TrackPoint>>{};
      for (final entry in _navigatorDataMap.entries) {
        if (entry.value.trackPoints.isNotEmpty) {
          heatTracks[entry.key] = entry.value.trackPoints;
        }
      }
      if (heatTracks.isNotEmpty) {
        layers.add(NavigatorHeatmapLayer(navigatorTracks: heatTracks));
      }
    }

    for (final entry in _navigatorDataMap.entries) {
      final data = entry.value;

      if (_showRoutes && data.trackPoints.isNotEmpty) {
        final actualPoints = data.trackPoints
            .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
            .toList();
        if (actualPoints.length > 1) {
          layers.add(PolylineLayer(
            polylines: [
              Polyline(
                points: actualPoints,
                color: data.color.withValues(alpha: _routesOpacity),
                strokeWidth: 3.0,
              ),
            ],
          ));
        }
      }
    }

    return layers;
  }

  Marker _buildPunchMarker(CheckpointPunch punch) {
    Color color;
    IconData icon;
    if (punch.isApproved) {
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (punch.isRejected) {
      color = Colors.red;
      icon = Icons.cancel;
    } else {
      color = Colors.orange;
      icon = Icons.flag;
    }

    return Marker(
      point: LatLng(punch.punchLocation.lat, punch.punchLocation.lng),
      width: 28,
      height: 28,
      child: Opacity(
        opacity: _punchesOpacity,
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }

  Widget _buildMapControls() {
    return MapControls(
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
          id: 'gg', label: 'גבול גזרה', color: _kBoundaryColor,
          visible: _showGG, onVisibilityChanged: (v) => setState(() => _showGG = v),
          opacity: _ggOpacity, onOpacityChanged: (v) => setState(() => _ggOpacity = v),
        ),
        MapLayerConfig(
          id: 'nz', label: 'נקודות ציון', color: Colors.blue,
          visible: _showNZ, onVisibilityChanged: (v) => setState(() => _showNZ = v),
          opacity: _nzOpacity, onOpacityChanged: (v) => setState(() => _nzOpacity = v),
        ),
        MapLayerConfig(
          id: 'nb', label: 'נקודות בטיחות', color: _kSafetyColor,
          visible: _showNB, onVisibilityChanged: (v) => setState(() => _showNB = v),
          opacity: _nbOpacity, onOpacityChanged: (v) => setState(() => _nbOpacity = v),
        ),
        MapLayerConfig(
          id: 'planned', label: 'ציר מתוכנן', color: _kPlannedRouteColor,
          visible: _showPlanned, onVisibilityChanged: (v) => setState(() => _showPlanned = v),
          opacity: _plannedOpacity, onOpacityChanged: (v) => setState(() => _plannedOpacity = v),
        ),
        MapLayerConfig(
          id: 'routes', label: 'מסלול בפועל', color: _kActualRouteColor,
          visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v),
          opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v),
        ),
        if (!_allNavigatorsMode)
          MapLayerConfig(
            id: 'punches', label: 'דקירות', color: Colors.green,
            visible: _showPunches, onVisibilityChanged: (v) => setState(() => _showPunches = v),
            opacity: _punchesOpacity, onOpacityChanged: (v) => setState(() => _punchesOpacity = v),
          ),
        if (!_allNavigatorsMode)
          MapLayerConfig(
            id: 'deviations', label: 'סטיות', color: Colors.red,
            visible: _showDeviations, onVisibilityChanged: (v) => setState(() => _showDeviations = v),
            opacity: 1.0, onOpacityChanged: (_) {},
          ),
        if (_allNavigatorsMode)
          MapLayerConfig(
            id: 'heatmap', label: 'מפת חום', color: Colors.orange,
            visible: _showHeatmap, onVisibilityChanged: (v) => setState(() => _showHeatmap = v),
            opacity: 1.0, onOpacityChanged: (_) {},
          ),
      ],
    );
  }

  // ===========================================================================
  // Statistics Tab
  // ===========================================================================

  Widget _buildStatisticsTab() {
    if (_navigatorDataMap.isEmpty) {
      return const Center(child: Text('אין נתוני מנווטים'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 16),
          const Text('פירוט לפי מנווט',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildStatisticsTable(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final totalNavigators = _navigatorDataMap.length;
    final withTracks = _navigatorDataMap.values
        .where((d) => d.trackPoints.isNotEmpty).length;
    final withDistances = _navigatorDataMap.values
        .where((d) => d.actualDistanceKm > 0).toList();
    final avgDistance = withDistances.isNotEmpty
        ? withDistances.fold(0.0, (sum, d) => sum + d.actualDistanceKm) /
            withDistances.length
        : 0.0;

    return Row(
      children: [
        Expanded(child: _summaryCard(
            icon: Icons.people, label: 'מנווטים',
            value: '$totalNavigators', color: Colors.blue)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard(
            icon: Icons.gps_fixed, label: 'עם מסלול',
            value: '$withTracks', color: Colors.green)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard(
            icon: Icons.route, label: 'מרחק ממוצע',
            value: '${avgDistance.toStringAsFixed(1)} ק"מ',
            color: Colors.orange)),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 14,
        headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
        columns: const [
          DataColumn(label: Text('מנווט',
              style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('מרחק\nמתוכנן',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('מרחק\nבפועל',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('זמן',
              style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('מהירות\nממוצעת',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('נ.צ.\nשנדקרו',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('ציון',
              style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _navigatorDataMap.entries.map((entry) {
          final navId = entry.key;
          final data = entry.value;
          final scoreColor = data.score != null
              ? ScoringService.getScoreColor(data.score!.totalScore)
              : Colors.grey;

          return DataRow(cells: [
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                    color: data.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(_getNavigatorDisplayName(navId),
                  style: const TextStyle(fontSize: 13)),
            ])),
            DataCell(Text('${data.plannedDistanceKm.toStringAsFixed(1)} ק"מ')),
            DataCell(Text(data.actualDistanceKm > 0
                ? '${data.actualDistanceKm.toStringAsFixed(1)} ק"מ'
                : '-')),
            DataCell(Text(data.totalDuration.inSeconds > 0
                ? _formatDuration(data.totalDuration)
                : '-')),
            DataCell(Text(data.avgSpeedKmh > 0
                ? '${data.avgSpeedKmh.toStringAsFixed(1)} קמ"ש'
                : '-')),
            DataCell(
                Text('${data.checkpointsHit}/${data.totalCheckpoints}')),
            DataCell(data.score != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${data.score!.totalScore}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scoreColor)),
                  )
                : const Text('-', style: TextStyle(color: Colors.grey))),
          ]);
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // Scores Tab
  // ===========================================================================

  Widget _buildScoresTab() {
    if (_navigatorDataMap.isEmpty) {
      return const Center(child: Text('אין נתונים'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _navigatorDataMap.length,
      itemBuilder: (context, index) {
        final entry = _navigatorDataMap.entries.elementAt(index);
        return _buildNavigatorScoreCard(entry.key, entry.value);
      },
    );
  }

  Widget _buildNavigatorScoreCard(String navigatorId, _NavigatorData data) {
    final score = data.score;
    final name = _getNavigatorDisplayName(navigatorId);

    if (score == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: data.color.withOpacity(0.2),
            child: Icon(Icons.person, color: data.color),
          ),
          title: Text(name),
          subtitle: const Text('אין ציון'),
          trailing:
              const Icon(Icons.remove_circle_outline, color: Colors.grey),
        ),
      );
    }

    final scoreColor = ScoringService.getScoreColor(score.totalScore);
    final grade = _scoringService.getGrade(score.totalScore);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scoreColor.withOpacity(0.15),
              border: Border.all(color: scoreColor, width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${score.totalScore}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: scoreColor)),
                Text(grade,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: scoreColor)),
              ],
            ),
          ),
          title: Text(name,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            'נ.צ. שנדקרו: ${data.checkpointsHit}/${data.totalCheckpoints}  |  '
            'מרחק: ${data.actualDistanceKm.toStringAsFixed(1)} ק"מ',
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            if (score.checkpointScores.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('פירוט לפי נקודה:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...score.checkpointScores.entries.map((cpEntry) {
                      final cpScore = cpEntry.value;
                      final matchCp = _navCheckpoints.where(
                        (c) => c.sourceId == cpScore.checkpointId ||
                            c.id == cpScore.checkpointId,
                      );
                      final cpName = matchCp.isNotEmpty
                          ? matchCp.first.name
                          : cpScore.checkpointId;
                      final cpScoreColor =
                          ScoringService.getScoreColor(cpScore.score);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              cpScore.approved
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: cpScore.approved
                                  ? Colors.green
                                  : Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(cpName,
                                    style: const TextStyle(fontSize: 12))),
                            Text(
                                '${cpScore.distanceMeters.toStringAsFixed(0)}מ\'',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cpScoreColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${cpScore.score}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: cpScoreColor,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Navigator View
  // ===========================================================================

  Widget _buildNavigatorView() {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.navigation.name),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final pointCps = _myCheckpoints
        .where((c) => !c.isPolygon && c.coordinates != null)
        .toList();
    final center = pointCps.isNotEmpty
        ? LatLng(
            pointCps.map((c) => c.coordinates!.lat).reduce((a, b) => a + b) /
                pointCps.length,
            pointCps.map((c) => c.coordinates!.lng).reduce((a, b) => a + b) /
                pointCps.length,
          )
        : const LatLng(32.0853, 34.7818);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text('תחקור ניווט', style: TextStyle(fontSize: 14)),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'ייצוא',
            onPressed: _onExport,
          ),
        ],
      ),
      body: Column(
        children: [
          // Score card
          if (_myScore != null) _buildNavigatorScoreHeader(),
          // Stats row
          _buildNavigatorStatsRow(),
          // Map
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
                      }
                    },
                  ),
                  layers: [
                    ..._buildBoundaryLayers(),
                    // Planned route (RED)
                    if (_showPlanned && _myPlannedRoute.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _myPlannedRoute,
                            color: _kPlannedRouteColor.withValues(
                                alpha: _plannedOpacity),
                            strokeWidth: 4.0,
                          ),
                        ],
                      ),
                    // Actual route (BLUE)
                    if (_showRoutes && _myActualRoute.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _myActualRoute,
                            color: _kActualRouteColor.withValues(
                                alpha: _routesOpacity),
                            strokeWidth: 3.0,
                          ),
                        ],
                      ),
                    // Checkpoints
                    if (_showNZ) ..._buildCheckpointMarkers(_myCheckpoints),
                    // Safety
                    ..._buildSafetyLayers(),
                    // Punches
                    if (_showPunches && _myPunches.isNotEmpty)
                      MarkerLayer(
                        markers: _myPunches
                            .map((p) => _buildPunchMarker(p))
                            .toList(),
                      ),
                    ...MapControls.buildMeasureLayers(_measurePoints),
                  ],
                ),
                _buildMapControls(),
              ],
            ),
          ),
          // Legend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _legendItem(_kPlannedRouteColor, 'ציר מתוכנן'),
                _legendItem(_kActualRouteColor, 'מסלול בפועל'),
                _legendItem(_kStartColor, 'התחלה (H)'),
                _legendItem(_kEndColor, 'סיום (S)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigatorScoreHeader() {
    final score = _myScore!;
    final scoreColor = ScoringService.getScoreColor(score.totalScore);

    return Card(
      margin: const EdgeInsets.all(12),
      color: scoreColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: scoreColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('${score.totalScore}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('הציון שלך',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    score.totalScore >= 80
                        ? 'כל הכבוד! ביצוע מעולה'
                        : score.totalScore >= 60
                            ? 'ביצוע טוב'
                            : 'נדרש שיפור',
                    style: TextStyle(color: scoreColor, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'נ.צ. שנדקרו: ${_myPunches.length}/${_myCheckpoints.length}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigatorStatsRow() {
    final actualCoords = _myActualRoute
        .map((ll) => Coordinate(lat: ll.latitude, lng: ll.longitude, utm: ''))
        .toList();
    final actualDistKm = GeometryUtils.calculatePathLengthKm(actualCoords);

    final user = widget.navigation.routes.values.isNotEmpty
        ? widget.navigation.routes.values.first
        : null;
    final plannedDistKm = user?.routeLengthKm ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip(
              Icons.route, '${plannedDistKm.toStringAsFixed(1)} ק"מ', 'מתוכנן'),
          _statChip(Icons.timeline,
              '${actualDistKm.toStringAsFixed(1)} ק"מ', 'בפועל'),
          _statChip(Icons.flag,
              '${_myPunches.length}/${_myCheckpoints.length}', 'נ.צ.'),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14, height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}ש ${minutes}ד';
    return '${minutes}ד';
  }
}

// =============================================================================
// Internal data class
// =============================================================================

class _NavigatorData {
  final String navigatorId;
  final List<TrackPoint> trackPoints;
  final List<CheckpointPunch> punches;
  final List<LatLng> plannedRoute;
  final List<nav.NavCheckpoint> routeCheckpoints;
  final NavigationScore? score;
  final double plannedDistanceKm;
  final double actualDistanceKm;
  final Duration totalDuration;
  final double avgSpeedKmh;
  final int checkpointsHit;
  final int totalCheckpoints;
  final Color color;

  _NavigatorData({
    required this.navigatorId,
    required this.trackPoints,
    required this.punches,
    required this.plannedRoute,
    required this.routeCheckpoints,
    this.score,
    required this.plannedDistanceKm,
    required this.actualDistanceKm,
    required this.totalDuration,
    required this.avgSpeedKmh,
    required this.checkpointsHit,
    required this.totalCheckpoints,
    required this.color,
  });
}
