import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/nav_layer.dart' as nav;
import '../../../../domain/entities/checkpoint_punch.dart';
import '../../../../domain/entities/navigation_score.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../domain/entities/user.dart';
import '../../../../data/repositories/nav_layer_repository.dart';
import '../../../../data/repositories/navigation_track_repository.dart';
import '../../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../../data/repositories/navigation_repository.dart';
import '../../../../services/gps_tracking_service.dart';
import '../../../../services/scoring_service.dart';
import '../../../../services/route_export_service.dart';
import '../../../../services/route_analysis_service.dart';
import '../../../widgets/map_with_selector.dart';
import '../../../widgets/map_controls.dart';
import '../../../widgets/fullscreen_map_screen.dart';
import '../../../widgets/speed_profile_chart.dart';
import '../../../widgets/route_playback_widget.dart';

/// צבעי מסלול
const _kPlannedRouteColor = Color(0xFFF44336); // אדום — מתוכנן
const _kActualRouteColor = Color(0xFF2196F3); // כחול — בפועל
const _kStartColor = Color(0xFF4CAF50); // ירוק — H (התחלה)
const _kEndColor = Color(0xFFF44336); // אדום — S (סיום)
const _kCheckpointColor = Color(0xFFFFC107); // צהוב — B (ביניים)
const _kBoundaryColor = Colors.black;
const _kSafetyColor = Color(0xFFFF9800); // כתום

/// תצוגת תחקיר למנווט — מפה + ציונים
class ReviewView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final NavigationScore? initialScore;

  const ReviewView({
    super.key,
    required this.navigation,
    required this.currentUser,
    this.initialScore,
  });

  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationTrackRepository _trackRepo = NavigationTrackRepository();
  final CheckpointPunchRepository _punchRepo = CheckpointPunchRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final ScoringService _scoringService = ScoringService();
  final RouteExportService _exportService = RouteExportService();
  final RouteAnalysisService _analysisService = RouteAnalysisService();
  final MapController _mapController = MapController();

  bool _isLoading = true;

  List<nav.NavCheckpoint> _checkpoints = [];
  List<nav.NavSafetyPoint> _safetyPoints = [];
  List<nav.NavBoundary> _boundaries = [];
  List<LatLng> _plannedRoute = [];
  List<LatLng> _actualRoute = [];
  List<TrackPoint> _trackPoints = [];
  List<CheckpointPunch> _punches = [];
  NavigationScore? _score;

  // שכבות מפה
  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = true;
  bool _showPlanned = true;
  bool _showActual = true;
  bool _showPunches = true;

  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _plannedOpacity = 1.0;
  double _actualOpacity = 1.0;
  double _punchesOpacity = 1.0;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // ניתוח
  List<SpeedSegment> _speedProfile = [];
  List<DeviationSegment> _deviations = [];
  bool _showDeviations = true;
  bool _showPlayback = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ReviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialScore != null &&
        widget.initialScore != oldWidget.initialScore) {
      setState(() => _score = widget.initialScore);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final navId = widget.navigation.id;
      final userId = widget.currentUser.uid;
      final route = widget.navigation.routes[userId];

      // שכבות ניווט
      _checkpoints =
          await _navLayerRepo.getCheckpointsByNavigation(navId);
      _safetyPoints =
          await _navLayerRepo.getSafetyPointsByNavigation(navId);
      _boundaries =
          await _navLayerRepo.getBoundariesByNavigation(navId);

      // Firestore fallback — שכבות נוצרות במכשיר המפקד, מכשירים אחרים צריכים לסנכרן
      if (_checkpoints.isEmpty && _safetyPoints.isEmpty && _boundaries.isEmpty) {
        try {
          await _navLayerRepo.syncAllLayersFromFirestore(navId);
          _checkpoints =
              await _navLayerRepo.getCheckpointsByNavigation(navId);
          _safetyPoints =
              await _navLayerRepo.getSafetyPointsByNavigation(navId);
          _boundaries =
              await _navLayerRepo.getBoundariesByNavigation(navId);
        } catch (_) {}
      }

      // סינון נקודות לציר הזה — כולל התחלה/סיום/ביניים
      if (route != null && route.checkpointIds.isNotEmpty) {
        final routeRelatedIds = <String>{
          ...route.checkpointIds,
          if (route.startPointId != null) route.startPointId!,
          if (route.endPointId != null) route.endPointId!,
          ...route.waypointIds,
        };
        final routeCps = <nav.NavCheckpoint>[];
        for (final cpId in routeRelatedIds) {
          final matches = _checkpoints
              .where((c) => c.id == cpId || c.sourceId == cpId)
              .toList();
          if (matches.isNotEmpty && !routeCps.contains(matches.first)) {
            routeCps.add(matches.first);
          }
        }
        if (routeCps.isNotEmpty) _checkpoints = routeCps;
      }

      // ציר מתוכנן
      if (route != null && route.plannedPath.isNotEmpty) {
        _plannedRoute =
            route.plannedPath.map((c) => LatLng(c.lat, c.lng)).toList();
      } else {
        _plannedRoute = _checkpoints
            .where((c) => !c.isPolygon && c.coordinates != null)
            .map((c) => LatLng(c.coordinates!.lat, c.coordinates!.lng))
            .toList();
      }

      // מסלול בפועל — נסיון מקומי, fallback ל-Firestore
      String? trackJson;
      final track =
          await _trackRepo.getByNavigatorAndNavigation(userId, navId);
      if (track != null && track.trackPointsJson.isNotEmpty) {
        trackJson = track.trackPointsJson;
      } else {
        try {
          final firestoreTracks =
              await _trackRepo.getByNavigationFromFirestore(navId);
          final myTrack = firestoreTracks
              .where((t) => t.navigatorUserId == userId)
              .toList();
          if (myTrack.isNotEmpty &&
              myTrack.first.trackPointsJson.isNotEmpty) {
            trackJson = myTrack.first.trackPointsJson;
          }
        } catch (_) {}
      }
      if (trackJson != null) {
        try {
          _trackPoints = (jsonDecode(trackJson) as List)
              .map((m) => TrackPoint.fromMap(m as Map<String, dynamic>))
              .toList();
          _actualRoute = _trackPoints
              .map((p) => LatLng(p.coordinate.lat, p.coordinate.lng))
              .toList();
        } catch (_) {}
      }

      // דקירות
      _punches = await _punchRepo.getByNavigator(userId);
      _punches =
          _punches.where((p) => p.navigationId == navId).toList();

      // ציונים
      try {
        final scores =
            await _navRepo.fetchScoresFromFirestore(navId);
        final myScoreMap =
            scores.where((s) => s['navigatorId'] == userId).toList();
        if (myScoreMap.isNotEmpty) {
          _score = NavigationScore.fromMap(myScoreMap.first);
        } else if (widget.initialScore != null) {
          _score = widget.initialScore;
        }
      } catch (_) {
        if (widget.initialScore != null) {
          _score = widget.initialScore;
        }
      }

      // ניתוח מסלול
      _computeAnalysis();

      _centerMap();
    } catch (e) {
      print('DEBUG ReviewView: Error loading data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _computeAnalysis() {
    if (_trackPoints.length < 2) return;
    final route = widget.navigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final stats = _analysisService.calculateStatistics(
      trackPoints: _trackPoints,
      checkpoints: _checkpoints,
      punches: _punches,
      route: route,
      plannedRoute: _plannedRoute.length >= 2 ? _plannedRoute : null,
    );
    _speedProfile = stats.speedProfile;

    if (_plannedRoute.length >= 2) {
      _deviations = _analysisService.analyzeDeviations(
        plannedRoute: _plannedRoute,
        actualTrack: _trackPoints,
      );
    }
  }

  void _centerMap() {
    if (_boundaries.isNotEmpty) {
      final boundary = _boundaries.first;
      if (boundary.coordinates.isNotEmpty) {
        final center = GeometryUtils.getPolygonCenter(boundary.coordinates);
        _mapController.move(LatLng(center.lat, center.lng), 13.0);
        return;
      }
    }
    final pointCps = _checkpoints
        .where((c) => !c.isPolygon && c.coordinates != null)
        .toList();
    if (pointCps.isNotEmpty) {
      final lat = pointCps
              .map((c) => c.coordinates!.lat)
              .reduce((a, b) => a + b) /
          pointCps.length;
      final lng = pointCps
              .map((c) => c.coordinates!.lng)
              .reduce((a, b) => a + b) /
          pointCps.length;
      _mapController.move(LatLng(lat, lng), 14.0);
    }
  }

  void _onExport() {
    final route = widget.navigation.routes[widget.currentUser.uid];
    _exportService.showExportDialog(context,
        data: ExportData(
          navigationName: widget.navigation.name,
          navigatorName: widget.currentUser.fullName,
          trackPoints: _trackPoints,
          checkpoints: _checkpoints,
          punches: _punches,
          plannedPath: route?.plannedPath,
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final showScores = widget.navigation.reviewSettings.showScoresAfterApproval;
    final route = widget.navigation.routes[widget.currentUser.uid];
    final actualCoords = _actualRoute
        .map((ll) => Coordinate(lat: ll.latitude, lng: ll.longitude, utm: ''))
        .toList();
    final actualDistKm = GeometryUtils.calculatePathLengthKm(actualCoords);
    final plannedDistKm = route?.routeLengthKm ?? 0.0;

    final pointCps = _checkpoints
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

    return Column(
      children: [
        // כרטיס ציון
        if (showScores && _score != null) _buildScoreHeader(),
        if (showScores && _score == null)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[50],
            child: const Row(
              children: [
                Icon(Icons.pending, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text('ציון טרם חושב',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        if (!showScores)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[50],
            child: const Row(
              children: [
                Icon(Icons.visibility_off, color: Colors.grey, size: 20),
                SizedBox(width: 8),
                Text('ציונים אינם מוצגים',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),

        // סרגל סטטיסטיקות + ייצוא
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.grey[50],
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statChip(Icons.route,
                        '${plannedDistKm.toStringAsFixed(1)} ק"מ', 'מתוכנן'),
                    _statChip(Icons.timeline,
                        '${actualDistKm.toStringAsFixed(1)} ק"מ', 'בפועל'),
                    _statChip(Icons.flag,
                        '${_punches.where((p) => !p.isDeleted).length}/${_checkpoints.length}',
                        'נ.צ.'),
                  ],
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.file_download, size: 18),
                label: const Text('ייצוא', style: TextStyle(fontSize: 12)),
                onPressed: _onExport,
                backgroundColor: Colors.blue[50],
              ),
            ],
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
                    }
                  },
                ),
                layers: [
                  // גבול גזרה
                  if (_showGG && _boundaries.isNotEmpty)
                    PolygonLayer(
                      polygons: _boundaries
                          .where((b) => b.coordinates.isNotEmpty)
                          .map((b) => Polygon(
                                points: b.coordinates
                                    .map((c) => LatLng(c.lat, c.lng))
                                    .toList(),
                                color: _kBoundaryColor
                                    .withValues(alpha: 0.1 * _ggOpacity),
                                borderColor: _kBoundaryColor
                                    .withValues(alpha: _ggOpacity),
                                borderStrokeWidth: 2.0,
                                isFilled: true,
                              ))
                          .toList(),
                    ),

                  // ציר מתוכנן (אדום)
                  if (_showPlanned && _plannedRoute.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _plannedRoute,
                          color: _kPlannedRouteColor
                              .withValues(alpha: _plannedOpacity),
                          strokeWidth: 4.0,
                        ),
                      ],
                    ),

                  // מסלול בפועל (כחול)
                  if (_showActual && _actualRoute.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _actualRoute,
                          color: _kActualRouteColor
                              .withValues(alpha: _actualOpacity),
                          strokeWidth: 3.0,
                        ),
                      ],
                    ),

                  // שכבת סטיות
                  if (_showActual && _showDeviations && _deviations.isNotEmpty)
                    for (final dev in _deviations)
                      if ((dev.endIndex + 1).clamp(0, _trackPoints.length) -
                              dev.startIndex
                                  .clamp(0, _trackPoints.length - 1) >
                          1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _trackPoints
                                  .sublist(
                                    dev.startIndex
                                        .clamp(0, _trackPoints.length - 1),
                                    (dev.endIndex + 1)
                                        .clamp(0, _trackPoints.length),
                                  )
                                  .map((tp) => LatLng(
                                      tp.coordinate.lat, tp.coordinate.lng))
                                  .toList(),
                              color: _analysisService
                                  .getDeviationColor(dev.maxDeviation)
                                  .withValues(alpha: 0.8 * _actualOpacity),
                              strokeWidth: 6.0,
                            ),
                          ],
                        ),

                  // נ"ב
                  if (_showNB && _safetyPoints.isNotEmpty)
                    MarkerLayer(
                      markers: _safetyPoints
                          .where((p) => p.coordinates != null)
                          .map((p) => Marker(
                                point: LatLng(
                                    p.coordinates!.lat, p.coordinates!.lng),
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

                  // נקודות ציון
                  if (_showNZ && pointCps.isNotEmpty)
                    Builder(builder: (_) {
                      final route = widget.navigation.routes[widget.currentUser.uid];
                      final startId = route?.startPointId;
                      final endId = route?.endPointId;

                      return MarkerLayer(
                        markers: pointCps.map((cp) {
                          Color bgColor;
                          String letter;

                          final isStart = (startId != null &&
                                  (cp.id == startId || cp.sourceId == startId)) ||
                              cp.type == 'start';
                          final isEnd = (endId != null &&
                                  (cp.id == endId || cp.sourceId == endId)) ||
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
                            point: LatLng(
                                cp.coordinates!.lat, cp.coordinates!.lng),
                            width: 38,
                            height: 38,
                            child: Opacity(
                              opacity: _nzOpacity,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
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
                      );
                    }),

                  // דקירות
                  if (_showPunches && _punches.isNotEmpty)
                    MarkerLayer(
                      markers:
                          _punches.where((p) => !p.isDeleted).map((p) {
                        Color color;
                        IconData icon;
                        if (p.isApproved) {
                          color = Colors.green;
                          icon = Icons.check_circle;
                        } else if (p.isRejected) {
                          color = Colors.red;
                          icon = Icons.cancel;
                        } else {
                          color = Colors.orange;
                          icon = Icons.flag;
                        }
                        return Marker(
                          point: LatLng(
                              p.punchLocation.lat, p.punchLocation.lng),
                          width: 80,
                          height: 45,
                          child: Opacity(
                            opacity: _punchesOpacity,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, color: color, size: 22),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 2, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    p.id,
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  // שכבות מדידה
                  ...MapControls.buildMeasureLayers(_measurePoints),
                ],
              ),
              _buildMapControls(center),
            ],
          ),
        ),

        // נגן מסלול
        if (_showPlayback && _trackPoints.length >= 2)
          Padding(
            padding: const EdgeInsets.all(8),
            child: RoutePlaybackWidget(
              trackPoints: _trackPoints,
              onPositionChanged: (pos) {
                _mapController.move(pos, _mapController.camera.zoom);
              },
            ),
          ),

        // פקדים + גרף מהירות + מקרא
        Container(
          color: Colors.grey[100],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // כפתורי toggle
              if (_trackPoints.length >= 2 || _deviations.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_trackPoints.length >= 2)
                      TextButton.icon(
                        onPressed: () => setState(() => _showPlayback = !_showPlayback),
                        icon: Icon(
                          _showPlayback ? Icons.stop : Icons.play_arrow,
                          size: 16,
                        ),
                        label: Text(_showPlayback ? 'סגור נגן' : 'נגן מסלול',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    if (_deviations.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => _showDeviations = !_showDeviations),
                        icon: Icon(
                          _showDeviations ? Icons.visibility : Icons.visibility_off,
                          size: 16, color: Colors.red,
                        ),
                        label: Text(_showDeviations ? 'הסתר סטיות' : 'הצג סטיות',
                            style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),

              // גרף מהירות
              if (_speedProfile.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: SpeedProfileChart(
                    segments: _speedProfile,
                    thresholdSpeedKmh: 8.0,
                  ),
                ),

              // מקרא
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        ),

        // פירוט ציונים (תחת המפה)
        if (showScores && _score != null) _buildScoreDetails(),
      ],
    );
  }

  Widget _buildMapControls(LatLng center) {
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
      onFullscreen: () => _openFullscreenMap(center),
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
          label: 'נת"בים',
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
          onVisibilityChanged: (v) => setState(() => _showPlanned = v),
          opacity: _plannedOpacity,
          onOpacityChanged: (v) => setState(() => _plannedOpacity = v),
        ),
        MapLayerConfig(
          id: 'actual',
          label: 'מסלול בפועל',
          color: _kActualRouteColor,
          visible: _showActual,
          onVisibilityChanged: (v) => setState(() => _showActual = v),
          opacity: _actualOpacity,
          onOpacityChanged: (v) => setState(() => _actualOpacity = v),
        ),
        MapLayerConfig(
          id: 'punches',
          label: 'דקירות',
          color: Colors.green,
          visible: _showPunches,
          onVisibilityChanged: (v) => setState(() => _showPunches = v),
          opacity: _punchesOpacity,
          onOpacityChanged: (v) => setState(() => _punchesOpacity = v),
        ),
      ],
    );
  }

  Widget _buildScoreHeader() {
    final score = _score!;
    final scoreColor = ScoringService.getScoreColor(score.totalScore);
    final grade = _scoringService.getGrade(score.totalScore);

    return Container(
      padding: const EdgeInsets.all(12),
      color: scoreColor.withOpacity(0.1),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scoreColor,
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${score.totalScore}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                Text(grade,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('הציון שלך',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  score.totalScore >= 80
                      ? 'כל הכבוד! ביצוע מעולה'
                      : score.totalScore >= 60
                          ? 'ביצוע טוב'
                          : 'נדרש שיפור',
                  style: TextStyle(color: scoreColor, fontSize: 13),
                ),
                if (score.notes != null && score.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(score.notes!,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreDetails() {
    final score = _score!;
    if (score.checkpointScores.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('פירוט לפי נקודה:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...score.checkpointScores.entries.map((cpEntry) {
              final cpScore = cpEntry.value;
              final matchCp = _checkpoints.where(
                (c) =>
                    c.sourceId == cpScore.checkpointId ||
                    c.id == cpScore.checkpointId,
              );
              final cpName =
                  matchCp.isNotEmpty ? matchCp.first.name : cpScore.checkpointId;
              final cpScoreColor =
                  ScoringService.getScoreColor(cpScore.score);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      cpScore.approved
                          ? Icons.check_circle
                          : Icons.cancel,
                      color:
                          cpScore.approved ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(cpName,
                            style: const TextStyle(fontSize: 12))),
                    Text(
                        '${cpScore.distanceMeters.toStringAsFixed(0)}מ\'',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: cpScoreColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
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
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 2),
        Text(value,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  void _openFullscreenMap(LatLng center) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          final route = widget.navigation.routes[widget.currentUser.uid];
          return _FullscreenReviewMap(
            center: center,
            checkpoints: _checkpoints,
            safetyPoints: _safetyPoints,
            boundaries: _boundaries,
            plannedRoute: _plannedRoute,
            actualRoute: _actualRoute,
            trackPoints: _trackPoints,
            punches: _punches,
            deviations: _deviations,
            startPointId: route?.startPointId,
            endPointId: route?.endPointId,
          );
        },
      ),
    );
  }
}

/// מסך מפה מלא לתחקיר מנווט
class _FullscreenReviewMap extends StatefulWidget {
  final LatLng center;
  final List<nav.NavCheckpoint> checkpoints;
  final List<nav.NavSafetyPoint> safetyPoints;
  final List<nav.NavBoundary> boundaries;
  final List<LatLng> plannedRoute;
  final List<LatLng> actualRoute;
  final List<TrackPoint> trackPoints;
  final List<CheckpointPunch> punches;
  final List<DeviationSegment> deviations;
  final String? startPointId;
  final String? endPointId;

  const _FullscreenReviewMap({
    required this.center,
    required this.checkpoints,
    required this.safetyPoints,
    required this.boundaries,
    required this.plannedRoute,
    required this.actualRoute,
    required this.trackPoints,
    required this.punches,
    required this.deviations,
    this.startPointId,
    this.endPointId,
  });

  @override
  State<_FullscreenReviewMap> createState() => _FullscreenReviewMapState();
}

class _FullscreenReviewMapState extends State<_FullscreenReviewMap> {
  final MapController _mapController = MapController();
  final RouteAnalysisService _analysisService = RouteAnalysisService();
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = true;
  bool _showPlanned = true;
  bool _showActual = true;
  bool _showPunches = true;
  bool _showDeviations = true;

  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _plannedOpacity = 1.0;
  double _actualOpacity = 1.0;
  double _punchesOpacity = 1.0;

  @override
  Widget build(BuildContext context) {
    final pointCps = widget.checkpoints
        .where((c) => !c.isPolygon && c.coordinates != null)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('מפת תחקיר'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            showTypeSelector: false,
            options: MapOptions(
              initialCenter: widget.center,
              initialZoom: 14.0,
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                }
              },
            ),
            layers: [
              // גבול גזרה
              if (_showGG && widget.boundaries.isNotEmpty)
                PolygonLayer(
                  polygons: widget.boundaries
                      .where((b) => b.coordinates.isNotEmpty)
                      .map((b) => Polygon(
                            points: b.coordinates
                                .map((c) => LatLng(c.lat, c.lng))
                                .toList(),
                            color: _kBoundaryColor
                                .withValues(alpha: 0.1 * _ggOpacity),
                            borderColor: _kBoundaryColor
                                .withValues(alpha: _ggOpacity),
                            borderStrokeWidth: 2.0,
                            isFilled: true,
                          ))
                      .toList(),
                ),

              // ציר מתוכנן
              if (_showPlanned && widget.plannedRoute.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.plannedRoute,
                      color: _kPlannedRouteColor
                          .withValues(alpha: _plannedOpacity),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),

              // מסלול בפועל
              if (_showActual && widget.actualRoute.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.actualRoute,
                      color: _kActualRouteColor
                          .withValues(alpha: _actualOpacity),
                      strokeWidth: 3.0,
                    ),
                  ],
                ),

              // שכבת סטיות
              if (_showActual &&
                  _showDeviations &&
                  widget.deviations.isNotEmpty)
                for (final dev in widget.deviations)
                  if ((dev.endIndex + 1)
                              .clamp(0, widget.trackPoints.length) -
                          dev.startIndex
                              .clamp(0, widget.trackPoints.length - 1) >
                      1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: widget.trackPoints
                              .sublist(
                                dev.startIndex
                                    .clamp(0, widget.trackPoints.length - 1),
                                (dev.endIndex + 1)
                                    .clamp(0, widget.trackPoints.length),
                              )
                              .map((tp) => LatLng(
                                  tp.coordinate.lat, tp.coordinate.lng))
                              .toList(),
                          color: _analysisService
                              .getDeviationColor(dev.maxDeviation)
                              .withValues(alpha: 0.8 * _actualOpacity),
                          strokeWidth: 6.0,
                        ),
                      ],
                    ),

              // נת"בים
              if (_showNB && widget.safetyPoints.isNotEmpty)
                MarkerLayer(
                  markers: widget.safetyPoints
                      .where((p) => p.coordinates != null)
                      .map((p) => Marker(
                            point: LatLng(
                                p.coordinates!.lat, p.coordinates!.lng),
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

              // נקודות ציון
              if (_showNZ && pointCps.isNotEmpty)
                Builder(builder: (_) {
                  final startId = widget.startPointId;
                  final endId = widget.endPointId;

                  return MarkerLayer(
                    markers: pointCps.map((cp) {
                      Color bgColor;
                      String letter;

                      final isStart = (startId != null &&
                              (cp.id == startId || cp.sourceId == startId)) ||
                          cp.type == 'start';
                      final isEnd = (endId != null &&
                              (cp.id == endId || cp.sourceId == endId)) ||
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
                        point: LatLng(
                            cp.coordinates!.lat, cp.coordinates!.lng),
                        width: 38,
                        height: 38,
                        child: Opacity(
                          opacity: _nzOpacity,
                          child: Container(
                            decoration: BoxDecoration(
                              color: bgColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
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
                  );
                }),

              // דקירות
              if (_showPunches && widget.punches.isNotEmpty)
                MarkerLayer(
                  markers:
                      widget.punches.where((p) => !p.isDeleted).map((p) {
                    Color color;
                    IconData icon;
                    if (p.isApproved) {
                      color = Colors.green;
                      icon = Icons.check_circle;
                    } else if (p.isRejected) {
                      color = Colors.red;
                      icon = Icons.cancel;
                    } else {
                      color = Colors.orange;
                      icon = Icons.flag;
                    }
                    return Marker(
                      point: LatLng(
                          p.punchLocation.lat, p.punchLocation.lng),
                      width: 80,
                      height: 45,
                      child: Opacity(
                        opacity: _punchesOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, color: color, size: 22),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 2, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                p.id,
                                style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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
            onMeasureClear: () =>
                setState(() => _measurePoints.clear()),
            onMeasureUndo: () => setState(() {
              if (_measurePoints.isNotEmpty) _measurePoints.removeLast();
            }),
            layers: [
              MapLayerConfig(
                id: 'gg',
                label: 'גבול גזרה',
                color: _kBoundaryColor,
                visible: _showGG,
                onVisibilityChanged: (v) =>
                    setState(() => _showGG = v),
                opacity: _ggOpacity,
                onOpacityChanged: (v) =>
                    setState(() => _ggOpacity = v),
              ),
              MapLayerConfig(
                id: 'nz',
                label: 'נקודות ציון',
                color: Colors.blue,
                visible: _showNZ,
                onVisibilityChanged: (v) =>
                    setState(() => _showNZ = v),
                opacity: _nzOpacity,
                onOpacityChanged: (v) =>
                    setState(() => _nzOpacity = v),
              ),
              MapLayerConfig(
                id: 'nb',
                label: 'נת"בים',
                color: _kSafetyColor,
                visible: _showNB,
                onVisibilityChanged: (v) =>
                    setState(() => _showNB = v),
                opacity: _nbOpacity,
                onOpacityChanged: (v) =>
                    setState(() => _nbOpacity = v),
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
                id: 'actual',
                label: 'מסלול בפועל',
                color: _kActualRouteColor,
                visible: _showActual,
                onVisibilityChanged: (v) =>
                    setState(() => _showActual = v),
                opacity: _actualOpacity,
                onOpacityChanged: (v) =>
                    setState(() => _actualOpacity = v),
              ),
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
            ],
          ),
        ],
      ),
    );
  }
}
