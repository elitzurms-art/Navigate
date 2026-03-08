import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/file_export_helper.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/utils/geometry_utils.dart';
import '../../../../core/utils/narration_generator.dart';
import '../../../../domain/entities/narration_entry.dart';
import '../../../../domain/entities/navigation.dart' as domain;
import '../../../../domain/entities/checkpoint.dart';
import '../../../../domain/entities/user.dart';
import '../../../../data/repositories/area_repository.dart';
import '../../../../data/repositories/boundary_repository.dart';
import '../../../../data/repositories/checkpoint_repository.dart';
import '../../../../data/repositories/navigation_repository.dart';
import '../../../../data/repositories/safety_point_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../../data/repositories/unit_repository.dart';
import '../../../../domain/entities/safety_point.dart';
import '../../../../domain/entities/boundary.dart';
import '../../../widgets/map_with_selector.dart';
import '../../../widgets/map_controls.dart';
import '../../../../core/map_config.dart';
import '../../../../services/auto_map_download_service.dart';
import '../../../widgets/fullscreen_map_screen.dart';
import 'route_editor_screen.dart';

/// תצוגת למידה למנווט — לשוניות דינמיות לפי LearningSettings
class LearningView extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final ValueChanged<domain.Navigation> onNavigationUpdated;

  const LearningView({
    super.key,
    required this.navigation,
    required this.currentUser,
    required this.onNavigationUpdated,
  });

  @override
  State<LearningView> createState() => _LearningViewState();
}

class _LearningViewState extends State<LearningView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<_LearningTab> _tabs;
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationRepository _navigationRepo = NavigationRepository();
  final SafetyPointRepository _safetyPointRepo = SafetyPointRepository();
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final MapController _mapController = MapController();

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  List<SafetyPoint> _safetyPoints = [];
  List<Boundary> _boundaries = [];

  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = false;
  bool _showRoutes = true;

  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _routesOpacity = 1.0;

  /// ניווט נוכחי — mutable, מתעדכן אחרי כל שמירה
  late domain.Navigation _currentNavigation;

  /// נקודות ציון טעונות לפי sequence — לשימוש במפה
  List<Checkpoint> _routeCheckpoints = [];
  bool _checkpointsLoaded = false;
  Checkpoint? _startCheckpoint;
  Checkpoint? _endCheckpoint;

  // Cluster navigation state
  Map<String, List<Checkpoint>> _clusterMap = {};
  List<Checkpoint> _allAreaCheckpoints = [];
  bool _revealAvailable = false;

  bool get _isReverseNavigation => _currentNavigation.isReverse;

  /// סיפור דרך — state
  List<NarrationEntry> _narrationEntries = [];

  /// קבוצה (צמד/חוליה) — state
  String? _repName; // שם הנציג (לבאנר)

  /// שמות לתצוגה בפרטי ניווט
  String? _areaName;
  String? _boundaryName;
  String? _unitName;

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    _loadNarrationFromRoute();
    _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadCheckpoints();
    _loadDisplayNames();
    _loadMapLayers();
    _promptMapDownload();
  }

  /// הצגת דיאלוג הורדת מפות אופליין — פעם אחת בלבד
  void _promptMapDownload() {
    final service = AutoMapDownloadService();
    final navId = widget.navigation.id;

    // דילוג אם כבר הוצג, או שההורדה בכל סטטוס חוץ מ-notStarted/failed
    final status = service.getStatus(navId);
    if (service.hasBeenPrompted(navId)) return;
    if (status != MapDownloadStatus.notStarted &&
        status != MapDownloadStatus.failed) return;

    service.markPrompted(navId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('הורדת מפות אופליין'),
          content: const Text(
            'האם להוריד מפות אופליין עבור הניווט?\n'
            'ההורדה תתבצע ברקע ותופיע כהתראה.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('לא כעת'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('הורד'),
            ),
          ],
        ),
      ).then((approved) {
        if (approved == true) {
          service.markApproved(navId);
          service.onStatusMessage = (message, {bool isError = false}) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: isError ? Colors.red : Colors.blue,
                duration: Duration(seconds: isError ? 4 : 3),
              ),
            );
          };
          service.triggerDownload(widget.navigation);
        }
      });
    });
  }

  @override
  void didUpdateWidget(LearningView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentNavigation = widget.navigation;
    if (oldWidget.navigation.id != widget.navigation.id) {
      _rebuildTabs();
    } else if (oldWidget.navigation.forceComposition != widget.navigation.forceComposition) {
      // נציג השתנה דרך sync — בנייה מחדש
      _rebuildTabs();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _buildTabs() {
    final settings = _currentNavigation.learningSettings;
    final route = _currentNavigation.routes[widget.currentUser.uid];
    final groupId = route?.groupId;
    final composition = _currentNavigation.forceComposition;
    final isGrouped = composition.isGrouped && groupId != null;
    final learningRep = composition.getLearningRepresentative(groupId);
    final isRep = learningRep == widget.currentUser.uid;
    final hasOtherRep = learningRep != null && !isRep;

    _tabs = [];

    if (settings.showNavigationDetails) {
      _tabs.add(_LearningTab(
        label: 'פרטי ניווט',
        icon: Icons.info_outline,
        builder: _buildDetailsTab,
      ));
    }

    if (settings.showRoutes) {
      _tabs.add(_LearningTab(
        label: 'הציר שלי',
        icon: Icons.route,
        builder: _buildRouteTab,
      ));
    }

    // אם יש קבוצה ויש נציג אחר — הסתר עריכה/אישור/סיפור דרך
    if (isGrouped && hasOtherRep) {
      // לא מוסיפים edit/narration tabs — הנציג עורך עבור המשני
      _loadRepName(learningRep!);
    } else {
      if (settings.allowRouteEditing) {
        _tabs.add(_LearningTab(
          label: 'עריכה ואישור',
          icon: Icons.edit,
          builder: _buildEditTab,
        ));
      }

      if (settings.allowRouteNarration) {
        _tabs.add(_LearningTab(
          label: 'סיפור דרך',
          icon: Icons.record_voice_over,
          builder: _buildNarrationTab,
        ));
      }
    }

    // אם אין לשוניות בכלל, הוסף placeholder
    if (_tabs.isEmpty) {
      _tabs.add(_LearningTab(
        label: 'למידה',
        icon: Icons.school,
        builder: _buildEmptyTab,
      ));
    }
  }

  /// טעינת שם הנציג לבאנר
  void _loadRepName(String repId) {
    UserRepository().getUser(repId).then((user) {
      if (mounted && user != null) {
        setState(() => _repName = user.fullName.isNotEmpty ? user.fullName : repId);
      }
    });
  }

  /// תווית הרכב כוח
  String _getCompositionLabel() {
    final type = _currentNavigation.forceComposition.type;
    return type == 'pair' ? 'צמד' : (type == 'squad' ? 'חוליה' : 'קבוצה');
  }

  /// בדיקה + תביעת נציג למידה. מחזיר true אם המנווט הוא/הפך לנציג.
  Future<bool> _ensureLearningRepresentative() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null || route.groupId == null) return true; // solo
    final composition = _currentNavigation.forceComposition;
    if (!composition.isGrouped) return true;

    final existingRep = composition.getLearningRepresentative(route.groupId);
    if (existingRep == widget.currentUser.uid) return true; // כבר נציג
    if (existingRep != null) return false; // יש נציג אחר

    // אין נציג — שאל
    final label = _getCompositionLabel();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('נציג ה$label'),
        content: Text('האם אתה בטוח שאתה נציג ה$label?\n'
            'לאחר אישור, רק אתה תוכל לערוך את הציר.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('אישור')),
        ],
      ),
    );
    if (confirmed != true) return false;

    // עדכון ForceComposition
    final updatedReps = Map<String, String>.from(
      _currentNavigation.forceComposition.learningRepresentatives,
    );
    updatedReps[route.groupId!] = widget.currentUser.uid;
    final updatedNav = _currentNavigation.copyWith(
      forceComposition: _currentNavigation.forceComposition.copyWith(
        learningRepresentatives: updatedReps,
      ),
      updatedAt: DateTime.now(),
    );
    await _navigationRepo.update(updatedNav);
    setState(() => _currentNavigation = updatedNav);
    widget.onNavigationUpdated(updatedNav);
    _rebuildTabs();
    return true;
  }

  /// בנייה מחדש של tabs (אחרי שינוי נציג)
  void _rebuildTabs() {
    final oldLength = _tabs.length;
    _buildTabs();
    if (_tabs.length != oldLength) {
      _tabController.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this);
    }
    setState(() {});
  }

  /// טעינת נקודות ציון של הציר לפי סדר ה-sequence + התחלה/סיום
  Future<void> _loadCheckpoints() async {
    final route = widget.navigation.routes[widget.currentUser.uid];
    if (route == null || route.checkpointIds.isEmpty) {
      if (mounted) setState(() => _checkpointsLoaded = true);
      return;
    }

    try {
      final loaded = <Checkpoint>[];
      for (final cpId in route.sequence) {
        final cp = await _checkpointRepo.getById(cpId);
        if (cp != null) loaded.add(cp);
      }

      // טעינת נקודות התחלה/סיום
      Checkpoint? startCp;
      Checkpoint? endCp;
      if (route.startPointId != null) {
        startCp = await _checkpointRepo.getById(route.startPointId!);
      }
      if (route.endPointId != null) {
        endCp = await _checkpointRepo.getById(route.endPointId!);
      }

      // ניווט הפוך — היפוך סדר תצוגה (הנתונים השמורים נשארים כמות שהם)
      final displayList = _isReverseNavigation ? loaded.reversed.toList() : loaded;
      if (_isReverseNavigation) {
        final tempStart = startCp;
        startCp = endCp;
        endCp = tempStart;
      }

      if (mounted) {
        setState(() {
          _routeCheckpoints = displayList;
          _startCheckpoint = startCp;
          _endCheckpoint = endCp;
          _checkpointsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkpointsLoaded = true);
    }

    // Load all area checkpoints for cluster decoy selection
    if (_currentNavigation.isClusters) {
      final allCps = await _checkpointRepo.getByArea(_currentNavigation.areaId);
      if (mounted) {
        setState(() {
          _allAreaCheckpoints = allCps;
        });
        _buildClusters();
        setState(() {});
      }
    }
  }

  void _buildClusters() {
    if (_clusterMap.isNotEmpty) return; // cached
    if (_routeCheckpoints.isEmpty) return; // guard

    final settings = _currentNavigation.clusterSettings;
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final specialIds = <String>{};
    if (route.startPointId != null) specialIds.add(route.startPointId!);
    if (route.endPointId != null) specialIds.add(route.endPointId!);
    for (final wpId in route.waypointIds) {
      specialIds.add(wpId);
    }

    // Middle checkpoints only (skip start/end/waypoints/polygons)
    final middleCps = _routeCheckpoints.where(
      (cp) => !specialIds.contains(cp.id) && cp.coordinates != null && !cp.isPolygon,
    ).toList();
    if (middleCps.isEmpty) return;

    final usedDecoys = <String>{};
    final assignedCpIds = route.checkpointIds.toSet();

    for (final realCp in middleCps) {
      final neededDecoys = settings.clusterSize - 1;
      final candidates = _allAreaCheckpoints
          .where((cp) => cp.id != realCp.id
              && !specialIds.contains(cp.id)
              && !assignedCpIds.contains(cp.id)
              && !usedDecoys.contains(cp.id)
              && cp.coordinates != null && !cp.isPolygon
              && _distanceMeters(realCp, cp) <= settings.clusterSpreadMeters)
          .toList();

      candidates.sort((a, b) =>
          _distanceMeters(realCp, a).compareTo(_distanceMeters(realCp, b)));

      final actualDecoys = candidates.take(neededDecoys).toList();
      for (final d in actualDecoys) {
        usedDecoys.add(d.id);
      }

      final cluster = [realCp, ...actualDecoys];
      cluster.shuffle(Random(realCp.id.hashCode));
      _clusterMap[realCp.id] = cluster;
    }
  }

  double _distanceMeters(Checkpoint a, Checkpoint b) {
    if (a.coordinates == null || b.coordinates == null) return double.infinity;
    return GeometryUtils.distanceBetweenMeters(a.coordinates!, b.coordinates!);
  }

  /// טעינת שמות שטח, גבול גזרה ויחידה לתצוגה
  Future<void> _loadDisplayNames() async {
    final nav = widget.navigation;
    try {
      final area = await AreaRepository().getById(nav.areaId);
      if (area != null && mounted) setState(() => _areaName = area.name);
    } catch (_) {}

    try {
      if (nav.boundaryLayerId != null) {
        final boundary = await BoundaryRepository().getById(nav.boundaryLayerId!);
        if (boundary != null && mounted) setState(() => _boundaryName = boundary.name);
      }
    } catch (_) {}

    try {
      if (nav.selectedUnitId != null) {
        final unit = await UnitRepository().getById(nav.selectedUnitId!);
        if (unit != null && mounted) setState(() => _unitName = unit.name);
      }
    } catch (_) {}
  }

  /// טעינת שכבות מפה: ג"ג, נת"ב
  Future<void> _loadMapLayers() async {
    try {
      final safetyPoints = await _safetyPointRepo.getByArea(widget.navigation.areaId);
      final boundaries = await _boundaryRepo.getByArea(widget.navigation.areaId);
      if (mounted) {
        setState(() {
          _safetyPoints = safetyPoints;
          _boundaries = boundaries;
        });
      }
    } catch (_) {}
  }

  // ===========================================================================
  // Tab builders
  // ===========================================================================

  Widget _buildDetailsTab() {
    final nav = _currentNavigation;
    final route = nav.routes[widget.currentUser.uid];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard('שם ניווט', nav.name),
          if (_unitName != null)
            _infoCard('יחידה', _unitName!),
          _infoCard('שטח', _areaName ?? nav.areaId),
          if (nav.boundaryLayerId != null)
            _infoCard('גבול גזרה', _boundaryName ?? nav.boundaryLayerId!),
          if (nav.routeLengthKm != null)
            _infoCard(
              'מרחק ניווט',
              '${nav.routeLengthKm!.min.toStringAsFixed(1)} - ${nav.routeLengthKm!.max.toStringAsFixed(1)} ק"מ',
            ),
          if (route != null) ...[
            const SizedBox(height: 16),
            Text(
              'הציר שלי',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _infoCard('מספר נקודות', '${route.checkpointIds.length}'),
            _infoCard('אורך ציר', '${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),
            _infoCard('סטטוס', _approvalStatusLabel(route.approvalStatus)),
            if (route.approvalStatus == 'approved' &&
                nav.timeCalculationSettings.enabled &&
                nav.learningSettings.showMissionTimes) ...[
              const Divider(),
              Text(
                'הזמנים שלי',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final settings = nav.timeCalculationSettings;
                final totalMinutes = GeometryUtils.getEffectiveTimeMinutes(
                  route: route,
                  settings: settings,
                );
                final walkMinutes = ((route.routeLengthKm / settings.walkingSpeedKmh) * 60).ceil();
                final breakMinutes = settings.breakDurationMinutes(route.routeLengthKm);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoCard('קצב', '${settings.walkingSpeedKmh.toStringAsFixed(1)} קמ"ש'),
                    _infoCard('זמן הליכה', GeometryUtils.formatNavigationTime(walkMinutes)),
                    if (breakMinutes > 0)
                      _infoCard('הפסקות',
                          '${(route.routeLengthKm / 10).floor()} הפסקות ($breakMinutes דק\')')
                    else
                      _infoCard('הפסקות', 'ללא (ציר קצר מ-10 ק"מ)'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text('סה"כ זמן משימה',
                                style: TextStyle(color: Colors.grey[600])),
                          ),
                          Expanded(
                            child: Text(
                              GeometryUtils.formatNavigationTime(totalMinutes),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRouteTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // מפת ציר
          _buildRouteMap(),
          const SizedBox(height: 16),
          Text(
            'נקודות הציר',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _buildCheckpointList(),
          const SizedBox(height: 12),
          _infoCard('אורך ציר', '${route.routeLengthKm.toStringAsFixed(2)} ק"מ'),
        ],
      ),
    );
  }

  /// בניית מפה עם נקודות ציון ו-polyline
  Widget _buildRouteMap() {
    if (!_checkpointsLoaded) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_routeCheckpoints.isEmpty) {
      return SizedBox(
        height: 250,
        child: Card(
          color: Colors.grey[100],
          child: const Center(child: Text('אין נתוני מיקום לנקודות')),
        ),
      );
    }

    final route = _currentNavigation.routes[widget.currentUser.uid];

    // נקודות ציון של המנווט — רק נקודות (לא פוליגונים)
    final pointCheckpoints = _routeCheckpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).toList();
    final cpPoints = pointCheckpoints
        .map((cp) => cp.coordinates!.toLatLng())
        .toList();

    // בניית ציר רפרנס מלא: התחלה → נקודות ציון → סיום
    final fullRefPoints = <LatLng>[];
    if (_startCheckpoint != null && !_startCheckpoint!.isPolygon && _startCheckpoint!.coordinates != null) {
      fullRefPoints.add(_startCheckpoint!.coordinates!.toLatLng());
    }
    fullRefPoints.addAll(cpPoints);
    if (_endCheckpoint != null && !_endCheckpoint!.isPolygon && _endCheckpoint!.coordinates != null) {
      fullRefPoints.add(_endCheckpoint!.coordinates!.toLatLng());
    }
    final refPoints = fullRefPoints.isNotEmpty ? fullRefPoints : cpPoints;

    // אם המנווט צייר ציר — מציגים אותו; אחרת ציר רפרנס
    final hasPlannedPath = route != null && route.plannedPath.isNotEmpty;
    final plannedPathPoints = hasPlannedPath
        ? route.plannedPath.map((c) => c.toLatLng()).toList()
        : <LatLng>[];

    final allPointsForBounds = [...refPoints, ...plannedPathPoints];
    // עדיפות לגבול גזרה אם קיים, אחרת נקודות ציון/ציר
    final boundaryPoints = _boundaries.isNotEmpty && _boundaries.first.coordinates.isNotEmpty
        ? _boundaries.first.coordinates.map((c) => LatLng(c.lat, c.lng)).toList()
        : <LatLng>[];
    final boundsPoints = boundaryPoints.isNotEmpty
        ? boundaryPoints
        : (allPointsForBounds.length > 1 ? allPointsForBounds : cpPoints);
    final bounds = LatLngBounds.fromPoints(boundsPoints);

    final markers = <Marker>[];
    // marker לנקודת התחלה
    if (_startCheckpoint != null && !_startCheckpoint!.isPolygon && _startCheckpoint!.coordinates != null) {
      markers.add(Marker(
        point: _startCheckpoint!.coordinates!.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: 'התחלה: ${_startCheckpoint!.name}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Text('H', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ));
    }
    if (_currentNavigation.isClusters && _clusterMap.isNotEmpty) {
      // מצב אשכולות — כל הנקודות עם sequenceNumber מהדומיין
      final seen = <String>{};
      const jitter = 0.0002; // ~10m
      for (final cluster in _clusterMap.values) {
        for (final cp in cluster) {
          if (cp.isPolygon || cp.coordinates == null) continue;
          if (cp.id == _startCheckpoint?.id || cp.id == _endCheckpoint?.id) continue;
          if (!seen.add(cp.id)) continue;

          final rng = Random(cp.id.hashCode);
          final jitterLat = (rng.nextDouble() - 0.5) * 2 * jitter;
          final jitterLng = (rng.nextDouble() - 0.5) * 2 * jitter;
          final point = LatLng(
            cp.coordinates!.lat + jitterLat,
            cp.coordinates!.lng + jitterLng,
          );

          markers.add(Marker(
            point: point,
            width: 32,
            height: 32,
            child: Tooltip(
              message: cp.name,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
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
          ));
        }
      }
    } else {
      // מצב רגיל — נקודות עם מספור
      for (var i = 0; i < _routeCheckpoints.length; i++) {
        final cp = _routeCheckpoints[i];
        if (cp.isPolygon || cp.coordinates == null) continue;
        if (cp.id == _startCheckpoint?.id || cp.id == _endCheckpoint?.id) continue;

        markers.add(Marker(
          point: cp.coordinates!.toLatLng(),
          width: 32,
          height: 32,
          child: Tooltip(
            message: cp.name,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ));
      }
    }
    // marker לנקודת סיום
    if (_endCheckpoint != null && !_endCheckpoint!.isPolygon && _endCheckpoint!.coordinates != null) {
      markers.add(Marker(
        point: _endCheckpoint!.coordinates!.toLatLng(),
        width: 32,
        height: 32,
        child: Tooltip(
          message: 'סיום: ${_endCheckpoint!.name}',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
              child: Text('S', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 250,
        child: Stack(
          children: [
            MapWithTypeSelector(
              mapController: _mapController,
              showTypeSelector: false,
              initialMapType: MapConfig.resolveMapType(widget.navigation.displaySettings.defaultMap),
              // Fullscreen button is added at the end of the Stack
              options: MapOptions(
                initialCenter: bounds.center,
                initialZoom: 14.0,
                initialCameraFit: boundsPoints.length > 1
                    ? CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(40),
                      )
                    : null,
                onTap: (tapPosition, point) {
                  if (_measureMode) {
                    setState(() => _measurePoints.add(point));
                    return;
                  }
                },
              ),
              layers: [
                // ג"ג
                if (_showGG && _boundaries.isNotEmpty)
                  PolygonLayer(
                    polygons: _boundaries.map((b) => Polygon(
                      points: b.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                      color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                      borderColor: Colors.black.withValues(alpha: _ggOpacity),
                      borderStrokeWidth: b.strokeWidth,
                      isFilled: true,
                    )).toList(),
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
                // ציר רפרנס (כחול בהיר) — מוסתר במצב אשכולות
                if (_showRoutes && refPoints.length > 1 && !(_currentNavigation.isClusters && _clusterMap.isNotEmpty))
                  PolylineLayer(polylines: [
                    Polyline(
                      points: refPoints,
                      color: Colors.blue.withValues(alpha: 0.3 * _routesOpacity),
                      strokeWidth: 2.0,
                    ),
                  ]),
                // ציר שצייר המנווט (כתום)
                if (_showRoutes && hasPlannedPath)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: plannedPathPoints,
                      color: Colors.blue.withValues(alpha: _routesOpacity),
                      strokeWidth: 3.0,
                    ),
                  ]),
                if (_showNZ)
                  MarkerLayer(markers: markers.map((m) => Marker(
                    point: m.point,
                    width: m.width,
                    height: m.height,
                    child: Opacity(opacity: _nzOpacity, child: m.child),
                  )).toList()),
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
              onFullscreen: () => _openFullscreenMap(
                refPoints: refPoints,
                plannedPathPoints: plannedPathPoints,
                hasPlannedPath: hasPlannedPath,
                markers: markers,
                bounds: bounds,
              ),
              layers: [
                MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, onVisibilityChanged: (v) => setState(() => _showGG = v), opacity: _ggOpacity, onOpacityChanged: (v) => setState(() => _ggOpacity = v)),
                MapLayerConfig(id: 'nz', label: 'נקודות ציון', color: Colors.blue, visible: _showNZ, onVisibilityChanged: (v) => setState(() => _showNZ = v), opacity: _nzOpacity, onOpacityChanged: (v) => setState(() => _nzOpacity = v)),
                MapLayerConfig(id: 'nb', label: 'נקודות בטיחות', color: Colors.red, visible: _showNB, onVisibilityChanged: (v) => setState(() => _showNB = v), opacity: _nbOpacity, onOpacityChanged: (v) => setState(() => _nbOpacity = v)),
                MapLayerConfig(id: 'routes', label: 'מסלול', color: Colors.orange, visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v), opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreenMap({
    required List<LatLng> refPoints,
    required List<LatLng> plannedPathPoints,
    required bool hasPlannedPath,
    required List<Marker> markers,
    required LatLngBounds bounds,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenRouteMap(
          refPoints: refPoints,
          plannedPathPoints: plannedPathPoints,
          hasPlannedPath: hasPlannedPath,
          markers: markers,
          bounds: bounds,
          boundaries: _boundaries,
          safetyPoints: _safetyPoints,
          defaultMap: widget.navigation.displaySettings.defaultMap,
        ),
      ),
    );
  }

  /// בניית רשימת נקודות ציר מלאה: התחלה → ביניים → סיום
  Widget _buildCheckpointList() {
    // בניית רשימה מסודרת: התחלה, נקודות ציון, סיום
    final allCheckpoints = <_CheckpointDisplayItem>[];

    if (_startCheckpoint != null) {
      allCheckpoints.add(_CheckpointDisplayItem(
        checkpoint: _startCheckpoint!,
        role: _CheckpointRole.start,
      ));
    }

    // מזהי נקודות ביניים (waypoints)
    final waypointIds = <String>{};
    if (_currentNavigation.waypointSettings.enabled) {
      for (final wp in _currentNavigation.waypointSettings.waypoints) {
        waypointIds.add(wp.checkpointId);
      }
    }

    final middleCps = _routeCheckpoints.where(
      (cp) => cp.id != _startCheckpoint?.id && cp.id != _endCheckpoint?.id,
    ).toList();

    if (_currentNavigation.isClusters && _clusterMap.isNotEmpty) {
      // מצב אשכולות — הצגה מקובצת עם decoys
      final addedClusters = <String>{};
      int clusterIndex = 0;

      for (final cp in middleCps) {
        if (addedClusters.contains(cp.id)) continue;
        final isWaypoint = waypointIds.contains(cp.id);

        final cluster = _clusterMap[cp.id];
        if (cluster != null) {
          // אשכול — header + חברי אשכול
          addedClusters.add(cp.id);
          clusterIndex++;
          allCheckpoints.add(_CheckpointDisplayItem(
            checkpoint: cp,
            role: isWaypoint ? _CheckpointRole.waypoint : _CheckpointRole.middle,
            isClusterHeader: true,
            clusterSize: cluster.length,
            clusterId: cp.id,
            clusterIndex: clusterIndex,
          ));
          for (final clusterCp in cluster) {
            allCheckpoints.add(_CheckpointDisplayItem(
              checkpoint: clusterCp,
              role: _CheckpointRole.middle,
              isClusterMember: true,
              clusterId: cp.id,
            ));
          }
        } else {
          // אין אשכול — תצוגה רגילה
          allCheckpoints.add(_CheckpointDisplayItem(
            checkpoint: cp,
            role: isWaypoint ? _CheckpointRole.waypoint : _CheckpointRole.middle,
          ));
        }
      }
    } else {
      // מצב רגיל — ללא אשכולות
      for (final cp in middleCps) {
        final isWaypoint = waypointIds.contains(cp.id);
        allCheckpoints.add(_CheckpointDisplayItem(
          checkpoint: cp,
          role: isWaypoint ? _CheckpointRole.waypoint : _CheckpointRole.middle,
        ));
      }
    }

    if (_endCheckpoint != null) {
      allCheckpoints.add(_CheckpointDisplayItem(
        checkpoint: _endCheckpoint!,
        role: _CheckpointRole.end,
      ));
    }

    if (allCheckpoints.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('אין נקודות ציון'),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: allCheckpoints.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = allCheckpoints[index];
          final cp = item.checkpoint;

          // אשכול — header או חבר
          if (item.isCluster) {
            if (item.isClusterHeader) {
              final headerText = item.clusterSize > 1
                  ? 'אשכול ${item.clusterIndex} (${item.clusterSize} נקודות)'
                  : 'אשכול ${item.clusterIndex} (ללא נקודות הסחה)';
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: Colors.purple,
                  radius: 16,
                  child: Text(
                    '${item.clusterIndex}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  headerText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }
            // חבר אשכול — נקודה בתוך אשכול
            final utmStr = (cp.coordinates != null && cp.coordinates!.utm.isNotEmpty)
                ? cp.coordinates!.utm
                : cp.coordinates != null
                    ? UTMConverter.convertToUTM(cp.coordinates!.lat, cp.coordinates!.lng)
                    : '';
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: Colors.blue,
                radius: 14,
                child: Text(
                  '${cp.sequenceNumber}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(cp.name),
              subtitle: Text(
                utmStr,
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontFamily: 'monospace'),
              ),
            );
          }

          // צבע, אות ואייקון לפי תפקיד
          final Color circleColor;
          final IconData trailingIcon;
          final String? roleLetter; // H/S/B לנקודות מיוחדות
          switch (item.role) {
            case _CheckpointRole.start:
              circleColor = Colors.green;
              trailingIcon = Icons.play_arrow;
              roleLetter = 'H';
              break;
            case _CheckpointRole.end:
              circleColor = Colors.red;
              trailingIcon = Icons.flag;
              roleLetter = 'S';
              break;
            case _CheckpointRole.waypoint:
              circleColor = Colors.amber;
              trailingIcon = Icons.adjust;
              roleLetter = 'B';
              break;
            case _CheckpointRole.middle:
              circleColor = Colors.blue;
              trailingIcon = Icons.circle;
              roleLetter = null;
              break;
          }

          // חישוב UTM — אם יש ערך ב-coordinates.utm משתמשים בו, אחרת מחשבים
          final utmStr = (cp.coordinates != null && cp.coordinates!.utm.isNotEmpty)
              ? cp.coordinates!.utm
              : cp.coordinates != null
                  ? UTMConverter.convertToUTM(cp.coordinates!.lat, cp.coordinates!.lng)
                  : '';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: circleColor,
              child: Text(
                roleLetter ?? '${cp.sequenceNumber}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              cp.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cp.description.isNotEmpty)
                  Text(cp.description),
                Text(
                  utmStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            trailing: Icon(trailingIcon, size: 16, color: circleColor),
            isThreeLine: cp.description.isNotEmpty,
          );
        },
      ),
    );
  }

  Future<void> _openRouteEditor() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    // בדיקת נציג — אם יש קבוצה, וודא שהמנווט הוא הנציג
    final isRep = await _ensureLearningRepresentative();
    if (!isRep || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteEditorScreen(
          navigation: _currentNavigation,
          navigatorUid: widget.currentUser.uid,
          checkpoints: _routeCheckpoints,
          clusterMap: _currentNavigation.isClusters ? _clusterMap : null,
          onNavigationUpdated: (updatedNav) {
            setState(() => _currentNavigation = updatedNav);
            widget.onNavigationUpdated(updatedNav);
          },
        ),
      ),
    );
  }

  void _showRejectionNotes(String? notes) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הערות פסילת ציר'),
        content: Text(notes ?? 'לא צוינו הערות'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('הבנתי'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRouteForApproval() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final updatedRoute = route.copyWith(approvalStatus: 'pending_approval');
    final updatedRoutes = Map<String, domain.AssignedRoute>.from(
      _currentNavigation.routes,
    );
    updatedRoutes[widget.currentUser.uid] = updatedRoute;

    // עדכון סטטוס אישור לכל חברי הקבוצה
    if (route.groupId != null) {
      for (final entry in updatedRoutes.entries) {
        if (entry.value.groupId == route.groupId && entry.key != widget.currentUser.uid) {
          updatedRoutes[entry.key] = entry.value.copyWith(approvalStatus: 'pending_approval');
        }
      }
    }

    final updatedNav = _currentNavigation.copyWith(
      routes: updatedRoutes,
      updatedAt: DateTime.now(),
    );

    try {
      await _navigationRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);
      widget.onNavigationUpdated(updatedNav);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הציר נשלח לאישור המפקד')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשליחה: $e')),
        );
      }
    }
  }

  Widget _buildEditTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    final approvalStatus = route.approvalStatus;

    // צבע, אייקון וטקסט לפי סטטוס
    final Color statusColor;
    final IconData statusIcon;
    final String statusTitle;
    final String statusSubtitle;
    switch (approvalStatus) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusTitle = 'הציר מאושר';
        statusSubtitle = 'שינויים נוספים ידרשו שליחה מחדש';
        break;
      case 'pending_approval':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        statusTitle = 'ממתין לאישור';
        statusSubtitle = 'הציר נשלח למפקד — ממתין לאישור';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusTitle = 'ציר נפסל';
        statusSubtitle = 'לחץ על "קרא הערות" לפרטים, ערוך ושלח מחדש';
        break;
      default: // not_submitted
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        statusTitle = 'הציר טרם נשלח';
        statusSubtitle = 'סקור את הציר ושלח לאישור המפקד';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // סטטוס אישור
          Card(
            color: statusColor.withValues(alpha: 0.1),
            child: ListTile(
              leading: Icon(statusIcon, color: statusColor),
              title: Text(statusTitle),
              subtitle: Text(statusSubtitle),
            ),
          ),
          const SizedBox(height: 16),

          // כפתור עריכת ציר על המפה
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _checkpointsLoaded ? _openRouteEditor : null,
              icon: const Icon(Icons.map),
              label: Text(
                route.plannedPath.isEmpty
                    ? 'ערוך ציר על המפה'
                    : 'ערוך ציר על המפה (${route.plannedPath.length} נקודות)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // כפתור פסילה — כאשר הציר נפסל
          if (approvalStatus == 'rejected') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showRejectionNotes(route.rejectionNotes),
                icon: const Icon(Icons.cancel),
                label: const Text('ציר נפסל — לחץ כאן על מנת לקרוא הערות'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // הערה — אם הציר טרם נערך
          if (route.plannedPath.isEmpty &&
              (approvalStatus == 'not_submitted' || approvalStatus == 'rejected'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'יש לערוך את הציר על המפה לפני שליחה לאישור',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // כפתור שליחה/סטטוס
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (approvalStatus == 'not_submitted' || approvalStatus == 'rejected')
                      && route.plannedPath.isNotEmpty
                  ? _submitRouteForApproval
                  : null,
              icon: Icon(
                approvalStatus == 'approved'
                    ? Icons.check_circle
                    : approvalStatus == 'pending_approval'
                        ? Icons.hourglass_top
                        : Icons.send,
              ),
              label: Text(
                approvalStatus == 'approved'
                    ? 'ציר מאושר'
                    : approvalStatus == 'pending_approval'
                        ? 'ממתין לאישור'
                        : 'שלח ציר לאישור',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: approvalStatus == 'approved'
                    ? Colors.green
                    : approvalStatus == 'pending_approval'
                        ? Colors.orange
                        : Colors.red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: approvalStatus == 'approved'
                    ? Colors.green.withValues(alpha: 0.7)
                    : Colors.orange.withValues(alpha: 0.7),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // סיפור דרך — Narration
  // ===========================================================================

  void _loadNarrationFromRoute() {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route != null && route.narrationEntries.isNotEmpty) {
      _narrationEntries = List.from(route.narrationEntries);
    }
  }

  /// חישוב סיכומים מתוך הרשימה
  double get _totalSegmentKm {
    double sum = 0;
    for (final e in _narrationEntries) {
      sum += double.tryParse(e.segmentKm) ?? 0;
    }
    return sum;
  }

  double get _totalWalkingMin {
    return _narrationEntries
        .where((e) => e.walkingTimeMin != null)
        .fold<double>(0, (sum, e) => sum + e.walkingTimeMin!);
  }

  /// עיצוב דקות לתצוגה עם שעות (למשל: 115 → "שעה ו-55 דקות")
  String _formatMinutes(double minutes) {
    final totalMin = minutes.round();
    if (totalMin < 60) return '$totalMin דקות';

    final hours = totalMin ~/ 60;
    final remaining = totalMin % 60;

    String hourStr;
    if (hours == 1) {
      hourStr = 'שעה';
    } else if (hours == 2) {
      hourStr = 'שעתיים';
    } else {
      hourStr = '$hours שעות';
    }

    if (remaining == 0) return hourStr;
    return '$hourStr ו-$remaining דקות';
  }

  /// עדכון מספור ומרחק מצטבר אחרי כל שינוי
  void _recalculateIndicesAndCumulative() {
    double cumulative = 0;
    for (int i = 0; i < _narrationEntries.length; i++) {
      final seg = double.tryParse(_narrationEntries[i].segmentKm) ?? 0;
      cumulative += seg;
      _narrationEntries[i] = _narrationEntries[i].copyWith(
        index: i + 1,
        cumulativeKm: cumulative.toStringAsFixed(2),
      );
    }
  }

  void _confirmAndReplace(String title, VoidCallback onConfirm) {
    if (_narrationEntries.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: const Text('כבר קיימות שורות בטבלה. האם להחליף?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onConfirm();
              },
              child: const Text('החלף'),
            ),
          ],
        ),
      );
    } else {
      onConfirm();
    }
  }

  void _generateNarration() {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    _confirmAndReplace('סיפור דרך אוטומטי', () {
      final entries = NarrationGenerator.generateFromRoute(
        route: route,
        checkpoints: _routeCheckpoints,
      );
      setState(() {
        _narrationEntries = entries;
      });
    });
  }

  void _generateManualNarration() {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    _confirmAndReplace('סיפור דרך ידני', () {
      // ניווט הפוך — שימוש ברצף הפוך לתצוגה
      final effectiveSequence = _isReverseNavigation
          ? route.sequence.reversed.toList()
          : route.sequence;

      // יצירת שורות ריקות עם שמות נקודות בלבד
      final entries = <NarrationEntry>[];
      for (int i = 0; i < effectiveSequence.length; i++) {
        final cpId = effectiveSequence[i];
        final cp = _routeCheckpoints.length > i ? _routeCheckpoints[i] : null;
        final pointName = cp?.name ?? cpId;

        entries.add(NarrationEntry(
          index: i + 1,
          pointName: pointName,
          action: i == 0
              ? 'התחלה'
              : i == effectiveSequence.length - 1
                  ? 'סיום'
                  : 'מעבר',
        ));
      }
      setState(() {
        _narrationEntries = entries;
      });
    });
  }

  void _addNarrationRowAtEnd() {
    setState(() {
      _narrationEntries.add(NarrationEntry(
        index: _narrationEntries.length + 1,
        pointName: '',
      ));
      _recalculateIndicesAndCumulative();
    });
  }

  void _insertNarrationRowAfter(int index) {
    setState(() {
      _narrationEntries.insert(
        index + 1,
        NarrationEntry(index: index + 2, pointName: ''),
      );
      _recalculateIndicesAndCumulative();
    });
  }

  void _deleteNarrationRow(int index) {
    if (_narrationEntries.length <= 1) return;
    setState(() {
      _narrationEntries.removeAt(index);
      _recalculateIndicesAndCumulative();
    });
  }

  void _updateNarrationEntry(int index, NarrationEntry updated) {
    setState(() {
      _narrationEntries[index] = updated;
      _recalculateIndicesAndCumulative();
    });
  }

  Future<void> _saveNarration() async {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null) return;

    final updatedRoute = route.copyWith(narrationEntries: _narrationEntries);
    final updatedRoutes = Map<String, domain.AssignedRoute>.from(
      _currentNavigation.routes,
    );
    updatedRoutes[widget.currentUser.uid] = updatedRoute;

    // עדכון סיפור דרך לכל חברי הקבוצה (צמד/חוליה)
    if (route.groupId != null) {
      for (final entry in updatedRoutes.entries) {
        if (entry.value.groupId == route.groupId && entry.key != widget.currentUser.uid) {
          updatedRoutes[entry.key] = entry.value.copyWith(
            narrationEntries: _narrationEntries,
          );
        }
      }
    }

    final updatedNav = _currentNavigation.copyWith(
      routes: updatedRoutes,
      updatedAt: DateTime.now(),
    );

    try {
      await _navigationRepo.update(updatedNav);
      setState(() => _currentNavigation = updatedNav);
      widget.onNavigationUpdated(updatedNav);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('סיפור הדרך נשמר בהצלחה')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    }
  }

  void _openEntryEditor(int index) {
    final entry = _narrationEntries[index];
    final segmentCtrl = TextEditingController(text: entry.segmentKm);
    final pointNameCtrl = TextEditingController(text: entry.pointName);
    final bearingCtrl = TextEditingController(text: entry.bearing);
    final descCtrl = TextEditingController(text: entry.description);
    final actionCtrl = TextEditingController(text: entry.action);
    final obstaclesCtrl = TextEditingController(text: entry.obstacles);
    final elevCtrl = TextEditingController(
      text: entry.elevationM?.toString() ?? '',
    );
    final walkingCtrl = TextEditingController(
      text: entry.walkingTimeMin?.toStringAsFixed(1) ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('עריכת שורה ${entry.index}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: segmentCtrl,
                decoration: const InputDecoration(
                  labelText: 'מקטע (ק"מ)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pointNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'שם הנקודה',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bearingCtrl,
                decoration: const InputDecoration(
                  labelText: 'כיוון',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'תיאור הדרך',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: actionCtrl,
                decoration: const InputDecoration(
                  labelText: 'פעולה נדרשת',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: walkingCtrl,
                decoration: const InputDecoration(
                  labelText: 'זמן הליכה (דקות)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: elevCtrl,
                decoration: const InputDecoration(
                  labelText: 'גובה (מטרים)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obstaclesCtrl,
                decoration: const InputDecoration(
                  labelText: 'מכשולים / מגבלות',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              final elev = double.tryParse(elevCtrl.text);
              final walking = double.tryParse(walkingCtrl.text);
              // validate segmentKm — only numbers
              final segText = segmentCtrl.text.trim();
              final segValid = segText.isEmpty || double.tryParse(segText) != null;
              if (!segValid) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('מקטע (ק"מ) חייב להיות מספר')),
                );
                return;
              }
              _updateNarrationEntry(
                index,
                entry.copyWith(
                  segmentKm: segText,
                  pointName: pointNameCtrl.text,
                  bearing: bearingCtrl.text,
                  description: descCtrl.text,
                  action: actionCtrl.text,
                  walkingTimeMin: walking,
                  clearWalkingTime: walkingCtrl.text.isEmpty,
                  elevationM: elev,
                  clearElevation: elevCtrl.text.isEmpty,
                  obstacles: obstaclesCtrl.text,
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportNarrationCsv() async {
    if (_narrationEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין נתוני סיפור דרך לייצוא')),
      );
      return;
    }

    final rows = <List<String>>[
      ['מסד', 'מקטע (ק"מ)', 'נקודה', 'מרחק מצטבר (ק"מ)', 'כיוון', 'תיאור הדרך', 'פעולה נדרשת', 'זמן הליכה (דק\')', 'מכשולים'],
    ];

    for (final entry in _narrationEntries) {
      rows.add([
        '${entry.index}',
        entry.segmentKm,
        entry.pointName,
        entry.cumulativeKm,
        entry.bearing,
        entry.description,
        entry.action,
        entry.walkingTimeMin?.toStringAsFixed(1) ?? '',
        entry.obstacles,
      ]);
    }

    // שורת סיכום
    final totalKm = _totalSegmentKm;
    final totalMin = _totalWalkingMin;
    rows.add(['', '', '', totalKm.toStringAsFixed(2), '', '', 'סה"כ', totalMin.toStringAsFixed(1), '']);

    final csvData = const ListToCsvConverter().convert(rows);

    try {
      final fileName = 'סיפור_דרך_${_currentNavigation.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final fileBytes = Uint8List.fromList(utf8.encode('\uFEFF$csvData'));
      final result = await saveFileWithBytes(
        dialogTitle: 'שמור סיפור דרך CSV',
        fileName: fileName,
        bytes: fileBytes,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('סיפור דרך נשמר ב-\n$result'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא: $e')),
        );
      }
    }
  }

  Future<void> _exportNarrationPdf() async {
    if (_narrationEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין נתוני סיפור דרך לייצוא')),
      );
      return;
    }

    try {
      final regularFont = await PdfGoogleFonts.rubikRegular();
      final boldFont = await PdfGoogleFonts.rubikBold();

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
        ),
      );

      final totalKm = _totalSegmentKm;
      final totalMin = _totalWalkingMin;

      // חישוב גובה (אם הוזן)
      final elevEntries = _narrationEntries.where((e) => e.elevationM != null).toList();
      double? totalClimb;
      double? totalDescent;
      if (elevEntries.length >= 2) {
        totalClimb = 0;
        totalDescent = 0;
        for (int i = 1; i < elevEntries.length; i++) {
          final diff = elevEntries[i].elevationM! - elevEntries[i - 1].elevationM!;
          if (diff > 0) {
            totalClimb = totalClimb! + diff;
          } else {
            totalDescent = totalDescent! + diff.abs();
          }
        }
      }

      // PDF RTL — סדר עמודות הפוך: מכשולים ← ... ← מסד
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(20),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'סיפור דרך — ${_currentNavigation.name}',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'תאריך: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (context) => pw.Text(
            'Navigate App',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey),
          ),
          build: (context) => [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  // סדר הפוך RTL: מכשולים(0), זמן(1), פעולה(2), תיאור(3), כיוון(4), מצטבר(5), נקודה(6), מקטע(7), #(8)
                  0: const pw.FlexColumnWidth(1.2),  // מכשולים
                  1: const pw.FixedColumnWidth(40),   // זמן
                  2: const pw.FlexColumnWidth(1),     // פעולה
                  3: const pw.FlexColumnWidth(2.5),   // תיאור
                  4: const pw.FlexColumnWidth(1),     // כיוון
                  5: const pw.FixedColumnWidth(50),   // מצטבר
                  6: const pw.FlexColumnWidth(1.2),   // נקודה
                  7: const pw.FixedColumnWidth(45),   // מקטע
                  8: const pw.FixedColumnWidth(30),   // #
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.deepPurple50),
                    children: [
                      _pdfCell('מכשולים', bold: true),
                      _pdfCell('זמן', bold: true),
                      _pdfCell('פעולה', bold: true),
                      _pdfCell('תיאור הדרך', bold: true),
                      _pdfCell('כיוון', bold: true),
                      _pdfCell('מצטבר', bold: true),
                      _pdfCell('נקודה', bold: true),
                      _pdfCell('מקטע', bold: true),
                      _pdfCell('#', bold: true),
                    ],
                  ),
                  ..._narrationEntries.map((entry) => pw.TableRow(
                    children: [
                      _pdfCell(entry.obstacles),
                      _pdfCell(entry.walkingTimeMin?.toStringAsFixed(1) ?? ''),
                      _pdfCell(entry.action),
                      _pdfCell(entry.description),
                      _pdfCell(entry.bearing),
                      _pdfCell(entry.cumulativeKm),
                      _pdfCell(entry.pointName),
                      _pdfCell(entry.segmentKm),
                      _pdfCell('${entry.index}'),
                    ],
                  )),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('סיכום:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.SizedBox(height: 4),
                  pw.Text('אורך כולל: ${totalKm.toStringAsFixed(2)} ק"מ', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('זמן הליכה כולל (משוער): ${_formatMinutes(totalMin)}', style: const pw.TextStyle(fontSize: 10)),
                  if (totalClimb != null)
                    pw.Text('עלייה מצטברת: ${totalClimb.toStringAsFixed(0)} מ\' | ירידה מצטברת: ${totalDescent!.toStringAsFixed(0)} מ\'', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      );

      final pdfBytes = Uint8List.fromList(await pdf.save());
      final fileName = 'סיפור_דרך_${_currentNavigation.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final result = await saveFileWithBytes(
        dialogTitle: 'שמור סיפור דרך PDF',
        fileName: fileName,
        bytes: pdfBytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('סיפור דרך נשמר ב-PDF\n$result'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בייצוא PDF: $e')),
        );
      }
    }
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildNarrationTab() {
    final route = _currentNavigation.routes[widget.currentUser.uid];

    if (route == null) {
      return const Center(child: Text('לא הוקצה ציר'));
    }

    // סיכומים — חישוב מסכום המקטעים
    final totalKm = _totalSegmentKm;
    final totalMin = _totalWalkingMin;

    // גובה
    final elevEntries = _narrationEntries.where((e) => e.elevationM != null).toList();
    double? totalClimb;
    double? totalDescent;
    if (elevEntries.length >= 2) {
      totalClimb = 0;
      totalDescent = 0;
      for (int i = 1; i < elevEntries.length; i++) {
        final diff = elevEntries[i].elevationM! - elevEntries[i - 1].elevationM!;
        if (diff > 0) {
          totalClimb = totalClimb! + diff;
        } else {
          totalDescent = totalDescent! + diff.abs();
        }
      }
    }

    return Column(
      children: [
        // כפתורי פעולה עליונים
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _checkpointsLoaded ? _generateNarration : null,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('אוטומטי'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _checkpointsLoaded ? _generateManualNarration : null,
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('ידני'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple[300],
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _narrationEntries.isNotEmpty ? _saveNarration : null,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('שמור'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple),
              ),
              OutlinedButton.icon(
                onPressed: _narrationEntries.isNotEmpty ? _exportNarrationCsv : null,
                icon: const Icon(Icons.table_chart, size: 18),
                label: const Text('CSV'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.green[700]),
              ),
              OutlinedButton.icon(
                onPressed: _narrationEntries.isNotEmpty ? _exportNarrationPdf : null,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('PDF'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red[700]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // טבלה
        Expanded(
          child: _narrationEntries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.record_voice_over, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'טבלת סיפור דרך ריקה',
                        style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '"אוטומטי" — יצירה עם חישובים\n"ידני" — טבלה ריקה עם שמות נקודות',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // טבלה גלילה אופקית
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Colors.deepPurple[50]),
                          columnSpacing: 12,
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 80,
                          columns: const [
                            DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('מקטע\n(ק"מ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataColumn(label: Text('נקודה', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('מצטבר\n(ק"מ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataColumn(label: Text('כיוון', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('תיאור הדרך', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('פעולה', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('זמן\n(דק\')', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataColumn(label: Text('גובה\n(מ\')', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataColumn(label: Text('מכשולים', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('', style: TextStyle())), // פעולות
                          ],
                          rows: _narrationEntries.asMap().entries.map((mapEntry) {
                            final idx = mapEntry.key;
                            final entry = mapEntry.value;
                            return DataRow(
                              cells: [
                                DataCell(Text('${entry.index}')),
                                DataCell(Text(entry.segmentKm)),
                                DataCell(SizedBox(
                                  width: 100,
                                  child: Text(entry.pointName, overflow: TextOverflow.ellipsis),
                                )),
                                DataCell(Text(entry.cumulativeKm)),
                                DataCell(SizedBox(
                                  width: 120,
                                  child: Text(entry.bearing, style: const TextStyle(fontSize: 12)),
                                )),
                                DataCell(SizedBox(
                                  width: 200,
                                  child: Text(
                                    entry.description,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                                DataCell(SizedBox(
                                  width: 80,
                                  child: Text(entry.action),
                                )),
                                DataCell(Text(entry.walkingTimeMin?.toStringAsFixed(1) ?? '')),
                                DataCell(Text(entry.elevationM?.toStringAsFixed(0) ?? '')),
                                DataCell(SizedBox(
                                  width: 120,
                                  child: Text(
                                    entry.obstacles,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                                // פעולות: הוסף + ערוך + מחק
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.add_circle_outline, size: 18, color: Colors.green[700]),
                                      onPressed: () => _insertNarrationRowAfter(idx),
                                      tooltip: 'הוסף שורה מתחת',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _openEntryEditor(idx),
                                      tooltip: 'ערוך',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                                      onPressed: _narrationEntries.length > 1
                                          ? () => _deleteNarrationRow(idx)
                                          : null,
                                      tooltip: 'מחק שורה',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                )),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // כפתור הוספת שורה בסוף
                      Center(
                        child: TextButton.icon(
                          onPressed: _addNarrationRowAtEnd,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('הוסף שורה בסוף'),
                          style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // סיכום
                      Card(
                        color: Colors.deepPurple[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'סיכום',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              _infoCard('סה"כ נקודות', '${_narrationEntries.length}'),
                              _infoCard('אורך כולל', '${totalKm.toStringAsFixed(2)} ק"מ'),
                              _infoCard('זמן הליכה (משוער)', _formatMinutes(totalMin)),
                              if (totalClimb != null) ...[
                                _infoCard('עלייה מצטברת', '${totalClimb.toStringAsFixed(0)} מ\''),
                                _infoCard('ירידה מצטברת', '${totalDescent!.toStringAsFixed(0)} מ\''),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'שלב הלמידה פעיל',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'המפקד לא הפעיל הגדרות למידה נוספות',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  String _approvalStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'מאושר';
      case 'pending_approval':
        return 'ממתין לאישור';
      case 'rejected':
        return 'נפסל';
      default:
        return 'טרם נשלח';
    }
  }

  Widget _infoCard(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  /// האם המנווט הנוכחי משני בקבוצה (לא נציג)
  bool get _isGroupSecondary {
    final route = _currentNavigation.routes[widget.currentUser.uid];
    if (route == null || route.groupId == null) return false;
    final composition = _currentNavigation.forceComposition;
    if (!composition.isGrouped) return false;
    final rep = composition.getLearningRepresentative(route.groupId);
    return rep != null && rep != widget.currentUser.uid;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // באנר למנווט משני — "הנציג [שם] עורך את הציר עבור ה[צמד/חוליה]"
        if (_isGroupSecondary)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'הנציג ${_repName ?? ''} עורך את הציר עבור ה${_getCompositionLabel()}',
                    style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                  ),
                ),
              ],
            ),
          ),
        TabBar(
          controller: _tabController,
          isScrollable: _tabs.length > 3,
          tabs: _tabs.map((t) => Tab(text: t.label, icon: Icon(t.icon))).toList(),
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _tabs.map((t) => t.builder()).toList(),
          ),
        ),
      ],
    );
  }
}

class _LearningTab {
  final String label;
  final IconData icon;
  final Widget Function() builder;

  _LearningTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
}

enum _CheckpointRole { start, middle, end, waypoint }

class _CheckpointDisplayItem {
  final Checkpoint checkpoint;
  final _CheckpointRole role;
  final bool isClusterHeader;
  final bool isClusterMember;
  final int clusterSize;
  final String? clusterId;
  final int clusterIndex;

  const _CheckpointDisplayItem({
    required this.checkpoint,
    this.role = _CheckpointRole.middle,
    this.isClusterHeader = false,
    this.isClusterMember = false,
    this.clusterSize = 0,
    this.clusterId,
    this.clusterIndex = 0,
  });

  bool get isCluster => isClusterHeader || isClusterMember;
}

/// מסך מפה במסך מלא — הציר שלי
class _FullscreenRouteMap extends StatefulWidget {
  final List<LatLng> refPoints;
  final List<LatLng> plannedPathPoints;
  final bool hasPlannedPath;
  final List<Marker> markers;
  final LatLngBounds bounds;
  final List<Boundary> boundaries;
  final List<SafetyPoint> safetyPoints;
  final String? defaultMap;

  const _FullscreenRouteMap({
    required this.refPoints,
    required this.plannedPathPoints,
    required this.hasPlannedPath,
    required this.markers,
    required this.bounds,
    required this.boundaries,
    required this.safetyPoints,
    this.defaultMap,
  });

  @override
  State<_FullscreenRouteMap> createState() => _FullscreenRouteMapState();
}

class _FullscreenRouteMapState extends State<_FullscreenRouteMap> {
  final MapController _mapController = MapController();
  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  bool _showGG = true;
  bool _showNZ = true;
  bool _showNB = false;
  bool _showRoutes = true;

  double _ggOpacity = 1.0;
  double _nzOpacity = 1.0;
  double _nbOpacity = 1.0;
  double _routesOpacity = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('הציר שלי'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MapWithTypeSelector(
            mapController: _mapController,
            showTypeSelector: false,
            initialMapType: MapConfig.resolveMapType(widget.defaultMap),
            options: MapOptions(
              initialCenter: widget.bounds.center,
              initialZoom: 14.0,
              initialCameraFit: CameraFit.bounds(
                bounds: widget.bounds,
                padding: const EdgeInsets.all(40),
              ),
              onTap: (tapPosition, point) {
                if (_measureMode) {
                  setState(() => _measurePoints.add(point));
                }
              },
            ),
            layers: [
              if (_showGG && widget.boundaries.isNotEmpty)
                PolygonLayer(
                  polygons: widget.boundaries.map((b) => Polygon(
                    points: b.coordinates.map((c) => LatLng(c.lat, c.lng)).toList(),
                    color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                    borderColor: Colors.black.withValues(alpha: _ggOpacity),
                    borderStrokeWidth: b.strokeWidth,
                    isFilled: true,
                  )).toList(),
                ),
              if (_showNB && widget.safetyPoints.where((p) => p.type == 'point').isNotEmpty)
                MarkerLayer(
                  markers: widget.safetyPoints
                      .where((p) => p.type == 'point' && p.coordinates != null)
                      .map((point) => Marker(
                            point: LatLng(point.coordinates!.lat, point.coordinates!.lng),
                            width: 30, height: 30,
                            child: Opacity(opacity: _nbOpacity, child: const Icon(Icons.warning, color: Colors.red, size: 30)),
                          ))
                      .toList(),
                ),
              if (_showNB && widget.safetyPoints.where((p) => p.type == 'polygon').isNotEmpty)
                PolygonLayer(
                  polygons: widget.safetyPoints
                      .where((p) => p.type == 'polygon' && p.polygonCoordinates != null)
                      .map((point) => Polygon(
                            points: point.polygonCoordinates!.map((c) => LatLng(c.lat, c.lng)).toList(),
                            color: Colors.red.withValues(alpha: 0.2 * _nbOpacity),
                            borderColor: Colors.red.withValues(alpha: _nbOpacity), borderStrokeWidth: 2, isFilled: true,
                          ))
                      .toList(),
                ),
              if (_showRoutes && widget.refPoints.length > 1)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.refPoints,
                    color: Colors.blue.withValues(alpha: 0.3 * _routesOpacity),
                    strokeWidth: 2.0,
                  ),
                ]),
              if (_showRoutes && widget.hasPlannedPath)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.plannedPathPoints,
                    color: Colors.blue.withValues(alpha: _routesOpacity),
                    strokeWidth: 3.0,
                  ),
                ]),
              if (_showNZ)
                MarkerLayer(markers: widget.markers.map((m) => Marker(
                  point: m.point,
                  width: m.width,
                  height: m.height,
                  child: Opacity(opacity: _nzOpacity, child: m.child),
                )).toList()),
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
              MapLayerConfig(id: 'routes', label: 'מסלול', color: Colors.orange, visible: _showRoutes, onVisibilityChanged: (v) => setState(() => _showRoutes = v), opacity: _routesOpacity, onOpacityChanged: (v) => setState(() => _routesOpacity = v)),
            ],
          ),
        ],
      ),
    );
  }
}
