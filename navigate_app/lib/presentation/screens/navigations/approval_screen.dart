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
import '../../widgets/fullscreen_map_screen.dart';
import '../home/navigator_views/approval_view.dart';

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

/// מסך אישור ניווט וחישוב ציונים
class ApprovalScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool isNavigator;

  const ApprovalScreen({
    super.key,
    required this.navigation,
    this.isNavigator = false,
  });

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen>
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

  // ציונים (עריכה מקומית)
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

  // הגדרות אישור
  bool _autoApprovalEnabled = true;

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

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
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

      if (!widget.isNavigator) {
        await _loadCommanderData();
        _computeAnalysis();
        _centerMapOnData();
      }
    } catch (e) {
      print('DEBUG ApprovalScreen: Error loading data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
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
        isDisqualified: track?.isDisqualified ?? false,
      );
    }

    _selectedNavigatorId =
        navigatorIds.isNotEmpty ? navigatorIds.first : null;
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
    final navId = _selectedNavigatorId;
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
    }

    // השוואת מנווטים
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
  // Score Actions
  // ===========================================================================

  Future<void> _calculateAllScores() async {
    setState(() => _isLoading = true);

    try {
      final criteria = _currentNavigation.reviewSettings.scoringCriteria;

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
          isDisqualified: data.isDisqualified,
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

    final criteria = _currentNavigation.reviewSettings.scoringCriteria;
    final isWeighted = criteria != null;

    final scoreController = TextEditingController(
      text: currentScore.totalScore.toString(),
    );
    final notesController = TextEditingController(
      text: currentScore.notes ?? '',
    );

    // Custom criteria scores for editing
    final editedCustomScores = Map<String, int>.from(
      currentScore.customCriteriaScores,
    );

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('עריכת ציון - ${_getNavigatorDisplayName(navigatorId)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: scoreController,
                  decoration: InputDecoration(
                    labelText: 'ציון (0-100)',
                    border: const OutlineInputBorder(),
                    helperText: _autoScores.containsKey(navigatorId)
                        ? 'ציון אוטומטי: ${_autoScores[navigatorId]}${isWeighted ? ' (משוקלל)' : ''}'
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                // Custom criteria inputs (only when weighted)
                if (isWeighted && criteria.customCriteria.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('קריטריונים נוספים:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(height: 8),
                  ...criteria.customCriteria.map((criterion) {
                    final earned = editedCustomScores[criterion.id] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(criterion.name,
                              style: const TextStyle(fontSize: 13))),
                          SizedBox(
                            width: 56,
                            child: TextField(
                              controller: TextEditingController(text: earned.toString()),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 8),
                                suffixText: '/${criterion.weight}',
                                suffixStyle: const TextStyle(fontSize: 10),
                              ),
                              onChanged: (val) {
                                setDialogState(() {
                                  editedCustomScores[criterion.id] =
                                      (int.tryParse(val) ?? 0).clamp(0, criterion.weight);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'הערות',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                final newScore = int.tryParse(scoreController.text) ?? currentScore.totalScore;
                setState(() {
                  _scores[navigatorId] = _scoringService.updateScore(
                    currentScore,
                    newTotalScore: newScore.clamp(0, 100),
                    newNotes: notesController.text,
                  ).copyWith(
                    customCriteriaScores: editedCustomScores,
                  );
                });
                Navigator.pop(dialogContext);
                // שמירת טיוטה ל-Firestore
                _saveDraftScores();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
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
            content: Text('ציון הופץ ל-${_getNavigatorDisplayName(navigatorId)}'),
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
    final unpublished = _scores.entries
        .where((e) => !e.value.isPublished)
        .toList();

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
  // Undo Disqualification
  // ===========================================================================

  Future<void> _undoDisqualification(String navigatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ביטול פסילה'),
        content: Text(
          'לבטל את פסילת ${_getNavigatorDisplayName(navigatorId)}?\n\n'
          'הנתונים יישמרו והציון יחושב מחדש.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('בטל פסילה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // מציאת track מ-Firestore
      final tracks = await _trackRepo.getByNavigationFromFirestore(
          widget.navigation.id);
      final navTrack = tracks.where((t) => t.navigatorUserId == navigatorId).toList();

      if (navTrack.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('לא נמצא track למנווט'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // ביטול פסילה ב-Drift + Firestore
      await _trackRepo.undoDisqualification(navTrack.first.id);

      // עדכון הנתונים המקומיים
      final data = _navigatorDataMap[navigatorId];
      if (data != null) {
        _navigatorDataMap[navigatorId] = _NavigatorData(
          navigatorId: data.navigatorId,
          trackPoints: data.trackPoints,
          punches: data.punches,
          plannedRoute: data.plannedRoute,
          routeCheckpoints: data.routeCheckpoints,
          score: data.score,
          plannedDistanceKm: data.plannedDistanceKm,
          actualDistanceKm: data.actualDistanceKm,
          totalDuration: data.totalDuration,
          avgSpeedKmh: data.avgSpeedKmh,
          checkpointsHit: data.checkpointsHit,
          totalCheckpoints: data.totalCheckpoints,
          color: data.color,
          isDisqualified: false,
        );
      }

      // חישוב ציון מחדש (ללא פסילה)
      final criteria = _currentNavigation.reviewSettings.scoringCriteria;
      final route = _currentNavigation.routes[navigatorId];
      final updatedData = _navigatorDataMap[navigatorId]!;
      final newScore = _scoringService.calculateAutomaticScore(
        navigationId: widget.navigation.id,
        navigatorId: navigatorId,
        punches: updatedData.punches,
        verificationSettings: widget.navigation.verificationSettings,
        scoringCriteria: criteria,
        isDisqualified: false,
        routeCheckpointIds: route?.checkpointIds,
      );
      _scores[navigatorId] = newScore;
      _autoScores[navigatorId] = newScore.totalScore;

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הפסילה של ${_getNavigatorDisplayName(navigatorId)} בוטלה — ציון חושב מחדש: ${newScore.totalScore}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בביטול פסילה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // Status Transitions
  // ===========================================================================

  Future<void> _moveToReview() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('המשך לתחקור'),
        content: const Text(
          'האם להעביר את הניווט למצב תחקור?\n\n'
          'הפצת ציונים אינה חובה — ניתן להפיץ גם בהמשך.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('המשך לתחקור'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updatedNav = _currentNavigation.copyWith(
        status: 'review',
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

  // _returnToPreparation and _deleteNavigation removed — no longer in bottom bar

  void _onExport() {
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

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (widget.isNavigator) return _buildNavigatorView();
    return _buildCommanderView();
  }

  // ===========================================================================
  // Navigator View — wraps ApprovalView
  // ===========================================================================

  Widget _buildNavigatorView() {
    return FutureBuilder(
      future: AuthService().getCurrentUser(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.navigation.name),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data!;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.navigation.name),
                const Text('ממתין לאישור', style: TextStyle(fontSize: 14)),
              ],
            ),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              // הודעת המתנה
              Card(
                margin: const EdgeInsets.all(12),
                color: Colors.amber[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_empty, color: Colors.amber[900]),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'הניווט הסתיים - ממתין לאישור המפקד',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ApprovalView widget
              Expanded(
                child: ApprovalView(
                  navigation: widget.navigation,
                  currentUser: user,
                ),
              ),
            ],
          ),
        );
      },
    );
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
            const Text('אישור ניווט', style: TextStyle(fontSize: 14)),
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
      bottomNavigationBar: _isLoading ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _moveToReview,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('הבא', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
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
  // Map Tab
  // ===========================================================================

  Widget _buildMapTab() {
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
                    ..._buildBoundaryLayers(),
                    ..._buildSafetyLayers(),
                    if (_allNavigatorsMode)
                      ..._buildAllNavigatorsRouteLayers()
                    else
                      ..._buildSingleNavigatorRouteLayers(),
                    if (_showNZ) ..._buildCheckpointMarkers(_navCheckpoints),
                    ...MapControls.buildMeasureLayers(_measurePoints),
                  ],
                ),
              ),
              _buildMapControls(),
              if (_allNavigatorsMode && _showHeatmap)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: HeatmapLegend(),
                ),
            ],
          ),
        ),
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
        if (!_allNavigatorsMode && playbackPoints.length >= 2)
          Container(
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _showPlayback = !_showPlayback),
                  icon: Icon(
                    _showPlayback ? Icons.stop : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(_showPlayback ? 'סגור נגן' : 'נגן מסלול',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
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
    if (pointSafety.isEmpty) return [];
    return [
      MarkerLayer(
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
      ),
    ];
  }

  List<Widget> _buildCheckpointMarkers(List<nav.NavCheckpoint> checkpoints) {
    final pointCps = checkpoints
        .where((c) => !c.isPolygon && c.coordinates != null)
        .toList();
    if (pointCps.isEmpty) return [];

    // זיהוי סוג לפי הציר (startPointId/endPointId) — fallback ל-cp.type
    final startIds = <String>{};
    final endIds = <String>{};
    for (final route in _currentNavigation.routes.values) {
      if (route.startPointId != null) startIds.add(route.startPointId!);
      if (route.endPointId != null) endIds.add(route.endPointId!);
    }

    return [
      MarkerLayer(
        markers: pointCps.map((cp) {
          Color bgColor;
          String letter;

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

    // Deviation segments
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
            title: 'מפת אישור',
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
  // Analysis Tab
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

          if (!_allNavigatorsMode && _selectedSpeedProfile.isNotEmpty) ...[
            SpeedProfileChart(
              segments: _selectedSpeedProfile,
              thresholdSpeedKmh: 8.0,
            ),
            const SizedBox(height: 16),
          ],

          if (!_allNavigatorsMode && _selectedNavStats != null) ...[
            _buildAnalysisSummaryCard(_selectedNavStats!),
            const SizedBox(height: 16),
          ],

          const Text('פירוט לפי מנווט',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _buildAnalysisSummaryCard(RouteStatistics stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ניתוח מסלול',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _analysisStat(
                  'מרחק מתוכנן',
                  '${stats.plannedDistanceKm.toStringAsFixed(1)} ק"מ',
                  Icons.route, Colors.red,
                )),
                Expanded(child: _analysisStat(
                  'מרחק בפועל',
                  '${stats.actualDistanceKm.toStringAsFixed(1)} ק"מ',
                  Icons.timeline, Colors.blue,
                )),
                Expanded(child: _analysisStat(
                  'מהירות מקסימלית',
                  '${stats.maxSpeedKmh.toStringAsFixed(1)} קמ"ש',
                  Icons.speed, Colors.orange,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _analysisStat(
                  'סטיות',
                  '${stats.deviationCount}',
                  Icons.warning, Colors.red,
                )),
                Expanded(child: _analysisStat(
                  'סטייה מקסימלית',
                  '${stats.maxDeviation.toStringAsFixed(0)} מ\'',
                  Icons.trending_up, Colors.deepOrange,
                )),
                Expanded(child: _analysisStat(
                  'נ.צ. שנדקרו',
                  '${stats.checkpointsPunched}/${stats.totalCheckpoints}',
                  Icons.flag, Colors.green,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _analysisStat(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
          final score = _scores[navId];
          final scoreColor = score != null
              ? ScoringService.getScoreColor(score.totalScore)
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
              if (data.isDisqualified) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('נפסל',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
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
                : const Text('-', style: TextStyle(color: Colors.grey))),
          ]);
        }).toList(),
      ),
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

    final publishedCount = _scores.values.where((s) => s.isPublished).length;
    final totalScores = _scores.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                          icon: const Icon(Icons.calculate, size: 18),
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
                          onPressed: _scores.isNotEmpty ? _publishAllScores : null,
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._navigatorDataMap.entries.map((entry) =>
              _buildNavigatorScoreCard(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildNavigatorScoreCard(String navigatorId, _NavigatorData data) {
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
          title: Row(
            children: [
              Text(name),
              if (data.isDisqualified) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('נפסל — פריצת אבטחה',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          subtitle: Text('נ.צ.: ${data.checkpointsHit}/${data.totalCheckpoints}  |  '
              'מרחק: ${data.actualDistanceKm.toStringAsFixed(1)} ק"מ',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.remove_circle_outline, color: Colors.grey),
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
                      color: score.isManual ? Colors.orange : scoreColor,
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
                  child: Icon(Icons.edit, size: 16,
                      color: score.isManual ? Colors.orange : Colors.grey[400]),
                ),
              ],
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (data.isDisqualified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('נפסל',
                      style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              if (score.isManual)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text('ידני',
                      style: TextStyle(fontSize: 10, color: Colors.orange)),
                ),
              if (score.isPublished)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Text('הופץ',
                      style: TextStyle(fontSize: 10, color: Colors.green)),
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
              if (score.isManual && _autoScores.containsKey(navigatorId))
                Text(
                  'ציון אוטומטי: ${_autoScores[navigatorId]}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
            ],
          ),
          children: [
            // Checkpoint details
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
            // Undo disqualification button
            if (data.isDisqualified)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _undoDisqualification(navigatorId),
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('בטל פסילה — חשב ציון רגיל', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                    ),
                  ),
                ),
              ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editScore(navigatorId),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('ערוך', style: TextStyle(fontSize: 12)),
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
                        score.isPublished ? Icons.check : Icons.send,
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
  // Settings Tab
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('אישור אוטומטי'),
                  subtitle: const Text('חישוב ציונים לפי הגדרות הניווט'),
                  value: _autoApprovalEnabled,
                  onChanged: (value) {
                    setState(() => _autoApprovalEnabled = value ?? true);
                  },
                ),
                if (_autoApprovalEnabled) ...[
                  const Divider(),
                  Text(
                    'שיטה: ${widget.navigation.verificationSettings.verificationType ?? "אישור/נכשל"}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (widget.navigation.verificationSettings.verificationType == 'approved_failed')
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      backgroundColor: data.color.withOpacity(0.2),
                      child: Icon(Icons.person, color: data.color, size: 20),
                    ),
                    title: Text(_getNavigatorDisplayName(navId)),
                    subtitle: Text(
                      '${data.checkpointsHit}/${data.totalCheckpoints} נ.צ.  |  '
                      '${data.trackPoints.isNotEmpty ? "יש מסלול" : "אין מסלול"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: score != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: ScoringService.getScoreColor(score.totalScore)
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${score.totalScore}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: ScoringService.getScoreColor(score.totalScore),
                              ),
                            ),
                          )
                        : const Text('-', style: TextStyle(color: Colors.grey)),
                  );
                }),
              ],
            ),
          ),
        ),
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
  final bool isDisqualified;

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
    this.isDisqualified = false,
  });
}
