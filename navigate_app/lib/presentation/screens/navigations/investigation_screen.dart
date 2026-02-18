import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/nav_layer.dart' as nav;
import '../../../domain/entities/checkpoint_punch.dart';
import '../../../domain/entities/navigation_score.dart';
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_track_repository.dart';
import '../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/gps_tracking_service.dart';
import '../../../services/scoring_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/route_export_service.dart';
import '../../../services/route_analysis_service.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/speed_profile_chart.dart';
import '../../widgets/elevation_profile_chart.dart';
import '../../widgets/route_playback_widget.dart';
import '../../widgets/navigator_heatmap.dart';
import '../../widgets/navigator_comparison_widget.dart';
import '../../widgets/map_image_export.dart';
import '../../widgets/fullscreen_map_screen.dart';

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

/// מסך תחקור ניווט מאוחד — מפקד (4 טאבים) ומנווט (single scroll)
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

  // נתוני מנווטים (commander mode)
  final Map<String, _NavigatorData> _navigatorDataMap = {};
  String? _selectedNavigatorId;
  bool _allNavigatorsMode = false;

  // ציונים (עריכה מקומית — commander)
  final Map<String, NavigationScore> _scores = {};
  // ציונים אוטומטיים מקוריים (לייחוס)
  final Map<String, int> _autoScores = {};

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

  // ניתוח
  RouteStatistics? _selectedNavStats;
  List<SpeedSegment> _selectedSpeedProfile = [];
  List<DeviationSegment> _selectedDeviations = [];
  List<NavigatorComparison> _navigatorComparisons = [];
  bool _showDeviations = true;
  bool _showHeatmap = false;
  bool _showPlayback = false;

  late domain.Navigation _currentNavigation;

  // הגדרות אישור (commander settings tab)
  bool _autoApprovalEnabled = true;

  // קריטריוני ניקוד
  String _scoringMode = 'equal'; // 'equal' | 'custom'
  int _equalWeight = 0;
  Map<String, int> _customWeights = {};
  List<CustomCriterion> _customCriteria = [];
  bool _criteriaLoaded = false;

  // Navigator view data
  List<nav.NavCheckpoint> _myCheckpoints = [];
  List<LatLng> _myPlannedRoute = [];
  List<LatLng> _myActualRoute = [];
  List<TrackPoint> _myTrackPoints = [];
  List<CheckpointPunch> _myPunches = [];
  NavigationScore? _myScore;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    if (!widget.isNavigator) {
      _tabController = TabController(length: 4, vsync: this);
    }
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Data Loading
  // ===========================================================================

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

      // Firestore fallback — שכבות נוצרות במכשיר המפקד, מכשירים אחרים צריכים לסנכרן
      if (_navCheckpoints.isEmpty && _navSafetyPoints.isEmpty && _navBoundaries.isEmpty) {
        try {
          await _navLayerRepo.syncAllLayersFromFirestore(widget.navigation.id);
          _navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
              widget.navigation.id);
          _navSafetyPoints = await _navLayerRepo.getSafetyPointsByNavigation(
              widget.navigation.id);
          _navBoundaries = await _navLayerRepo.getBoundariesByNavigation(
              widget.navigation.id);
        } catch (_) {}
      }

      if (widget.isNavigator) {
        await _loadNavigatorViewData();
      } else {
        await _loadCommanderData();
      }

      // טעינת קריטריוני ניקוד
      _loadScoringCriteria();

      // חישוב ניתוח
      _computeAnalysis();

      // Center map on boundary or checkpoints
      _centerMapOnData();
    } catch (e) {
      print('DEBUG InvestigationScreen: Error loading data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _loadScoringCriteria() {
    final criteria = _currentNavigation.reviewSettings.scoringCriteria;
    if (criteria != null) {
      _scoringMode = criteria.mode;
      _equalWeight = criteria.equalWeightPerCheckpoint ?? 0;
      _customWeights = Map.from(criteria.checkpointWeights);
      _customCriteria = List.from(criteria.customCriteria);
    }
    _criteriaLoaded = true;
  }

  ScoringCriteria? _buildScoringCriteria() {
    if (!_criteriaLoaded) return null;
    // אם אין משקלות, אין קריטריונים
    if (_scoringMode == 'equal' && _equalWeight == 0 && _customCriteria.isEmpty) {
      return null;
    }
    if (_scoringMode == 'custom' && _customWeights.isEmpty && _customCriteria.isEmpty) {
      return null;
    }
    return ScoringCriteria(
      mode: _scoringMode,
      equalWeightPerCheckpoint: _scoringMode == 'equal' ? _equalWeight : null,
      checkpointWeights: _scoringMode == 'custom' ? _customWeights : const {},
      customCriteria: _customCriteria,
    );
  }

  Future<void> _saveScoringCriteria() async {
    final criteria = _buildScoringCriteria();
    final updatedReview = _currentNavigation.reviewSettings.copyWith(
      scoringCriteria: criteria,
    );
    final updatedNav = _currentNavigation.copyWith(
      reviewSettings: updatedReview,
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNav);
    setState(() {
      _currentNavigation = updatedNav;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('קריטריוני ניקוד נשמרו'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _loadNavigatorViewData() async {
    final user = await AuthService().getCurrentUser();
    if (user == null) return;
    _myUserId = user.uid;

    final route = widget.navigation.routes[user.uid];
    if (route == null) return;

    // Checkpoints for this navigator's route
    _myCheckpoints = [];
    for (final cpId in route.checkpointIds) {
      final cp = _navCheckpoints
          .where((c) => c.id == cpId || c.sourceId == cpId)
          .toList();
      if (cp.isNotEmpty && !_myCheckpoints.contains(cp.first)) {
        _myCheckpoints.add(cp.first);
      }
    }
    if (_myCheckpoints.isEmpty) _myCheckpoints = _navCheckpoints;

    // Planned route
    _myPlannedRoute =
        route.plannedPath.map((c) => LatLng(c.lat, c.lng)).toList();
    if (_myPlannedRoute.isEmpty) {
      _myPlannedRoute = _myCheckpoints
          .where((c) => !c.isPolygon && c.coordinates != null)
          .map((c) => LatLng(c.coordinates!.lat, c.coordinates!.lng))
          .toList();
    }

    // Actual route from track (store raw TrackPoints too)
    // נסיון מקומי, fallback ל-Firestore
    String? trackJson;
    final track = await _trackRepo.getByNavigatorAndNavigation(
        user.uid, widget.navigation.id);
    if (track != null && track.trackPointsJson.isNotEmpty) {
      trackJson = track.trackPointsJson;
    } else {
      try {
        final firestoreTracks = await _trackRepo.getByNavigationFromFirestore(
            widget.navigation.id);
        final myTrack = firestoreTracks.where((t) => t.navigatorUserId == user.uid).toList();
        if (myTrack.isNotEmpty && myTrack.first.trackPointsJson.isNotEmpty) {
          trackJson = myTrack.first.trackPointsJson;
        }
      } catch (_) {}
    }
    if (trackJson != null) {
      try {
        _myTrackPoints = (jsonDecode(trackJson) as List)
            .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
            .toList();
        _myActualRoute = _myTrackPoints
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
      final scores =
          await _navRepo.fetchScoresFromFirestore(widget.navigation.id);
      final myScoreMap =
          scores.where((s) => s['navigatorId'] == user.uid).toList();
      if (myScoreMap.isNotEmpty) {
        _myScore = NavigationScore.fromMap(myScoreMap.first);
      }
    } catch (_) {}
  }

  Future<void> _loadCommanderData() async {
    final navigatorIds = widget.navigation.routes.keys.toList();
    int colorIdx = 0;

    // טעינת tracks מ-Firestore (המפקד לא מחזיק tracks מקומיים — sync pushOnly)
    final Map<String, String> firestoreTrackPoints = {};
    try {
      final firestoreTracks = await _trackRepo.getByNavigationFromFirestore(
          widget.navigation.id);
      for (final track in firestoreTracks) {
        if (track.trackPointsJson.isNotEmpty) {
          firestoreTrackPoints[track.navigatorUserId] = track.trackPointsJson;
        }
      }
    } catch (_) {}

    for (final navId in navigatorIds) {
      final route = widget.navigation.routes[navId]!;
      final color = _kNavigatorColors[colorIdx % _kNavigatorColors.length];
      colorIdx++;

      // Track points — נסיון מקומי, fallback ל-Firestore
      List<TrackPoint> trackPoints = [];
      final track = await _trackRepo.getByNavigatorAndNavigation(
          navId, widget.navigation.id);
      String? trackJson;
      if (track != null && track.trackPointsJson.isNotEmpty) {
        trackJson = track.trackPointsJson;
      } else if (firestoreTrackPoints.containsKey(navId)) {
        trackJson = firestoreTrackPoints[navId];
      }
      if (trackJson != null) {
        try {
          trackPoints = (jsonDecode(trackJson) as List)
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
      final plannedRoute =
          route.plannedPath.map((c) => LatLng(c.lat, c.lng)).toList();

      // Route checkpoints
      List<nav.NavCheckpoint> routeCps = [];
      for (final cpId in route.checkpointIds) {
        final matches = _navCheckpoints
            .where((c) => c.id == cpId || c.sourceId == cpId)
            .toList();
        if (matches.isNotEmpty && !routeCps.contains(matches.first)) {
          routeCps.add(matches.first);
        }
      }

      // Score
      NavigationScore? score;
      try {
        final scores =
            await _navRepo.fetchScoresFromFirestore(widget.navigation.id);
        final match =
            scores.where((s) => s['navigatorId'] == navId).toList();
        if (match.isNotEmpty) {
          score = NavigationScore.fromMap(match.first);
        }
      } catch (_) {}

      // Track score for editing
      if (score != null) {
        _scores[navId] = score;
      }

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

      // חישוב פרופיל גובה
      final elevData = _analysisService.calculateElevationProfile(trackPoints: trackPoints);

      _navigatorDataMap[navId] = _NavigatorData(
        navigatorId: navId,
        trackPoints: trackPoints,
        punches: activePunches,
        plannedRoute: plannedRoute,
        routeCheckpoints: routeCps,
        score: score,
        plannedDistanceKm: route.routeLengthKm,
        actualDistanceKm: actualDistKm,
        totalDuration:
            totalDuration.isNegative ? Duration.zero : totalDuration,
        avgSpeedKmh: avgSpeedKmh,
        checkpointsHit: activePunches.length,
        totalCheckpoints: route.checkpointIds.length,
        color: color,
        totalAscent: elevData.ascent,
        totalDescent: elevData.descent,
        elevationProfile: elevData.profile,
      );
    }

    _selectedNavigatorId = widget.navigatorId ??
        (navigatorIds.isNotEmpty ? navigatorIds.first : null);
  }

  void _centerMapOnData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
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
          final lat =
              pointCps.map((c) => c.coordinates!.lat).reduce((a, b) => a + b) /
                  pointCps.length;
          final lng =
              pointCps.map((c) => c.coordinates!.lng).reduce((a, b) => a + b) /
                  pointCps.length;
          _mapController.move(LatLng(lat, lng), 14.0);
        }
      } catch (_) {}
    });
  }

  // ===========================================================================
  // Analysis
  // ===========================================================================

  void _computeAnalysis() {
    // ניתוח למנווט נבחר (commander)
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
          plannedRoute:
              data.plannedRoute.length >= 2 ? data.plannedRoute : null,
        );
        _selectedSpeedProfile = _selectedNavStats?.speedProfile ?? [];
        _selectedDeviations = data.plannedRoute.length >= 2
            ? _analysisService.analyzeDeviations(
                plannedRoute: data.plannedRoute,
                actualTrack: data.trackPoints,
              )
            : [];
      }
    } else if (widget.isNavigator && _myTrackPoints.length >= 2) {
      // ניתוח למנווט עצמו
      final uid = _myUserId;
      if (uid != null) {
        final route = widget.navigation.routes[uid];
        if (route != null) {
          _selectedNavStats = _analysisService.calculateStatistics(
            trackPoints: _myTrackPoints,
            checkpoints: _myCheckpoints,
            punches: _myPunches,
            route: route,
            plannedRoute:
                _myPlannedRoute.length >= 2 ? _myPlannedRoute : null,
          );
          _selectedSpeedProfile = _selectedNavStats?.speedProfile ?? [];
          _selectedDeviations = _myPlannedRoute.length >= 2
              ? _analysisService.analyzeDeviations(
                  plannedRoute: _myPlannedRoute,
                  actualTrack: _myTrackPoints,
                )
              : [];
        }
      }
    }

    // השוואת מנווטים (commander only)
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

  // ===========================================================================
  // Score Actions (Commander)
  // ===========================================================================

  Future<void> _calculateAllScores() async {
    setState(() => _isLoading = true);

    try {
      final criteria = _buildScoringCriteria();

      for (final entry in _navigatorDataMap.entries) {
        final navId = entry.key;
        final data = entry.value;

        final route = _currentNavigation.routes[navId];
        final score = _scoringService.calculateAutomaticScore(
          navigationId: widget.navigation.id,
          navigatorId: navId,
          punches: data.punches,
          verificationSettings: widget.navigation.verificationSettings,
          scoringCriteria: criteria,
          routeCheckpointIds: route?.checkpointIds,
        );

        _scores[navId] = score;
        _autoScores[navId] = score.totalScore;
      }

      // שמירת טיוטה ל-Firestore — כדי שהציונים לא יאבדו ביציאה מהמסך
      await _saveDraftScores();

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ציונים חושבו בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// שמירת כל הציונים שטרם הופצו כטיוטה ל-Firestore
  Future<void> _saveDraftScores() async {
    for (final entry in _scores.entries) {
      try {
        await _navRepo.pushScore(
          navigationId: widget.navigation.id,
          navigatorId: entry.key,
          scoreData: entry.value.toMap(),
        );
      } catch (e) {
        print('DEBUG: draft score save failed for ${entry.key}: $e');
      }
    }
  }

  void _editScore(String navigatorId) {
    final currentScore = _scores[navigatorId];
    if (currentScore == null) return;

    final criteria = _buildScoringCriteria();
    final isWeighted = criteria != null;

    // Deep copy checkpoint scores for editing
    final editedCheckpointScores = <String, CheckpointScore>{};
    for (final entry in currentScore.checkpointScores.entries) {
      editedCheckpointScores[entry.key] = CheckpointScore(
        checkpointId: entry.value.checkpointId,
        approved: entry.value.approved,
        score: entry.value.score,
        distanceMeters: entry.value.distanceMeters,
        rejectionReason: entry.value.rejectionReason,
        weight: entry.value.weight,
      );
    }

    // Deep copy custom criteria scores
    final editedCustomScores = Map<String, int>.from(
      currentScore.customCriteriaScores,
    );

    final notesController = TextEditingController(
      text: currentScore.notes ?? '',
    );
    bool totalOverride = false;
    final totalController = TextEditingController(
      text: currentScore.totalScore.toString(),
    );

    int calcTotal(Map<String, CheckpointScore> cpScores, Map<String, int> customScores) {
      if (isWeighted) {
        return ScoringService.calculateWeightedTotal(
          checkpointScores: cpScores,
          customCriteriaScores: customScores,
        );
      }
      return ScoringService.calculateAverage(cpScores);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final computedTotal = calcTotal(editedCheckpointScores, editedCustomScores);
            final displayTotal = totalOverride
                ? (int.tryParse(totalController.text) ?? computedTotal)
                : computedTotal;

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                final cpItems = editedCheckpointScores.entries.toList();
                final customItems = isWeighted ? _customCriteria : <CustomCriterion>[];
                final totalItems = cpItems.length + customItems.length;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Drag handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'עריכת ציון - ${_getNavigatorDisplayName(navigatorId)}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          // Total score circle
                          GestureDetector(
                            onTap: () {
                              setSheetState(() => totalOverride = !totalOverride);
                              if (!totalOverride) {
                                totalController.text = computedTotal.toString();
                              }
                            },
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: ScoringService.getScoreColor(displayTotal),
                              child: totalOverride
                                  ? SizedBox(
                                      width: 36,
                                      child: TextField(
                                        controller: totalController,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (_) => setSheetState(() {}),
                                      ),
                                    )
                                  : Text(
                                      '$displayTotal',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (_autoScores.containsKey(navigatorId))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text(
                                'ציון אוטומטי: ${_autoScores[navigatorId]}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                              if (isWeighted)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Text('(משוקלל)',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.blue)),
                                ),
                              if (totalOverride)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Text('(ציון ידני)',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.orange)),
                                ),
                            ],
                          ),
                        ),
                      const Divider(height: 16),
                      // Notes field
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'הערות',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      // Checkpoint list header
                      if (editedCheckpointScores.isNotEmpty)
                        Row(
                          children: [
                            const Text('פירוט לפי נקודה:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            if (isWeighted)
                              Text('  (משוקלל)',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.blue[600])),
                          ],
                        ),
                      const SizedBox(height: 4),
                      // Checkpoint + custom criteria list
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: totalItems,
                          itemBuilder: (_, index) {
                            // Custom criteria section
                            if (index >= cpItems.length) {
                              final criterion = customItems[index - cpItems.length];
                              final earned = editedCustomScores[criterion.id] ?? 0;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: Colors.purple[50],
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.purple, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(criterion.name,
                                            style: const TextStyle(fontWeight: FontWeight.w500)),
                                      ),
                                      Text('${criterion.weight} נק\'',
                                          style: TextStyle(fontSize: 11, color: Colors.purple[300])),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 56,
                                        height: 36,
                                        child: TextField(
                                          controller: TextEditingController(text: earned.toString()),
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          decoration: InputDecoration(
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 8),
                                            fillColor: Colors.purple.withOpacity(0.1),
                                            filled: true,
                                          ),
                                          onChanged: (val) {
                                            final newVal = (int.tryParse(val) ?? 0)
                                                .clamp(0, criterion.weight);
                                            setSheetState(() {
                                              editedCustomScores[criterion.id] = newVal;
                                              if (!totalOverride) {
                                                totalController.text = calcTotal(
                                                    editedCheckpointScores, editedCustomScores)
                                                    .toString();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            // Checkpoint score row
                            final cpEntry = cpItems[index];
                            final cpId = cpEntry.key;
                            final cpScore = cpEntry.value;
                            final matchCp = _navCheckpoints.where(
                              (c) =>
                                  c.sourceId == cpScore.checkpointId ||
                                  c.id == cpScore.checkpointId,
                            );
                            final cpName = matchCp.isNotEmpty
                                ? matchCp.first.name
                                : cpScore.checkpointId;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Approved toggle
                                        IconButton(
                                          icon: Icon(
                                            cpScore.approved
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            color: cpScore.approved
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          onPressed: () {
                                            setSheetState(() {
                                              final wasApproved = cpScore.approved;
                                              editedCheckpointScores[cpId] =
                                                  CheckpointScore(
                                                checkpointId:
                                                    cpScore.checkpointId,
                                                approved: !wasApproved,
                                                score: !wasApproved
                                                    ? (cpScore.score > 0
                                                        ? cpScore.score
                                                        : 100)
                                                    : 0,
                                                distanceMeters:
                                                    cpScore.distanceMeters,
                                                rejectionReason: wasApproved
                                                    ? cpScore.rejectionReason
                                                    : null,
                                                weight: cpScore.weight,
                                              );
                                              if (!totalOverride) {
                                                totalController.text =
                                                    calcTotal(editedCheckpointScores,
                                                        editedCustomScores)
                                                        .toString();
                                              }
                                            });
                                          },
                                          tooltip: cpScore.approved
                                              ? 'סמן כנכשל'
                                              : 'סמן כמאושר',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                        const SizedBox(width: 8),
                                        // Checkpoint name + weight
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(cpName,
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.w500)),
                                              ),
                                              if (cpScore.weight > 0)
                                                Text(' (${cpScore.weight} נק\')',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.blue[400])),
                                            ],
                                          ),
                                        ),
                                        // Distance (read-only)
                                        Text(
                                          '${cpScore.distanceMeters.toStringAsFixed(0)}מ\'',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey),
                                        ),
                                        const SizedBox(width: 8),
                                        // Score input
                                        SizedBox(
                                          width: 56,
                                          height: 36,
                                          child: TextField(
                                            controller: TextEditingController(
                                                text:
                                                    cpScore.score.toString()),
                                            keyboardType:
                                                TextInputType.number,
                                            textAlign: TextAlign.center,
                                            decoration: InputDecoration(
                                              border:
                                                  const OutlineInputBorder(),
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 8),
                                              fillColor: ScoringService
                                                      .getScoreColor(
                                                          cpScore.score)
                                                  .withOpacity(0.15),
                                              filled: true,
                                            ),
                                            onChanged: (val) {
                                              final newVal =
                                                  (int.tryParse(val) ?? 0)
                                                      .clamp(0, 100);
                                              setSheetState(() {
                                                editedCheckpointScores[cpId] =
                                                    CheckpointScore(
                                                  checkpointId:
                                                      cpScore.checkpointId,
                                                  approved: newVal > 0,
                                                  score: newVal,
                                                  distanceMeters:
                                                      cpScore.distanceMeters,
                                                  rejectionReason:
                                                      cpScore.rejectionReason,
                                                  weight: cpScore.weight,
                                                );
                                                if (!totalOverride) {
                                                  totalController.text =
                                                      calcTotal(editedCheckpointScores,
                                                          editedCustomScores)
                                                          .toString();
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Rejection reason (only when rejected)
                                    if (!cpScore.approved)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: TextField(
                                          controller: TextEditingController(
                                              text:
                                                  cpScore.rejectionReason ?? ''),
                                          decoration: const InputDecoration(
                                            labelText: 'סיבת דחייה',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                          ),
                                          style: const TextStyle(fontSize: 13),
                                          onChanged: (val) {
                                            editedCheckpointScores[cpId] =
                                                CheckpointScore(
                                              checkpointId:
                                                  cpScore.checkpointId,
                                              approved: cpScore.approved,
                                              score: cpScore.score,
                                              distanceMeters:
                                                  cpScore.distanceMeters,
                                              rejectionReason:
                                                  val.isEmpty ? null : val,
                                              weight: cpScore.weight,
                                            );
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Footer buttons
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              // Reset to auto
                              OutlinedButton.icon(
                                onPressed: () {
                                  final data = _navigatorDataMap[navigatorId];
                                  if (data == null) return;
                                  final autoScore =
                                      _scoringService.calculateAutomaticScore(
                                    navigationId: widget.navigation.id,
                                    navigatorId: navigatorId,
                                    punches: data.punches,
                                    verificationSettings:
                                        widget.navigation.verificationSettings,
                                    scoringCriteria: criteria,
                                  );
                                  setSheetState(() {
                                    editedCheckpointScores.clear();
                                    editedCheckpointScores.addAll(
                                        autoScore.checkpointScores);
                                    editedCustomScores.clear();
                                    totalOverride = false;
                                    totalController.text =
                                        autoScore.totalScore.toString();
                                    notesController.clear();
                                  });
                                },
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('איפוס לאוטומטי',
                                    style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                ),
                              ),
                              const Spacer(),
                              // Cancel
                              TextButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                child: const Text('ביטול'),
                              ),
                              const SizedBox(width: 8),
                              // Save
                              ElevatedButton.icon(
                                onPressed: () {
                                  final finalTotal = totalOverride
                                      ? (int.tryParse(totalController.text) ??
                                              computedTotal)
                                          .clamp(0, 100)
                                      : computedTotal;
                                  setState(() {
                                    _scores[navigatorId] =
                                        _scoringService.updateScore(
                                      currentScore,
                                      newTotalScore: finalTotal,
                                      newCheckpointScores:
                                          editedCheckpointScores,
                                      newNotes: notesController.text.isEmpty
                                          ? null
                                          : notesController.text,
                                    ).copyWith(
                                      customCriteriaScores: editedCustomScores,
                                    );
                                  });
                                  Navigator.pop(sheetContext);
                                  // שמירת טיוטה ל-Firestore
                                  _saveDraftScores();
                                },
                                icon: const Icon(Icons.save, size: 18),
                                label: const Text('שמור'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _publishScore(String navigatorId) async {
    final score = _scores[navigatorId];
    if (score == null) return;

    try {
      final published = _scoringService.publishScore(score);
      _scores[navigatorId] = published;

      await _navRepo.pushScore(
        navigationId: widget.navigation.id,
        navigatorId: navigatorId,
        scoreData: published.toMap(),
      );

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'ציון הופץ ל-${_getNavigatorDisplayName(navigatorId)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _publishAllScores() async {
    final unpublished =
        _scores.entries.where((e) => !e.value.isPublished).toList();

    if (unpublished.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('כל הציונים כבר הופצו')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('הפצת ציונים'),
        content: Text(
          'האם להפיץ ${unpublished.length} ציונים לכל המנווטים?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('הפץ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      for (final entry in unpublished) {
        final published = _scoringService.publishScore(entry.value);
        _scores[entry.key] = published;

        await _navRepo.pushScore(
          navigationId: widget.navigation.id,
          navigatorId: entry.key,
          scoreData: published.toMap(),
        );
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('כל הציונים הופצו בהצלחה!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================================
  // Save Full Navigation
  // ===========================================================================

  Future<void> _saveFullNavigation() async {
    try {
      // Build navigatorNames map
      final userRepo = UserRepository();
      final navigatorNames = <String, String>{};
      for (final navId in _currentNavigation.routes.keys) {
        final user = await userRepo.getUser(navId);
        if (user != null) {
          navigatorNames[navId] = user.fullName;
        } else {
          navigatorNames[navId] = _getNavigatorDisplayName(navId);
        }
      }

      final result = await _exportService.exportFullNavigation(
        navigation: _currentNavigation,
        navigatorNames: navigatorNames,
      );

      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ניווט נשמר בהצלחה: $result'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================================
  // Status Transitions & Navigation Actions
  // ===========================================================================

  Future<void> _returnToPreparation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('חזרה להכנה'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('האם להחזיר את הניווט למצב הכנה?'),
            SizedBox(height: 12),
            Text(
              'פעולה זו תמחק את כל הנתונים מהקלטת הניווט! אנא וודא קודם שייצאת את הניווט לקובץ ושמרת אותו כראוי.',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
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
        content: const Text(
            'פעולה זו בלתי הפיכה!\nכל נתוני הניווט יימחקו לצמיתות.'),
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

  // ===========================================================================
  // Export
  // ===========================================================================

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
    _exportService.showExportDialog(context,
        data: ExportData(
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

    _exportService.showExportDialog(context,
        data: ExportData(
          navigationName: widget.navigation.name,
          navigatorName: _getNavigatorDisplayName(navId),
          trackPoints: data.trackPoints,
          checkpoints: data.routeCheckpoints,
          punches: data.punches,
          plannedPath: route?.plannedPath,
        ));
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (widget.isNavigator) return _buildNavigatorView();
    return _buildCommanderView();
  }

  // ===========================================================================
  // Commander View — 4 tabs: מפה | ניתוח | ציונים | הגדרות
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
            Tab(icon: Icon(Icons.analytics), text: 'ניתוח'),
            Tab(icon: Icon(Icons.grade), text: 'ציונים'),
            Tab(icon: Icon(Icons.settings), text: 'הגדרות'),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'אפשרויות',
            onSelected: (value) {
              switch (value) {
                case 'back_to_preparation':
                  _returnToPreparation();
                  break;
                case 'save_navigation':
                  _saveFullNavigation();
                  break;
                case 'delete_navigation':
                  _deleteNavigation();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'back_to_preparation',
                child: Row(
                  children: [
                    Icon(Icons.undo, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('חזרה להכנה'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'save_navigation',
                child: Row(
                  children: [
                    Icon(Icons.save, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('שמירת ניווט'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete_navigation',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text('מחיקת ניווט'),
                  ],
                ),
              ),
            ],
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
                            onChanged: _onNavigatorChanged,
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
                      _buildAnalysisTab(),
                      _buildScoresTab(),
                      _buildSettingsTab(),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _isLoading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('סיום',
                        style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ===========================================================================
  // Map Tab (Commander)
  // ===========================================================================

  Widget _buildMapTab() {
    // TrackPoints for playback
    final playbackPoints = !_allNavigatorsMode &&
            _selectedNavigatorId != null &&
            _navigatorDataMap.containsKey(_selectedNavigatorId!)
        ? _navigatorDataMap[_selectedNavigatorId!]!.trackPoints
        : <TrackPoint>[];

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MapCaptureWrapper(
                captureKey: _mapCaptureKey,
                child: MapWithTypeSelector(
                  showTypeSelector: true,
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
              ),
              _buildMapControls(),
              // Heatmap legend
              if (_allNavigatorsMode && _showHeatmap)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: HeatmapLegend(),
                ),
            ],
          ),
        ),
        // Route playback
        if (_showPlayback && playbackPoints.length >= 2)
          Padding(
            padding: const EdgeInsets.all(8),
            child: RoutePlaybackWidget(
              trackPoints: playbackPoints,
              onPositionChanged: (pos) {
                _mapController.move(pos, _mapController.camera.zoom);
              },
            ),
          ),
        // Playback toggle bar
        if (!_allNavigatorsMode && playbackPoints.length >= 2)
          Container(
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showPlayback = !_showPlayback),
                  icon: Icon(
                    _showPlayback ? Icons.stop : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(
                      _showPlayback ? 'סגור נגן' : 'נגן מסלול',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // Map Layers (shared between Commander and Navigator)
  // ===========================================================================

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
                  color:
                      _kBoundaryColor.withValues(alpha: 0.1 * _ggOpacity),
                  borderColor:
                      _kBoundaryColor.withValues(alpha: _ggOpacity),
                  borderStrokeWidth: 2.0,
                  isFilled: true,
                ))
            .toList(),
      ),
    ];
  }

  List<Widget> _buildSafetyLayers() {
    if (!_showNB || _navSafetyPoints.isEmpty) return [];
    final pointSafety =
        _navSafetyPoints.where((p) => p.coordinates != null).toList();
    if (pointSafety.isEmpty) return [];
    return [
      MarkerLayer(
        markers: pointSafety
            .map((p) => Marker(
                  point:
                      LatLng(p.coordinates!.lat, p.coordinates!.lng),
                  width: 30,
                  height: 30,
                  child: Opacity(
                    opacity: _nbOpacity,
                    child: const Icon(Icons.warning_amber,
                        color: _kSafetyColor, size: 28),
                  ),
                ))
            .toList(),
      ),
    ];
  }

  /// איסוף כל מזהי נקודות התחלה/סיום מהצירים
  Set<String> _collectStartPointIds() {
    final ids = <String>{};
    for (final route in widget.navigation.routes.values) {
      if (route.startPointId != null) ids.add(route.startPointId!);
    }
    return ids;
  }

  Set<String> _collectEndPointIds() {
    final ids = <String>{};
    for (final route in widget.navigation.routes.values) {
      if (route.endPointId != null) ids.add(route.endPointId!);
    }
    return ids;
  }

  List<Widget> _buildCheckpointMarkers(
      List<nav.NavCheckpoint> checkpoints) {
    final pointCps = checkpoints
        .where((c) => !c.isPolygon && c.coordinates != null)
        .toList();
    if (pointCps.isEmpty) return [];

    // זיהוי סוג לפי הציר (startPointId/endPointId) — fallback ל-cp.type
    final startIds = _collectStartPointIds();
    final endIds = _collectEndPointIds();

    return [
      MarkerLayer(
        markers: pointCps.map((cp) {
          Color bgColor;
          String letter;

          // בדיקה לפי מזהה ציר (id או sourceId) — מקור אמין יותר מ-cp.type
          final isStart = startIds.contains(cp.id) ||
              startIds.contains(cp.sourceId) ||
              cp.type == 'start';
          final isEnd = endIds.contains(cp.id) ||
              endIds.contains(cp.sourceId) ||
              cp.type == 'end';

          if (isStart) {
            bgColor = _kStartColor;
            letter = 'H';
          } else if (isEnd) {
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
            color:
                _kPlannedRouteColor.withValues(alpha: _plannedOpacity),
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
              color:
                  _kActualRouteColor.withValues(alpha: _routesOpacity),
              strokeWidth: 3.0,
            ),
          ],
        ));
      }
    }

    // Deviation segments (colored overlay)
    if (_showDeviations &&
        _selectedDeviations.isNotEmpty &&
        data.trackPoints.isNotEmpty) {
      for (final dev in _selectedDeviations) {
        final devColor =
            _analysisService.getDeviationColor(dev.maxDeviation);
        final start =
            dev.startIndex.clamp(0, data.trackPoints.length - 1);
        final end =
            (dev.endIndex + 1).clamp(0, data.trackPoints.length);
        final devPoints = data.trackPoints
            .sublist(start, end)
            .map(
                (tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
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
        markers:
            data.punches.map((p) => _buildPunchMarker(p)).toList(),
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
        layers
            .add(NavigatorHeatmapLayer(navigatorTracks: heatTracks));
      }
    }

    for (final entry in _navigatorDataMap.entries) {
      final data = entry.value;

      if (_showRoutes && data.trackPoints.isNotEmpty) {
        final actualPoints = data.trackPoints
            .map(
                (tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
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
      width: 80,
      height: 45,
      child: Opacity(
        opacity: _punchesOpacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                punch.id,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
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
      onFullscreen: () {
        final camera = _mapController.camera;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => FullscreenMapScreen(
            title: 'מפת תחקיר',
            initialCenter: camera.center,
            initialZoom: camera.zoom,
            layerConfigs: [
              MapLayerConfig(
                id: 'gg', label: 'גבול גזרה', color: _kBoundaryColor,
                visible: _showGG, onVisibilityChanged: (_) {},
                opacity: _ggOpacity, onOpacityChanged: (_) {},
              ),
              MapLayerConfig(
                id: 'nz', label: 'נקודות ציון', color: Colors.blue,
                visible: _showNZ, onVisibilityChanged: (_) {},
                opacity: _nzOpacity, onOpacityChanged: (_) {},
              ),
              MapLayerConfig(
                id: 'nb', label: 'נקודות בטיחות', color: _kSafetyColor,
                visible: _showNB, onVisibilityChanged: (_) {},
                opacity: _nbOpacity, onOpacityChanged: (_) {},
              ),
              MapLayerConfig(
                id: 'planned', label: 'ציר מתוכנן', color: _kPlannedRouteColor,
                visible: _showPlanned, onVisibilityChanged: (_) {},
                opacity: _plannedOpacity, onOpacityChanged: (_) {},
              ),
              MapLayerConfig(
                id: 'routes', label: 'מסלול בפועל', color: _kActualRouteColor,
                visible: _showRoutes, onVisibilityChanged: (_) {},
                opacity: _routesOpacity, onOpacityChanged: (_) {},
              ),
              if (!_allNavigatorsMode)
                MapLayerConfig(
                  id: 'punches', label: 'דקירות', color: Colors.green,
                  visible: _showPunches, onVisibilityChanged: (_) {},
                  opacity: _punchesOpacity, onOpacityChanged: (_) {},
                ),
              if (!_allNavigatorsMode)
                MapLayerConfig(
                  id: 'deviations', label: 'סטיות', color: Colors.red,
                  visible: _showDeviations, onVisibilityChanged: (_) {},
                  opacity: 1.0, onOpacityChanged: (_) {},
                ),
              if (_allNavigatorsMode)
                MapLayerConfig(
                  id: 'heatmap', label: 'מפת חום', color: Colors.orange,
                  visible: _showHeatmap, onVisibilityChanged: (_) {},
                  opacity: 1.0, onOpacityChanged: (_) {},
                ),
            ],
            layerBuilder: (visibility, opacity) => [
              if (visibility['gg'] == true) ..._buildBoundaryLayers(),
              if (visibility['nb'] == true) ..._buildSafetyLayers(),
              if (_allNavigatorsMode)
                ..._buildAllNavigatorsRouteLayers()
              else
                ..._buildSingleNavigatorRouteLayers(),
              if (visibility['nz'] == true) ..._buildCheckpointMarkers(_navCheckpoints),
            ],
          ),
        ));
      },
      layers: [
        MapLayerConfig(
          id: 'gg',
          label: 'גבול גזרה',
          color: _kBoundaryColor,
          visible: _showGG,
          onVisibilityChanged: (v) => setState(() => _showGG = v),
          opacity: _ggOpacity,
          onOpacityChanged: (v) => setState(() => _ggOpacity = v),
        ),
        MapLayerConfig(
          id: 'nz',
          label: 'נקודות ציון',
          color: Colors.blue,
          visible: _showNZ,
          onVisibilityChanged: (v) => setState(() => _showNZ = v),
          opacity: _nzOpacity,
          onOpacityChanged: (v) => setState(() => _nzOpacity = v),
        ),
        MapLayerConfig(
          id: 'nb',
          label: 'נקודות בטיחות',
          color: _kSafetyColor,
          visible: _showNB,
          onVisibilityChanged: (v) => setState(() => _showNB = v),
          opacity: _nbOpacity,
          onOpacityChanged: (v) => setState(() => _nbOpacity = v),
        ),
        MapLayerConfig(
          id: 'planned',
          label: 'ציר מתוכנן',
          color: _kPlannedRouteColor,
          visible: _showPlanned,
          onVisibilityChanged: (v) =>
              setState(() => _showPlanned = v),
          opacity: _plannedOpacity,
          onOpacityChanged: (v) =>
              setState(() => _plannedOpacity = v),
        ),
        MapLayerConfig(
          id: 'routes',
          label: 'מסלול בפועל',
          color: _kActualRouteColor,
          visible: _showRoutes,
          onVisibilityChanged: (v) =>
              setState(() => _showRoutes = v),
          opacity: _routesOpacity,
          onOpacityChanged: (v) =>
              setState(() => _routesOpacity = v),
        ),
        if (!_allNavigatorsMode)
          MapLayerConfig(
            id: 'punches',
            label: 'דקירות',
            color: Colors.green,
            visible: _showPunches,
            onVisibilityChanged: (v) =>
                setState(() => _showPunches = v),
            opacity: _punchesOpacity,
            onOpacityChanged: (v) =>
                setState(() => _punchesOpacity = v),
          ),
        if (!_allNavigatorsMode)
          MapLayerConfig(
            id: 'deviations',
            label: 'סטיות',
            color: Colors.red,
            visible: _showDeviations,
            onVisibilityChanged: (v) =>
                setState(() => _showDeviations = v),
            opacity: 1.0,
            onOpacityChanged: (_) {},
          ),
        if (_allNavigatorsMode)
          MapLayerConfig(
            id: 'heatmap',
            label: 'מפת חום',
            color: Colors.orange,
            visible: _showHeatmap,
            onVisibilityChanged: (v) =>
                setState(() => _showHeatmap = v),
            opacity: 1.0,
            onOpacityChanged: (_) {},
          ),
      ],
    );
  }

  // ===========================================================================
  // Analysis Tab (Commander)
  // ===========================================================================

  Widget _buildAnalysisTab() {
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

          // Speed profile chart for selected navigator
          if (!_allNavigatorsMode &&
              _selectedSpeedProfile.isNotEmpty) ...[
            SpeedProfileChart(
              segments: _selectedSpeedProfile,
              thresholdSpeedKmh: 8.0,
            ),
            const SizedBox(height: 16),
          ],

          // Elevation profile chart for selected navigator
          if (!_allNavigatorsMode &&
              _selectedNavigatorId != null &&
              _navigatorDataMap[_selectedNavigatorId]?.elevationProfile.isNotEmpty == true) ...[
            ElevationProfileChart(
              segments: _navigatorDataMap[_selectedNavigatorId]!.elevationProfile,
              totalAscent: _navigatorDataMap[_selectedNavigatorId]!.totalAscent,
              totalDescent: _navigatorDataMap[_selectedNavigatorId]!.totalDescent,
            ),
            const SizedBox(height: 16),
          ],

          // Route analysis summary for selected navigator
          if (!_allNavigatorsMode &&
              _selectedNavStats != null) ...[
            _buildAnalysisSummaryCard(_selectedNavStats!),
            const SizedBox(height: 16),
          ],

          const Text('פירוט לפי מנווט',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildStatisticsTable(),

          // השוואת מנווטים
          if (_navigatorComparisons.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('השוואת מנווטים',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: NavigatorComparisonWidget(
                comparisons: _navigatorComparisons,
                navigatorColors: {
                  for (final entry in _navigatorDataMap.entries)
                    entry.key: entry.value.color,
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final totalNavigators = _navigatorDataMap.length;
    final withTracks = _navigatorDataMap.values
        .where((d) => d.trackPoints.isNotEmpty)
        .length;
    final withDistances = _navigatorDataMap.values
        .where((d) => d.actualDistanceKm > 0)
        .toList();
    final avgDistance = withDistances.isNotEmpty
        ? withDistances.fold(
                0.0, (sum, d) => sum + d.actualDistanceKm) /
            withDistances.length
        : 0.0;

    return Row(
      children: [
        Expanded(
            child: _summaryCard(
                icon: Icons.people,
                label: 'מנווטים',
                value: '$totalNavigators',
                color: Colors.blue)),
        const SizedBox(width: 8),
        Expanded(
            child: _summaryCard(
                icon: Icons.gps_fixed,
                label: 'עם מסלול',
                value: '$withTracks',
                color: Colors.green)),
        const SizedBox(width: 8),
        Expanded(
            child: _summaryCard(
                icon: Icons.route,
                label: 'מרחק ממוצע',
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisSummaryCard(RouteStatistics stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ניתוח מסלול',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _analysisStat(
                  'מרחק מתוכנן',
                  '${stats.plannedDistanceKm.toStringAsFixed(1)} ק"מ',
                  Icons.route,
                  Colors.red,
                )),
                Expanded(
                    child: _analysisStat(
                  'מרחק בפועל',
                  '${stats.actualDistanceKm.toStringAsFixed(1)} ק"מ',
                  Icons.timeline,
                  Colors.blue,
                )),
                Expanded(
                    child: _analysisStat(
                  'מהירות מקסימלית',
                  '${stats.maxSpeedKmh.toStringAsFixed(1)} קמ"ש',
                  Icons.speed,
                  Colors.orange,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _analysisStat(
                  'סטיות',
                  '${stats.deviationCount}',
                  Icons.warning,
                  Colors.red,
                )),
                Expanded(
                    child: _analysisStat(
                  'סטייה מקסימלית',
                  '${stats.maxDeviation.toStringAsFixed(0)} מ\'',
                  Icons.trending_up,
                  Colors.deepOrange,
                )),
                Expanded(
                    child: _analysisStat(
                  'נ.צ. שנדקרו',
                  '${stats.checkpointsPunched}/${stats.totalCheckpoints}',
                  Icons.flag,
                  Colors.green,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _analysisStat(
      String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 12)),
        Text(label,
            style: TextStyle(fontSize: 9, color: Colors.grey[600]),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildStatisticsTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 24,
        ),
        child: DataTable(
        columnSpacing: 14,
        headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
        columns: const [
          DataColumn(
              label: Text('מנווט',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('מרחק\nמתוכנן',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('מרחק\nבפועל',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('זמן',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('מהירות\nממוצעת',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('נ.צ.\nשנדקרו',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('↑↓',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(
              label: Text('ציון',
                  style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _navigatorDataMap.entries.map((entry) {
          final navId = entry.key;
          final data = entry.value;
          final score = _scores[navId];
          final scoreColor = score != null
              ? ScoringService.getScoreColor(score.totalScore)
              : Colors.grey;

          return DataRow(cells: [
            DataCell(
                Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: data.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(_getNavigatorDisplayName(navId),
                  style: const TextStyle(fontSize: 13)),
            ])),
            DataCell(Text(
                '${data.plannedDistanceKm.toStringAsFixed(1)} ק"מ')),
            DataCell(Text(data.actualDistanceKm > 0
                ? '${data.actualDistanceKm.toStringAsFixed(1)} ק"מ'
                : '-')),
            DataCell(Text(data.totalDuration.inSeconds > 0
                ? _formatDuration(data.totalDuration)
                : '-')),
            DataCell(Text(data.avgSpeedKmh > 0
                ? '${data.avgSpeedKmh.toStringAsFixed(1)} קמ"ש'
                : '-')),
            DataCell(Text(
                '${data.checkpointsHit}/${data.totalCheckpoints}')),
            DataCell(data.totalAscent > 0 || data.totalDescent > 0
                ? Text('↑${data.totalAscent.round()} ↓${data.totalDescent.round()}',
                    style: const TextStyle(fontSize: 11))
                : const Text('-', style: TextStyle(color: Colors.grey))),
            DataCell(score != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${score.totalScore}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scoreColor)),
                  )
                : const Text('-',
                    style: TextStyle(color: Colors.grey))),
          ]);
        }).toList(),
      ),
      ),
    );
  }

  // ===========================================================================
  // Scores Tab (Commander)
  // ===========================================================================

  Widget _buildScoresTab() {
    if (_navigatorDataMap.isEmpty) {
      return const Center(child: Text('אין נתונים'));
    }

    final publishedCount =
        _scores.values.where((s) => s.isPublished).length;
    final totalScores = _scores.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scoring criteria configuration
          _buildScoringCriteriaCard(),

          const SizedBox(height: 12),

          // Actions bar
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _calculateAllScores,
                          icon:
                              const Icon(Icons.calculate, size: 18),
                          label: const Text('חשב ציונים'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _scores.isNotEmpty
                              ? _publishAllScores
                              : null,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('הפץ הכל'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (totalScores > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$publishedCount/$totalScores ציונים הופצו',
                      style: TextStyle(
                        fontSize: 12,
                        color: publishedCount == totalScores
                            ? Colors.green[700]
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Score cards
          const Text('ציונים',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._navigatorDataMap.entries.map((entry) =>
              _buildNavigatorScoreCard(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildScoringCriteriaCard() {
    // חישוב סה"כ משקלים — נקודות למנווט (לא כלל הנקודות)
    int cpCount = _currentNavigation.checkpointsPerNavigator ?? 0;
    if (cpCount == 0 && _navigatorDataMap.isNotEmpty) {
      cpCount = _navigatorDataMap.values.first.totalCheckpoints;
    }
    if (cpCount == 0) {
      cpCount = _navCheckpoints
          .where((c) => c.type != 'start' && c.type != 'end' && !c.isPolygon)
          .length;
    }
    int totalCpWeight;
    if (_scoringMode == 'equal') {
      totalCpWeight = _equalWeight * cpCount;
    } else {
      totalCpWeight = _customWeights.values.fold(0, (s, w) => s + w);
    }
    final customWeight = _customCriteria.fold(0, (s, c) => s + c.weight);
    final totalWeight = totalCpWeight + customWeight;
    final isValid = totalWeight <= 100;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.indigo[700]),
                const SizedBox(width: 8),
                const Text('קריטריוני ניקוד',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),

            // Mode toggle
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'equal', label: Text('ניקוד שווה')),
                ButtonSegment(value: 'custom', label: Text('ניקוד מותאם')),
              ],
              selected: {_scoringMode},
              onSelectionChanged: (values) {
                setState(() => _scoringMode = values.first);
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Colors.indigo[100],
              ),
            ),
            const SizedBox(height: 12),

            // Equal mode
            if (_scoringMode == 'equal') ...[
              Row(
                children: [
                  const Text('משקל לכל נקודה: '),
                  SizedBox(
                    width: 60,
                    height: 36,
                    child: TextField(
                      controller: TextEditingController(text: _equalWeight.toString()),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      onChanged: (val) {
                        setState(() => _equalWeight = int.tryParse(val) ?? 0);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$_equalWeight × $cpCount נק\' למנווט = $totalCpWeight',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ],

            // Custom mode — לפי מיקום בציר (position-based)
            if (_scoringMode == 'custom') ...[
              const Text('משקל לכל נקודה:',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              const SizedBox(height: 6),
              ...List.generate(cpCount, (i) {
                final key = i.toString();
                final weight = _customWeights[key] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('נ.צ. ${i + 1}', style: const TextStyle(fontSize: 13)),
                      ),
                      SizedBox(
                        width: 56,
                        height: 32,
                        child: TextField(
                          controller: TextEditingController(text: weight.toString()),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _customWeights[key] = int.tryParse(val) ?? 0;
                            });
                          },
                        ),
                      ),
                      const Text(' נק\'', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }),
            ],

            const Divider(height: 20),

            // Custom criteria section
            Row(
              children: [
                const Text('קריטריונים נוספים',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _customCriteria.add(CustomCriterion(
                        id: 'crit_${DateTime.now().millisecondsSinceEpoch}',
                        name: '',
                        weight: 0,
                      ));
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('הוסף', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            ..._customCriteria.asMap().entries.map((entry) {
              final idx = entry.key;
              final criterion = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: TextEditingController(text: criterion.name),
                        decoration: const InputDecoration(
                          hintText: 'שם קריטריון',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (val) {
                          _customCriteria[idx] = criterion.copyWith(name: val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      height: 36,
                      child: TextField(
                        controller: TextEditingController(text: criterion.weight.toString()),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _customCriteria[idx] = criterion.copyWith(
                              weight: int.tryParse(val) ?? 0,
                            );
                          });
                        },
                      ),
                    ),
                    const Text(' נק\'', style: TextStyle(fontSize: 12)),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() => _customCriteria.removeAt(idx));
                      },
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 12),

            // Summary bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isValid ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isValid ? Colors.green : Colors.red,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'סה"כ: $totalWeight/100',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isValid ? Colors.green[800] : Colors.red[800],
                    ),
                  ),
                  Icon(
                    isValid ? Icons.check_circle : Icons.error,
                    color: isValid ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveScoringCriteria,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('שמור קריטריונים'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigatorScoreCard(
      String navigatorId, _NavigatorData data) {
    final score = _scores[navigatorId];
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
          subtitle: Text(
            'נ.צ.: ${data.checkpointsHit}/${data.totalCheckpoints}  |  '
            'מרחק: ${data.actualDistanceKm.toStringAsFixed(1)} ק"מ',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.remove_circle_outline,
              color: Colors.grey),
        ),
      );
    }

    final scoreColor =
        ScoringService.getScoreColor(score.totalScore);
    final grade = _scoringService.getGrade(score.totalScore);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: GestureDetector(
            onTap: () => _editScore(navigatorId),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scoreColor.withOpacity(0.15),
                    border: Border.all(
                      color: score.isManual
                          ? Colors.orange
                          : scoreColor,
                      width: 3,
                    ),
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
                Positioned(
                  top: -4,
                  left: -4,
                  child: Icon(Icons.edit,
                      size: 16,
                      color: score.isManual
                          ? Colors.orange
                          : Colors.grey[400]),
                ),
              ],
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold)),
              ),
              if (score.isManual)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text('ידני',
                      style: TextStyle(
                          fontSize: 10, color: Colors.orange)),
                ),
              if (score.isPublished)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Text('הופץ',
                      style: TextStyle(
                          fontSize: 10, color: Colors.green)),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'נ.צ.: ${data.checkpointsHit}/${data.totalCheckpoints}  |  '
                'מרחק: ${data.actualDistanceKm.toStringAsFixed(1)} ק"מ',
                style: const TextStyle(fontSize: 12),
              ),
              if (score.isManual &&
                  _autoScores.containsKey(navigatorId))
                Text(
                  'ציון אוטומטי: ${_autoScores[navigatorId]}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic),
                ),
            ],
          ),
          children: [
            // Checkpoint details
            if (score.checkpointScores.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('פירוט לפי נקודה:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(height: 6),
                    ...score.checkpointScores.entries
                        .map((cpEntry) {
                      final cpScore = cpEntry.value;
                      final matchCp = _navCheckpoints.where(
                        (c) =>
                            c.sourceId ==
                                cpScore.checkpointId ||
                            c.id == cpScore.checkpointId,
                      );
                      final cpName = matchCp.isNotEmpty
                          ? matchCp.first.name
                          : cpScore.checkpointId;
                      final cpScoreColor =
                          ScoringService.getScoreColor(
                              cpScore.score);
                      final weightedPoints = cpScore.weight > 0
                          ? (cpScore.weight * cpScore.score / 100.0).round()
                          : null;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 3),
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
                                child: Row(
                              children: [
                                Flexible(child: Text(cpName,
                                    style: const TextStyle(
                                        fontSize: 12))),
                                if (cpScore.weight > 0)
                                  Text(' (${cpScore.weight} נק\')',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue[400])),
                              ],
                            )),
                            Text(
                                '${cpScore.distanceMeters.toStringAsFixed(0)}מ\'',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey)),
                            const SizedBox(width: 8),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2),
                              decoration: BoxDecoration(
                                color: cpScoreColor
                                    .withOpacity(0.2),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                  weightedPoints != null
                                      ? '$weightedPoints/${cpScore.weight}'
                                      : '${cpScore.score}',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      color: cpScoreColor,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    }),
                    // Custom criteria scores
                    if (score.customCriteriaScores.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('קריטריונים נוספים:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      ...score.customCriteriaScores.entries.map((ccEntry) {
                        final criterion = _customCriteria
                            .where((c) => c.id == ccEntry.key)
                            .toList();
                        final name = criterion.isNotEmpty
                            ? criterion.first.name
                            : ccEntry.key;
                        final maxWeight = criterion.isNotEmpty
                            ? criterion.first.weight
                            : ccEntry.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.star, size: 16, color: Colors.purple),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name,
                                  style: const TextStyle(fontSize: 12))),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('${ccEntry.value}/$maxWeight',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple,
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editScore(navigatorId),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('ערוך',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: score.isPublished
                          ? null
                          : () => _publishScore(navigatorId),
                      icon: Icon(
                        score.isPublished
                            ? Icons.check
                            : Icons.send,
                        size: 16,
                      ),
                      label: Text(
                        score.isPublished ? 'הופץ' : 'הפץ',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Settings Tab (Commander)
  // ===========================================================================

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Text(
                      'הגדרות אישור',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('אישור אוטומטי'),
                  subtitle: const Text(
                      'חישוב ציונים לפי הגדרות הניווט'),
                  value: _autoApprovalEnabled,
                  onChanged: (value) {
                    setState(() =>
                        _autoApprovalEnabled = value ?? true);
                  },
                ),
                if (_autoApprovalEnabled) ...[
                  const Divider(),
                  Text(
                    'שיטה: ${widget.navigation.verificationSettings.verificationType ?? "אישור/נכשל"}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (widget.navigation.verificationSettings
                          .verificationType ==
                      'approved_failed')
                    Text(
                      'מרחק אישור: ${widget.navigation.verificationSettings.approvalDistance ?? 50}m',
                      style: const TextStyle(fontSize: 14),
                    ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // סיכום מנווטים
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.people, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Text(
                      'רשימת מנווטים',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._navigatorDataMap.entries.map((entry) {
                  final navId = entry.key;
                  final data = entry.value;
                  final score = _scores[navId];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          data.color.withOpacity(0.2),
                      child: Icon(Icons.person,
                          color: data.color, size: 20),
                    ),
                    title: Text(
                        _getNavigatorDisplayName(navId)),
                    subtitle: Text(
                      '${data.checkpointsHit}/${data.totalCheckpoints} נ.צ.  |  '
                      '${data.trackPoints.isNotEmpty ? "יש מסלול" : "אין מסלול"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: score != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: ScoringService.getScoreColor(
                                      score.totalScore)
                                  .withOpacity(0.2),
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${score.totalScore}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    ScoringService.getScoreColor(
                                        score.totalScore),
                              ),
                            ),
                          )
                        : const Text('-',
                            style:
                                TextStyle(color: Colors.grey)),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Navigator View — single scroll
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
            pointCps
                    .map((c) => c.coordinates!.lat)
                    .reduce((a, b) => a + b) /
                pointCps.length,
            pointCps
                    .map((c) => c.coordinates!.lng)
                    .reduce((a, b) => a + b) /
                pointCps.length,
          )
        : const LatLng(32.0853, 34.7818);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text('תחקור ניווט',
                style: TextStyle(fontSize: 14)),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          MapExportButton(
            captureKey: _mapCaptureKey,
            navigationName: widget.navigation.name,
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'ייצוא',
            onPressed: _onExport,
          ),
        ],
      ),
      body: Column(
        children: [
          // Score header
          _buildNavigatorScoreSection(),
          // Stats row
          _buildNavigatorStatsRow(),
          // Map
          Expanded(
            child: Stack(
              children: [
                MapCaptureWrapper(
                  captureKey: _mapCaptureKey,
                  child: MapWithTypeSelector(
                    showTypeSelector: true,
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 14.0,
                      onTap: (tapPosition, point) {
                        if (_measureMode) {
                          setState(
                              () => _measurePoints.add(point));
                        }
                      },
                    ),
                    layers: [
                      ..._buildBoundaryLayers(),
                      // Planned route (RED)
                      if (_showPlanned &&
                          _myPlannedRoute.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _myPlannedRoute,
                              color: _kPlannedRouteColor
                                  .withValues(
                                      alpha: _plannedOpacity),
                              strokeWidth: 4.0,
                            ),
                          ],
                        ),
                      // Actual route (BLUE)
                      if (_showRoutes &&
                          _myActualRoute.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _myActualRoute,
                              color: _kActualRouteColor
                                  .withValues(
                                      alpha: _routesOpacity),
                              strokeWidth: 3.0,
                            ),
                          ],
                        ),
                      // Deviation segments overlay
                      if (_showDeviations &&
                          _selectedDeviations.isNotEmpty &&
                          _myTrackPoints.isNotEmpty)
                        for (final dev in _selectedDeviations)
                          if (() {
                            final start = dev.startIndex.clamp(
                                0, _myTrackPoints.length - 1);
                            final end = (dev.endIndex + 1).clamp(
                                0, _myTrackPoints.length);
                            return end - start > 1;
                          }())
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _myTrackPoints
                                      .sublist(
                                        dev.startIndex.clamp(0,
                                            _myTrackPoints.length - 1),
                                        (dev.endIndex + 1).clamp(0,
                                            _myTrackPoints.length),
                                      )
                                      .map((tp) => LatLng(
                                          tp.coordinate.lat,
                                          tp.coordinate.lng))
                                      .toList(),
                                  color: _analysisService
                                      .getDeviationColor(
                                          dev.maxDeviation)
                                      .withValues(alpha: 0.8),
                                  strokeWidth: 6.0,
                                ),
                              ],
                            ),
                      // Checkpoints
                      if (_showNZ)
                        ..._buildCheckpointMarkers(
                            _myCheckpoints),
                      // Safety
                      ..._buildSafetyLayers(),
                      // Punches
                      if (_showPunches &&
                          _myPunches.isNotEmpty)
                        MarkerLayer(
                          markers: _myPunches
                              .map((p) =>
                                  _buildPunchMarker(p))
                              .toList(),
                        ),
                      ...MapControls.buildMeasureLayers(
                          _measurePoints),
                    ],
                  ),
                ),
                _buildMapControls(),
              ],
            ),
          ),
          // Route playback
          if (_showPlayback && _myTrackPoints.length >= 2)
            Padding(
              padding: const EdgeInsets.all(8),
              child: RoutePlaybackWidget(
                trackPoints: _myTrackPoints,
                onPositionChanged: (pos) {
                  _mapController.move(
                      pos, _mapController.camera.zoom);
                },
              ),
            ),
          // Speed profile + analysis + controls bar
          Container(
            color: Colors.grey[100],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Playback + deviation toggles
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_myTrackPoints.length >= 2)
                      TextButton.icon(
                        onPressed: () => setState(() =>
                            _showPlayback = !_showPlayback),
                        icon: Icon(
                          _showPlayback
                              ? Icons.stop
                              : Icons.play_arrow,
                          size: 16,
                        ),
                        label: Text(
                            _showPlayback
                                ? 'סגור נגן'
                                : 'נגן מסלול',
                            style:
                                const TextStyle(fontSize: 11)),
                      ),
                    if (_selectedDeviations.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() =>
                            _showDeviations =
                                !_showDeviations),
                        icon: Icon(
                          _showDeviations
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 16,
                          color: Colors.red,
                        ),
                        label: Text(
                            _showDeviations
                                ? 'הסתר סטיות'
                                : 'הצג סטיות',
                            style:
                                const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
                // Speed profile chart
                if (_selectedSpeedProfile.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: SpeedProfileChart(
                      segments: _selectedSpeedProfile,
                      thresholdSpeedKmh: 8.0,
                    ),
                  ),
                // Elevation profile chart
                if (_selectedNavigatorId != null &&
                    _navigatorDataMap[_selectedNavigatorId]?.elevationProfile.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: ElevationProfileChart(
                      segments: _navigatorDataMap[_selectedNavigatorId]!.elevationProfile,
                      totalAscent: _navigatorDataMap[_selectedNavigatorId]!.totalAscent,
                      totalDescent: _navigatorDataMap[_selectedNavigatorId]!.totalDescent,
                    ),
                  ),
                // Analysis summary
                if (_selectedNavStats != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: _buildAnalysisSummaryCard(
                        _selectedNavStats!),
                  ),
                // Legend
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceAround,
                    children: [
                      _legendItem(
                          _kPlannedRouteColor, 'ציר מתוכנן'),
                      _legendItem(
                          _kActualRouteColor, 'מסלול בפועל'),
                      _legendItem(_kStartColor, 'התחלה (H)'),
                      _legendItem(_kEndColor, 'סיום (S)'),
                    ],
                  ),
                ),
                // Score details (expandable, only after publication)
                if (_myScore != null && _myScore!.isPublished)
                  _buildNavigatorScoreDetails(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Navigator Score Section
  // ===========================================================================

  Widget _buildNavigatorScoreSection() {
    if (_myScore != null && _myScore!.isPublished) {
      return _buildNavigatorScoreHeader();
    }
    // Scores not published yet
    return Card(
      margin: const EdgeInsets.all(12),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.hourglass_empty,
                color: Colors.amber[900]),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ממתין לפרסום ציונים מהמפקד',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigatorScoreHeader() {
    final score = _myScore!;
    final scoreColor =
        ScoringService.getScoreColor(score.totalScore);

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
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    score.totalScore >= 80
                        ? 'כל הכבוד! ביצוע מעולה'
                        : score.totalScore >= 60
                            ? 'ביצוע טוב'
                            : 'נדרש שיפור',
                    style: TextStyle(
                        color: scoreColor, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'נ.צ. שנדקרו: ${_myPunches.length}/${_myCheckpoints.length}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigatorScoreDetails() {
    final score = _myScore;
    if (score == null || !score.isPublished) {
      return const SizedBox.shrink();
    }

    if (score.checkpointScores.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 8),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('פירוט ציון',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          children: [
            ...score.checkpointScores.entries.map((cpEntry) {
              final cpScore = cpEntry.value;
              final matchCp = _navCheckpoints.where(
                (c) =>
                    c.sourceId == cpScore.checkpointId ||
                    c.id == cpScore.checkpointId,
              );
              final cpName = matchCp.isNotEmpty
                  ? matchCp.first.name
                  : cpScore.checkpointId;
              final cpScoreColor =
                  ScoringService.getScoreColor(cpScore.score);

              return Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 3),
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
                            style: const TextStyle(
                                fontSize: 12))),
                    Text(
                        '${cpScore.distanceMeters.toStringAsFixed(0)}מ\'',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            cpScoreColor.withOpacity(0.2),
                        borderRadius:
                            BorderRadius.circular(8),
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
            if (score.notes != null &&
                score.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.note,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      score.notes!,
                      style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey),
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

  Widget _buildNavigatorStatsRow() {
    final actualCoords = _myActualRoute
        .map((ll) => Coordinate(
            lat: ll.latitude, lng: ll.longitude, utm: ''))
        .toList();
    final actualDistKm =
        GeometryUtils.calculatePathLengthKm(actualCoords);

    final uid = _myUserId;
    final route = uid != null
        ? widget.navigation.routes[uid]
        : (widget.navigation.routes.values.isNotEmpty
            ? widget.navigation.routes.values.first
            : null);
    final plannedDistKm = route?.routeLengthKm ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8),
      color: Colors.grey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip(Icons.route,
              '${plannedDistKm.toStringAsFixed(1)} ק"מ', 'מתוכנן'),
          _statChip(Icons.timeline,
              '${actualDistKm.toStringAsFixed(1)} ק"מ', 'בפועל'),
          _statChip(Icons.flag,
              '${_myPunches.length}/${_myCheckpoints.length}', 'נ.צ.'),
        ],
      ),
    );
  }

  // ===========================================================================
  // Small Helpers
  // ===========================================================================

  Widget _statChip(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label,
            style:
                TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
              color: color, shape: BoxShape.circle),
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
  final double totalAscent;
  final double totalDescent;
  final List<ElevationSegment> elevationProfile;

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
    this.totalAscent = 0,
    this.totalDescent = 0,
    this.elevationProfile = const [],
  });
}
