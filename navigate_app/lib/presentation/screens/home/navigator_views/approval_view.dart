import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/nav_layer.dart' as nav;
import '../../../../domain/entities/checkpoint_punch.dart';
import '../../../../domain/entities/coordinate.dart';
import '../../../../domain/entities/user.dart';
import '../../../../data/repositories/nav_layer_repository.dart';
import '../../../../data/repositories/navigation_track_repository.dart';
import '../../../../data/repositories/checkpoint_punch_repository.dart';
import '../../../../services/gps_tracking_service.dart';
import '../../../../services/route_export_service.dart';
import '../../../../services/route_analysis_service.dart';
import '../../../widgets/map_with_selector.dart';
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

/// תצוגת אישרור למנווט — מפה עם מסלולים מתוכננים ובפועל
class ApprovalView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;

  const ApprovalView({
    super.key,
    required this.navigation,
    required this.currentUser,
  });

  @override
  State<ApprovalView> createState() => _ApprovalViewState();
}

class _ApprovalViewState extends State<ApprovalView> {
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationTrackRepository _trackRepo = NavigationTrackRepository();
  final CheckpointPunchRepository _punchRepo = CheckpointPunchRepository();
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

  // ניתוח
  List<SpeedSegment> _speedProfile = [];
  List<DeviationSegment> _deviations = [];
  bool _showDeviations = true;
  bool _showPlayback = false;

  bool _showPlanned = true;
  bool _showActual = true;
  bool _showCheckpoints = true;

  @override
  void initState() {
    super.initState();
    _loadData();
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

      // סינון נקודות לציר הזה
      if (route != null && route.checkpointIds.isNotEmpty) {
        final routeCps = <nav.NavCheckpoint>[];
        for (final cpId in route.checkpointIds) {
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

      // ניתוח מסלול
      _computeAnalysis();

      _centerMap();
    } catch (e) {
      print('DEBUG ApprovalView: Error loading data: $e');
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
          child: MapWithTypeSelector(
            showTypeSelector: false,
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14.0,
            ),
            layers: [
              // גבול גזרה
              if (_boundaries.isNotEmpty)
                PolygonLayer(
                  polygons: _boundaries
                      .where((b) => b.coordinates.isNotEmpty)
                      .map((b) => Polygon(
                            points: b.coordinates
                                .map((c) => LatLng(c.lat, c.lng))
                                .toList(),
                            color: _kBoundaryColor.withOpacity(0.1),
                            borderColor: _kBoundaryColor,
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
                      color: _kPlannedRouteColor,
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
                      color: _kActualRouteColor,
                      strokeWidth: 3.0,
                    ),
                  ],
                ),

              // שכבת סטיות
              if (_showDeviations && _deviations.isNotEmpty)
                for (final dev in _deviations)
                  if ((dev.endIndex + 1).clamp(0, _trackPoints.length) -
                          dev.startIndex.clamp(0, _trackPoints.length - 1) > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _trackPoints
                              .sublist(
                                dev.startIndex.clamp(0, _trackPoints.length - 1),
                                (dev.endIndex + 1).clamp(0, _trackPoints.length),
                              )
                              .map((tp) => LatLng(tp.coordinate.lat, tp.coordinate.lng))
                              .toList(),
                          color: _analysisService
                              .getDeviationColor(dev.maxDeviation)
                              .withValues(alpha: 0.8),
                          strokeWidth: 6.0,
                        ),
                      ],
                    ),

              // נ"ב
              if (_safetyPoints.isNotEmpty)
                MarkerLayer(
                  markers: _safetyPoints
                      .where((p) => p.coordinates != null)
                      .map((p) => Marker(
                            point: LatLng(
                                p.coordinates!.lat, p.coordinates!.lng),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.warning_amber,
                                color: _kSafetyColor, size: 28),
                          ))
                      .toList(),
                ),

              // נקודות ציון
              if (_showCheckpoints && pointCps.isNotEmpty)
                Builder(builder: (_) {
                  // זיהוי סוג לפי הציר — fallback ל-cp.type
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
                        point:
                            LatLng(cp.coordinates!.lat, cp.coordinates!.lng),
                        width: 38,
                        height: 38,
                        child: Container(
                          decoration: BoxDecoration(
                            color: bgColor,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2),
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
                      );
                    }).toList(),
                  );
                }),

              // דקירות
              if (_punches.isNotEmpty)
                MarkerLayer(
                  markers: _punches.where((p) => !p.isDeleted).map((p) {
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
                              p.id,
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
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
      ],
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
}
