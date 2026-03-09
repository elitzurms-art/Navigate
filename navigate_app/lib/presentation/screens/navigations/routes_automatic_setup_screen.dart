import 'dart:math';

import 'package:flutter/material.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/safety_point_repository.dart';
import '../../../domain/entities/navigation_tree.dart';
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/safety_point.dart';
import '../../../data/repositories/boundary_repository.dart';
import '../../../services/routes_distribution_service.dart';
import '../../../services/navigation_layer_copy_service.dart';
import 'checkpoint_map_picker_screen.dart';
import 'routes_verification_screen.dart';

/// שלב 2 - הגדרות חלוקה אוטומטית
class RoutesAutomaticSetupScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesAutomaticSetupScreen({super.key, required this.navigation});

  @override
  State<RoutesAutomaticSetupScreen> createState() => _RoutesAutomaticSetupScreenState();
}

class _RoutesAutomaticSetupScreenState extends State<RoutesAutomaticSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final NavigationTreeRepository _treeRepo = NavigationTreeRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationLayerCopyService _layerCopyService = NavigationLayerCopyService();
  final RoutesDistributionService _distributionService = RoutesDistributionService();
  final UserRepository _userRepo = UserRepository();

  List<Checkpoint> _checkpoints = [];
  List<SafetyPoint> _safetyPoints = [];
  NavigationTree? _tree;
  Boundary? _boundary;
  bool _isLoading = false;

  // הגדרות
  String _navigationType = 'regular';
  String _executionOrder = 'sequential';
  double _minRouteLength = 5.0;
  double _maxRouteLength = 15.0;
  int _checkpointsPerNavigator = 5;
  String? _startPointId;
  String? _endPointId;

  // נקודות ביניים
  bool _waypointsEnabled = false;
  List<WaypointCheckpoint> _waypoints = [];

  // קריטריון ניקוד
  String _scoringCriterion = 'fairness';

  // הרכב הכוח
  String _forceComposition = 'solo';
  String? _swapPointId;
  Map<String, List<String>> _manualGroups = {};
  List<String> _navigatorsList = [];

  // כוכב — זמנים ומצב אוטומטי
  int _starLearningMinutes = 5;
  int _starNavigatingMinutes = 15;
  bool _starAutoMode = false;

  // אשכולות
  int _clusterSize = 3;
  int _clusterSpreadMeters = 200;
  bool _revealEnabled = true;
  int _revealAfterMinutes = 30;

  // צנחנים
  List<String> _dropPointIds = [];
  String _parachuteAssignmentMethod = 'random';
  Map<String, String> _navigatorDropPoints = {};
  Map<String, List<String>> _subFrameworkDropPoints = {};
  bool _samePointPerSubFramework = false;
  String _routeMode = 'checkpoints';

  // Progress
  bool _isDistributing = false;
  double _maxProgressRatio = 0;

  @override
  void initState() {
    super.initState();
    _initializeFromNavigation(widget.navigation);
    _loadData();
  }

  void _initializeFromNavigation(domain.Navigation nav) {
    setState(() {
      final knownTypes = {'regular', 'star', 'reverse', 'parachute', 'clusters', 'clusters_reverse'};
      _navigationType = knownTypes.contains(nav.navigationType) ? nav.navigationType! : 'regular';
      _executionOrder = nav.executionOrder ?? 'sequential';
      if (nav.routeLengthKm != null) {
        _minRouteLength = nav.routeLengthKm!.min;
        _maxRouteLength = nav.routeLengthKm!.max;
      }
      _checkpointsPerNavigator = nav.checkpointsPerNavigator ?? 5;
      _startPointId = nav.startPoint;
      _endPointId = nav.endPoint;

      // נקודות ביניים
      _waypointsEnabled = nav.waypointSettings.enabled;
      _waypoints = List.from(nav.waypointSettings.waypoints);

      // קריטריון חלוקה
      _scoringCriterion = nav.scoringCriterion ?? 'fairness';

      // כוכב
      _starLearningMinutes = nav.starLearningMinutes ?? 5;
      _starNavigatingMinutes = nav.starNavigatingMinutes ?? 15;
      _starAutoMode = nav.starAutoMode;

      // אשכולות
      _clusterSize = nav.clusterSettings.clusterSize;
      _clusterSpreadMeters = nav.clusterSettings.clusterSpreadMeters;
      _revealEnabled = nav.clusterSettings.revealEnabled;
      _revealAfterMinutes = nav.clusterSettings.revealAfterMinutes;

      // צנחנים
      if (nav.parachuteSettings != null) {
        final ps = nav.parachuteSettings!;
        _dropPointIds = List.from(ps.dropPointIds);
        _parachuteAssignmentMethod = ps.assignmentMethod;
        _navigatorDropPoints = Map.from(ps.navigatorDropPoints);
        _subFrameworkDropPoints = ps.subFrameworkDropPoints.map((k, v) => MapEntry(k, List<String>.from(v)));
        _samePointPerSubFramework = ps.samePointPerSubFramework;
        _routeMode = ps.routeMode;
      }

      // הרכב הכוח
      _forceComposition = nav.forceComposition.type;
      _swapPointId = nav.forceComposition.swapPointId;
      _manualGroups = Map.from(nav.forceComposition.manualGroups.map(
        (k, v) => MapEntry(k, List<String>.from(v)),
      ));
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // טעינת ניווט עדכני מה-DB (ולא widget.navigation שעלול להיות ישן)
      final freshNav = await _navRepo.getById(widget.navigation.id);
      if (freshNav != null) {
        _initializeFromNavigation(freshNav);
      }

      // טעינת נקודות ציון מהשכבות הניווטיות (כבר מסוננות לפי גבול גזרה)
      var navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
        widget.navigation.id,
      );

      // אם אין נקודות ניווטיות — ננסה להעתיק שכבות מהשטח
      if (navCheckpoints.isEmpty) {
        await _layerCopyService.copyLayersForNavigation(
          navigationId: widget.navigation.id,
          boundaryId: widget.navigation.boundaryLayerId ?? '',
          areaId: widget.navigation.areaId,
          createdBy: '',
        );
        // ניסיון חוזר לטעינה
        navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
          widget.navigation.id,
        );
      }

      // אם עדיין אין — טעינה ישירה מנקודות השטח
      List<Checkpoint> checkpoints;
      if (navCheckpoints.isEmpty) {
        checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      } else {
        // המרה ל-Checkpoint עם sourceId כ-ID (תאימות לאחור)
        checkpoints = navCheckpoints.map((nc) => Checkpoint(
          id: nc.sourceId,
          areaId: nc.areaId,
          name: nc.name,
          description: nc.description,
          type: nc.type,
          color: nc.color,
          coordinates: nc.coordinates,
          sequenceNumber: nc.sequenceNumber,
          labels: nc.labels,
          createdBy: nc.createdBy,
          createdAt: nc.createdAt,
        )).toList();
      }

      // טעינת עץ מבנה
      final tree = await _treeRepo.getById(widget.navigation.treeId);

      // טעינת רשימת מנווטים
      final navigatorsList = await _loadNavigatorsList(tree);

      // טעינת גבול גזרה (לשימוש במפת בחירת נקודות)
      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await BoundaryRepository().getById(widget.navigation.boundaryLayerId!);
      }

      // טעינת נת"בים לסינון בחלוקה אוטומטית
      List<SafetyPoint> safetyPoints = [];
      try {
        final navSafetyPoints = await _navLayerRepo.getSafetyPointsByNavigation(
          widget.navigation.id,
        );
        if (navSafetyPoints.isNotEmpty) {
          safetyPoints = navSafetyPoints.map((nsp) => SafetyPoint(
            id: nsp.sourceId,
            areaId: nsp.areaId,
            name: nsp.name,
            description: nsp.description,
            type: nsp.type,
            coordinates: nsp.coordinates,
            polygonCoordinates: nsp.polygonCoordinates,
            sequenceNumber: nsp.sequenceNumber,
            severity: nsp.severity,
            createdAt: nsp.createdAt,
            updatedAt: nsp.updatedAt,
          )).toList();
        } else {
          safetyPoints = await SafetyPointRepository().getByArea(widget.navigation.areaId);
        }
      } catch (_) {}

      // ניקוי נקודות שלא קיימות ברשימת הנקודות הטעונות
      final cpIds = checkpoints.map((c) => c.id).toSet();
      if (_startPointId != null && !cpIds.contains(_startPointId)) {
        _startPointId = null;
      }
      if (_endPointId != null && !cpIds.contains(_endPointId)) {
        _endPointId = null;
      }
      if (_swapPointId != null && !cpIds.contains(_swapPointId)) {
        _swapPointId = null;
      }
      _waypoints.removeWhere((w) => !cpIds.contains(w.checkpointId));

      setState(() {
        _checkpoints = checkpoints;
        _safetyPoints = safetyPoints;
        _tree = tree;
        _boundary = boundary;
        _navigatorsList = navigatorsList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בטעינת נתונים: $e')),
        );
      }
    }
  }

  Future<List<String>> _loadNavigatorsList(NavigationTree? tree) async {
    if (tree == null) return [];
    final nav = widget.navigation;
    // אם נבחרו משתתפים ספציפיים
    if (nav.selectedParticipantIds.isNotEmpty) {
      final result = <String>[];
      for (final uid in nav.selectedParticipantIds) {
        final user = await _userRepo.getUser(uid);
        if (user != null && user.role == 'navigator') result.add(uid);
      }
      return result;
    }
    // fallback: מנווטים מהיחידה
    final unitId = nav.selectedUnitId ?? tree.unitId;
    if (unitId == null) return [];
    final users = await _userRepo.getNavigatorsForUnit(unitId);
    return users.map((u) => u.uid).toList();
  }

  Future<void> _saveSettings() async {
    final settingsNav = widget.navigation.copyWith(
      navigationType: _navigationType,
      executionOrder: _executionOrder,
      routeLengthKm: domain.RouteLengthRange(min: _minRouteLength, max: _maxRouteLength),
      checkpointsPerNavigator: _checkpointsPerNavigator,
      startPoint: _startPointId,
      endPoint: _endPointId,
      waypointSettings: WaypointSettings(enabled: _waypointsEnabled, waypoints: _waypoints),
      scoringCriterion: _scoringCriterion,
      forceComposition: ForceComposition(
        type: _forceComposition,
        swapPointId: _swapPointId,
        manualGroups: _manualGroups,
      ),
      starLearningMinutes: _navigationType == 'star' ? _starLearningMinutes : null,
      starNavigatingMinutes: _navigationType == 'star' ? _starNavigatingMinutes : null,
      starAutoMode: _navigationType == 'star' ? _starAutoMode : false,
      clusterSettings: (_navigationType == 'clusters' || _navigationType == 'clusters_reverse' || (_navigationType == 'parachute' && _routeMode == 'clusters'))
          ? ClusterSettings(
              clusterSize: _clusterSize,
              clusterSpreadMeters: _clusterSpreadMeters,
              revealEnabled: _revealEnabled,
              revealAfterMinutes: _revealAfterMinutes,
            )
          : const ClusterSettings(),
      parachuteSettings: _navigationType == 'parachute'
          ? ParachuteSettings(
              dropPointIds: _dropPointIds,
              assignmentMethod: _parachuteAssignmentMethod,
              navigatorDropPoints: _navigatorDropPoints,
              subFrameworkDropPoints: _subFrameworkDropPoints,
              samePointPerSubFramework: _samePointPerSubFramework,
              routeMode: _routeMode,
            )
          : null,
      clearParachuteSettings: _navigationType != 'parachute',
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(settingsNav);
  }

  Future<void> _distribute() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tree == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נטען עץ מבנה')),
      );
      return;
    }

    // כוכב: חובה לבחור נקודה מרכזית; רגיל: חובה התחלה + סיום
    if (_navigationType == 'star') {
      if (_startPointId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('חובה לבחור נקודה מרכזית'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // וידוא שההתחלה = הסיום
      _endPointId = _startPointId;
    } else if (_navigationType == 'parachute') {
      if (_endPointId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('חובה לבחור נקודת סיום'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else {
      if (_startPointId == null || _endPointId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('חובה לבחור נקודת התחלה ונקודת סיום'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // ולידציות הרכב הכוח (לפני _isDistributing)
    if (_forceComposition != 'solo') {
      if (_navigatorsList.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נדרשים לפחות 2 מנווטים להרכב לא-בדד')),
        );
        return;
      }
      if (_forceComposition == 'squad' && _navigatorsList.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נדרשים לפחות 4 מנווטים להרכב חוליה')),
        );
        return;
      }

      // שיבוץ אוטומטי אם לא הוגדרו קבוצות עדיין
      if (_manualGroups.isEmpty) {
        _autoAssignGroups();
      }

      // ולידציה: בדיקה שאין קבוצה שחורגת מהגודל המקסימלי
      final maxSize = ForceComposition(type: _forceComposition).maxGroupSize;
      final oversizedGroups = _manualGroups.entries
          .where((e) => e.value.length > maxSize)
          .toList();
      if (oversizedGroups.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('יש קבוצות עם יותר מ-$maxSize חברים — יש לאזן לפני החלוקה')),
        );
        return;
      }
    }

    // שמירת הגדרות לפני החלוקה — כך שהן נשמרות גם אם החלוקה נכשלת או בוטלה
    await _saveSettings();

    setState(() {
      _isDistributing = true;
      _maxProgressRatio = 0;
    });

    final composition = ForceComposition(
      type: _forceComposition,
      swapPointId: _swapPointId,
      manualGroups: _manualGroups,
    );

    try {
      final distributionResult = await _distributionService.distributeAutomatically(
        navigation: widget.navigation,
        tree: _tree!,
        checkpoints: _checkpoints,
        boundary: null,
        startPointId: _startPointId,
        endPointId: _endPointId,
        waypoints: _waypointsEnabled ? _waypoints : [],
        executionOrder: _executionOrder,
        checkpointsPerNavigator: _checkpointsPerNavigator,
        minRouteLength: _minRouteLength,
        maxRouteLength: _maxRouteLength,
        scoringCriterion: _scoringCriterion,
        forceComposition: composition,
        safetyPoints: _safetyPoints,
        onProgress: (current, total) {
          if (mounted) {
            final ratio = total > 0 ? current / total : 0.0;
            if (ratio > _maxProgressRatio) {
              setState(() => _maxProgressRatio = ratio);
            }
          }
        },
      );

      setState(() => _isDistributing = false);

      // --- טיפול בתוצאה ---
      if (distributionResult.needsApproval) {
        final approved = await _showApprovalDialog(distributionResult);
        if (approved == null) return; // ביטל

        if (approved == 'accept_best') {
          // אישור החלוקה הטובה ביותר כמו שהיא
          await _saveAndNavigate(distributionResult.routes, distributionResult);
        } else if (approved == 'expand_range') {
          // הרצה מחדש עם טווח מורחב
          final option = distributionResult.approvalOptions
              .firstWhere((o) => o.type == 'expand_range');
          setState(() {
            _minRouteLength = option.expandedMin!;
            _maxRouteLength = option.expandedMax!;
          });
          await _distribute(); // הרצה מחדש
        } else if (approved == 'reduce_checkpoints') {
          // הרצה מחדש עם פחות נקודות
          final option = distributionResult.approvalOptions
              .firstWhere((o) => o.type == 'reduce_checkpoints');
          setState(() {
            _checkpointsPerNavigator = option.reducedCheckpoints!;
          });
          await _distribute(); // הרצה מחדש
        }
      } else {
        // הצלחה — שמירה ומעבר לוידוא
        await _saveAndNavigate(distributionResult.routes, distributionResult);
      }
    } catch (e) {
      setState(() => _isDistributing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בחלוקה: $e')),
        );
      }
    }
  }

  Future<String?> _showApprovalDialog(domain.DistributionResult result) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // סיכום צירים חורגים
        final outOfRange = result.routes.values.where((r) => r.status != 'optimal').length;
        final total = result.routes.length;

        // מאבטח: פירוט סטטוס לכל חצי ציר
        final isGuardMode = _forceComposition == 'guard';
        int tooShortCount = 0;
        int tooLongCount = 0;
        if (isGuardMode) {
          for (final r in result.routes.values) {
            if (r.status == 'too_short') tooShortCount++;
            if (r.status == 'too_long') tooLongCount++;
          }
        }

        return AlertDialog(
          title: const Text('חלוקה חורגת מהטווח'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$outOfRange מתוך $total צירים חורגים מטווח '
                '${_minRouteLength.toStringAsFixed(1)} — ${_maxRouteLength.toStringAsFixed(1)} ק"מ',
                style: const TextStyle(fontSize: 14),
              ),
              if (isGuardMode && (tooShortCount > 0 || tooLongCount > 0)) ...[
                const SizedBox(height: 6),
                if (tooShortCount > 0)
                  Text(
                    '$tooShortCount חצאי ציר קצרים מדי',
                    style: TextStyle(fontSize: 13, color: Colors.yellow[700]),
                  ),
                if (tooLongCount > 0)
                  Text(
                    '$tooLongCount חצאי ציר ארוכים מדי',
                    style: TextStyle(fontSize: 13, color: Colors.red[700]),
                  ),
              ],
              if (result.hasSharedCheckpoints) ...[
                const SizedBox(height: 8),
                Text(
                  '${result.sharedCheckpointCount} נקודות משותפות בין מנווטים',
                  style: TextStyle(fontSize: 13, color: Colors.orange[700]),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'בחר פעולה:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...result.approvalOptions.map((option) {
                IconData icon;
                Color color;
                switch (option.type) {
                  case 'expand_range':
                    icon = Icons.open_in_full;
                    color = Colors.blue;
                    break;
                  case 'reduce_checkpoints':
                    icon = Icons.remove_circle_outline;
                    color = Colors.orange;
                    break;
                  case 'accept_best':
                    icon = Icons.check_circle_outline;
                    color = Colors.green;
                    break;
                  default:
                    icon = Icons.help_outline;
                    color = Colors.grey;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, option.type),
                    icon: Icon(icon, color: color),
                    label: Text(option.label),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      minimumSize: const Size(double.infinity, 44),
                      alignment: Alignment.centerRight,
                    ),
                  ),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('ביטול'),
            ),
          ],
        );
      },
    );
  }

  /// בודק אם יש מספיק נקודות הסחה לכל אשכול בכל ציר.
  /// מחזיר null אם הכל תקין, אחרת מפה: navigatorId → רשימת (cpName, actualSize).
  Map<String, List<(String, int)>>? _validateClusterDecoys(
      Map<String, domain.AssignedRoute> routes) {
    if (_navigationType != 'clusters' && _navigationType != 'clusters_reverse') return null;

    final allUndersized = <String, List<(String, int)>>{};

    for (final entry in routes.entries) {
      final route = entry.value;
      final specialIds = <String>{};
      if (route.startPointId != null) specialIds.add(route.startPointId!);
      if (route.endPointId != null) specialIds.add(route.endPointId!);
      for (final wpId in route.waypointIds) {
        specialIds.add(wpId);
      }

      final assignedCpIds = route.checkpointIds.toSet();
      final usedDecoys = <String>{};
      final neededDecoys = _clusterSize - 1;
      final undersized = <(String, int)>[];

      // נקודות אמצע בלבד (ללא התחלה/סיום/ביניים/פוליגון)
      final middleCps = route.checkpointIds
          .where((id) => !specialIds.contains(id))
          .map((id) {
            try {
              return _checkpoints.firstWhere((cp) => cp.id == id);
            } catch (_) {
              return null;
            }
          })
          .where((cp) => cp != null && cp.coordinates != null && !cp.isPolygon)
          .cast<Checkpoint>()
          .toList();

      for (final realCp in middleCps) {
        final candidates = _checkpoints
            .where((cp) => cp.id != realCp.id
                && !specialIds.contains(cp.id)
                && !assignedCpIds.contains(cp.id)
                && !usedDecoys.contains(cp.id)
                && cp.coordinates != null && !cp.isPolygon
                && GeometryUtils.distanceBetweenMeters(realCp.coordinates!, cp.coordinates!) <= _clusterSpreadMeters)
            .toList();
        candidates.sort((a, b) =>
            GeometryUtils.distanceBetweenMeters(realCp.coordinates!, a.coordinates!)
                .compareTo(GeometryUtils.distanceBetweenMeters(realCp.coordinates!, b.coordinates!)));
        final actualDecoys = candidates.take(neededDecoys).toList();
        for (final d in actualDecoys) {
          usedDecoys.add(d.id);
        }

        final actualSize = 1 + actualDecoys.length;
        if (actualSize < _clusterSize) {
          undersized.add((realCp.name, actualSize));
        }
      }

      if (undersized.isNotEmpty) allUndersized[entry.key] = undersized;
    }

    return allUndersized.isEmpty ? null : allUndersized;
  }

  Future<String?> _showClusterValidationDialog(
      Map<String, List<(String, int)>> undersized) {
    final minSize = undersized.values
        .expand((list) => list.map((e) => e.$2))
        .reduce(min);

    final totalUndersized = undersized.values.expand((l) => l).length;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('אשכולות עם חוסר בנקודות'),
        content: Text(
          'רדיוס חיפוש: $_clusterSpreadMeters מטר\n'
          'גודל אשכול: $_clusterSize\n\n'
          '$totalUndersized אשכולות עם פחות נקודות מהנדרש.\n'
          'גודל מינימלי שנמצא: $minSize',
        ),
        actions: [
          if (_clusterSpreadMeters < 6000)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'increase_radius'),
              child: const Text('הגדל רדיוס'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reduce_all'),
            child: Text('הקטן אשכולות ל-$minSize'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'accept'),
            child: const Text('המשך בכל זאת'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndNavigate(
    Map<String, domain.AssignedRoute> routes,
    domain.DistributionResult distributionResult,
  ) async {
    // הצגת הודעה על שיתוף אם יש
    if (distributionResult.hasSharedCheckpoints && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'שים לב: ${distributionResult.sharedCheckpointCount} נקודות משותפות בין מנווטים',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // ולידציית אשכולות — בדיקת מספיק נקודות הסחה
    if (_navigationType == 'clusters' || _navigationType == 'clusters_reverse') {
      final undersized = _validateClusterDecoys(routes);
      if (undersized != null && mounted) {
        final action = await _showClusterValidationDialog(undersized);
        if (!mounted) return;

        if (action == 'increase_radius') {
          _clusterSpreadMeters = (_clusterSpreadMeters + 100).clamp(50, 6000);
          setState(() {});
          return _saveAndNavigate(routes, distributionResult);
        } else if (action == 'reduce_all') {
          final minSize = undersized.values
              .expand((l) => l.map((e) => e.$2))
              .reduce(min);
          _clusterSize = minSize;
          setState(() {});
          // ממשיכים עם גודל מוקטן
        } else if (action == null) {
          return; // ביטל
        }
        // 'accept' → ממשיכים כרגיל
      }
    }

    // שמירת הגדרות + צירים + סטטוס חלוקה
    await _saveSettings();
    final updatedNavigation = widget.navigation.copyWith(
      routes: routes,
      routesStage: 'verification',
      routesDistributed: true,
      navigationType: _navigationType,
      executionOrder: _executionOrder,
      routeLengthKm: domain.RouteLengthRange(
        min: _minRouteLength,
        max: _maxRouteLength,
      ),
      checkpointsPerNavigator: _checkpointsPerNavigator,
      startPoint: _startPointId,
      endPoint: _endPointId,
      waypointSettings: WaypointSettings(
        enabled: _waypointsEnabled,
        waypoints: _waypoints,
      ),
      forceComposition: distributionResult.forceComposition ?? ForceComposition(
        type: _forceComposition,
        swapPointId: _swapPointId,
        manualGroups: _manualGroups,
      ),
      clusterSettings: (_navigationType == 'clusters' || _navigationType == 'clusters_reverse')
          ? ClusterSettings(
              clusterSize: _clusterSize,
              clusterSpreadMeters: _clusterSpreadMeters,
              revealEnabled: _revealEnabled,
              revealAfterMinutes: _revealAfterMinutes,
            )
          : const ClusterSettings(),
      starLearningMinutes: _navigationType == 'star' ? _starLearningMinutes : null,
      starNavigatingMinutes: _navigationType == 'star' ? _starNavigatingMinutes : null,
      starAutoMode: _navigationType == 'star' ? _starAutoMode : false,
      updatedAt: DateTime.now(),
    );

    await _navRepo.update(updatedNavigation);

    if (mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RoutesVerificationScreen(navigation: updatedNavigation),
        ),
      );
      if (result == true && mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveSettings();
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('חלוקה אוטומטית'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isDistributing
              ? _buildProgressView()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'הגדרות חלוקה',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // סוג ניווט
                        _buildNavigationTypeSection(),
                        const SizedBox(height: 16),

                        // נקודות הצנחה (צנחנים בלבד)
                        if (_navigationType == 'parachute') ...[
                          _buildDropPointsSection(),
                          const SizedBox(height: 16),
                        ],

                        // הרכב הכוח
                        _buildForceCompositionSection(),
                        const SizedBox(height: 16),

                        // שיבוץ קבוצות (רק כשהרכב ≠ בדד)
                        if (_forceComposition != 'solo') ...[
                          _buildGroupsSection(),
                          const SizedBox(height: 16),
                        ],

                        // אופן ביצוע (לא בכוכב)
                        if (_navigationType != 'star') ...[
                          _buildExecutionOrderSection(),
                          const SizedBox(height: 16),
                        ],

                        // טווח אורך ציר / טווח מרחקי נקודות
                        _buildRouteLengthSection(),
                        const SizedBox(height: 16),

                        // כמות נקודות למנווט
                        _buildCheckpointsPerNavigatorSection(),
                        const SizedBox(height: 16),

                        // זמני למידה/ניווט ומצב אוטומטי (כוכב בלבד)
                        if (_navigationType == 'star') ...[
                          _buildStarTimeSection(),
                          const SizedBox(height: 16),
                        ],

                        // נקודה מרכזית (כוכב) / נקודות התחלה וסיום (רגיל)
                        _buildStartEndPointsSection(),
                        const SizedBox(height: 16),

                        // נקודות ביניים (לא בכוכב)
                        if (_navigationType != 'star') ...[
                          _buildWaypointsSection(),
                          const SizedBox(height: 16),
                        ],

                        // קריטריון ניקוד
                        _buildScoringCriterionSection(),
                        const SizedBox(height: 24),

                        // אשכולות
                        if (_navigationType == 'clusters' || _navigationType == 'clusters_reverse' || (_navigationType == 'parachute' && _routeMode == 'clusters'))
                          _buildClustersSection(),

                        const SizedBox(height: 32),

                        // כפתור חלוקה
                        if (_forceComposition == 'guard' && _swapPointId == null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              border: Border.all(color: Colors.orange),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.orange[800]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'לא ניתן לבצע חלוקה במצב מאבטח ללא בחירת נקודת החלפה',
                                    style: TextStyle(color: Colors.orange[900], fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: (_forceComposition == 'guard' && _swapPointId == null)
                                ? null
                                : _distribute,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('חלק אוטומטית'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildProgressView() {
    // Bar never goes backwards (phase 2 may reset total)
    final progress = _maxProgressRatio;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'מחלק צירים...',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'בודק אופציות חלוקה...',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoringCriterionSection() {
    final isStar = _navigationType == 'star';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'קריטריון חלוקה',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'איך האלגוריתם בוחר את החלוקה הטובה ביותר',
                  child: Icon(Icons.info_outline, size: 18, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isStar)
              RadioListTile<String>(
                title: const Text('הוגנות'),
                subtitle: const Text('אורך צירים אחיד ככל האפשר'),
                value: 'fairness',
                groupValue: _scoringCriterion,
                onChanged: (value) => setState(() => _scoringCriterion = value!),
              ),
            if (!isStar)
              RadioListTile<String>(
                title: const Text('קרבה לאמצע הטווח'),
                subtitle: const Text('כל הצירים קרובים לאמצע הטווח'),
                value: 'midpoint',
                groupValue: _scoringCriterion,
                onChanged: (value) => setState(() => _scoringCriterion = value!),
              ),
            RadioListTile<String>(
              title: const Text('מקסימום ייחודיות'),
              subtitle: Text(isStar
                  ? 'כמה שפחות נקודות משותפות בין מנווטים'
                  : 'כמה שפחות נקודות משותפות בין מנווטים'),
              value: 'uniqueness',
              groupValue: _scoringCriterion,
              onChanged: (value) => setState(() => _scoringCriterion = value!),
            ),
            RadioListTile<String>(
              title: const Text('אימות כפול'),
              subtitle: const Text('כל נקודה נבדקת ע"י 2 מנווטים שונים'),
              value: 'doubleCheck',
              groupValue: _scoringCriterion,
              onChanged: (value) => setState(() => _scoringCriterion = value!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationTypeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'סוג ניווט',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _navigationType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר סוג',
              ),
              items: const [
                DropdownMenuItem(value: 'regular', child: Text('רגיל')),
                DropdownMenuItem(value: 'star', child: Text('כוכב')),
                DropdownMenuItem(value: 'reverse', child: Text('הפוך')),
                DropdownMenuItem(
                  value: 'parachute',
                  child: Text('צנחנים'),
                ),
                DropdownMenuItem(value: 'clusters', child: Text('אשכולות')),
                DropdownMenuItem(value: 'clusters_reverse', child: Text('אשכולות הפוך')),
              ],
              onChanged: (value) {
                setState(() {
                  _navigationType = value!;
                  if (value == 'star') {
                    // כוכב: אין מאבטח
                    if (_forceComposition == 'guard') {
                      _forceComposition = 'solo';
                      _swapPointId = null;
                      _manualGroups = {};
                    }
                    // כוכב: רק uniqueness או doubleCheck
                    if (_scoringCriterion != 'uniqueness' && _scoringCriterion != 'doubleCheck') {
                      _scoringCriterion = 'uniqueness';
                    }
                    // כוכב: אין נקודות ביניים
                    _waypointsEnabled = false;
                    _waypoints = [];
                    // כוכב: נקודת סיום = נקודת התחלה (נקודה מרכזית)
                    _endPointId = _startPointId;
                  }
                  if (value == 'clusters' || value == 'clusters_reverse') {
                    // אשכולות: אין מאבטח
                    if (_forceComposition == 'guard') {
                      _forceComposition = 'solo';
                      _swapPointId = null;
                      _manualGroups = {};
                    }
                  }
                  if (value == 'parachute') {
                    // צנחנים: אין מאבטח
                    if (_forceComposition == 'guard') {
                      _forceComposition = 'solo';
                      _swapPointId = null;
                      _manualGroups = {};
                    }
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionOrderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'אופן ביצוע',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              title: const Text('לפי סדר הנקודות'),
              subtitle: const Text('המנווט חייב לעבור בנקודות לפי הסדר'),
              value: 'sequential',
              groupValue: _executionOrder,
              onChanged: (value) {
                setState(() => _executionOrder = value!);
              },
            ),
            RadioListTile<String>(
              title: const Text('לפי בחירת המנווט'),
              subtitle: const Text('המנווט יכול לבחור את סדר הנקודות'),
              value: 'navigator_choice',
              groupValue: _executionOrder,
              onChanged: (value) {
                setState(() => _executionOrder = value!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteLengthSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _navigationType == 'star'
                  ? 'טווח מרחקי נקודות (ק"מ)'
                  : 'טווח אורך ציר (ק"מ)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _minRouteLength.toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'מינימום',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'שדה חובה';
                      final num = double.tryParse(value);
                      if (num == null || num <= 0) return 'מספר חיובי';
                      return null;
                    },
                    onChanged: (value) {
                      _minRouteLength = double.tryParse(value) ?? _minRouteLength;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: _maxRouteLength.toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'מקסימום',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'שדה חובה';
                      final num = double.tryParse(value);
                      if (num == null || num <= 0) return 'מספר חיובי';
                      if (num < _minRouteLength) return 'גדול ממינימום';
                      return null;
                    },
                    onChanged: (value) {
                      _maxRouteLength = double.tryParse(value) ?? _maxRouteLength;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckpointsPerNavigatorSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'כמות נקודות ציון למנווט',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _checkpointsPerNavigator.toString(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'מספר נקודות (1-10)',
                helperText: 'כל מנווט יקבל אותו מספר נקודות',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) return 'שדה חובה';
                final num = int.tryParse(value);
                if (num == null || num < 1 || num > 10) return 'בין 1 ל-10';
                return null;
              },
              onChanged: (value) {
                _checkpointsPerNavigator = int.tryParse(value) ?? _checkpointsPerNavigator;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarTimeSection() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer, size: 20),
                const SizedBox(width: 8),
                const Text('זמני כוכב', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'זמן למידה וניווט ברירת מחדל לכל נקודה. ניתן לשנות בזמן הניווט',
                  child: Icon(Icons.info_outline, size: 16, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '$_starLearningMinutes',
                    decoration: const InputDecoration(
                      labelText: 'זמן למידה (דקות)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final val = int.tryParse(v ?? '');
                      if (val == null || val < 1 || val > 30) return '1-30';
                      return null;
                    },
                    onChanged: (v) {
                      final val = int.tryParse(v);
                      if (val != null && val >= 1 && val <= 30) {
                        _starLearningMinutes = val;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: '$_starNavigatingMinutes',
                    decoration: const InputDecoration(
                      labelText: 'זמן ניווט (דקות)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final val = int.tryParse(v ?? '');
                      if (val == null || val < 1 || val > 120) return '1-120';
                      return null;
                    },
                    onChanged: (v) {
                      final val = int.tryParse(v);
                      if (val != null && val >= 1 && val <= 120) {
                        _starNavigatingMinutes = val;
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _starAutoMode,
              onChanged: (v) => setState(() => _starAutoMode = v),
              title: const Text('מצב אוטומטי'),
              subtitle: const Text(
                'הנקודה הבאה נפתחת אוטומטית כשהמנווט חוזר למרכז',
                style: TextStyle(fontSize: 12),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartEndPointsSection() {
    final isStar = _navigationType == 'star';
    final isParachute = _navigationType == 'parachute';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isStar ? 'נקודה מרכזית' : isParachute ? 'נקודת סיום' : (_forceComposition == 'guard' ? 'נקודות התחלה, החלפה וסיום' : 'נקודות התחלה וסיום'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: isStar
                      ? 'הנקודה שממנה המנווט יוצא וחוזר אליה'
                      : 'נקודות משותפות לכל המנווטים',
                  child: Icon(Icons.info_outline, size: 18, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (isStar) ...[
              // כוכב — נקודה מרכזית אחת
              DropdownButtonFormField<String>(
                value: _startPointId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'נקודה מרכזית *',
                ),
                items: [
                  DropdownMenuItem(
                    value: '__pick_on_map__',
                    child: Row(
                      children: [
                        Icon(Icons.map, size: 18, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('בחר במפה'),
                      ],
                    ),
                  ),
                  ..._checkpoints.map((cp) => DropdownMenuItem(
                    value: cp.id,
                    child: Text(cp.displayLabel),
                  )),
                ],
                validator: (value) {
                  if (value == null) return 'חובה לבחור נקודה מרכזית';
                  return null;
                },
                onChanged: (value) async {
                  if (value == '__pick_on_map__') {
                    final selectedId = await Navigator.push<String>(context,
                      MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                        checkpoints: _checkpoints,
                        boundary: _boundary,
                      )));
                    if (selectedId != null) {
                      setState(() {
                        _startPointId = selectedId;
                        _endPointId = selectedId; // כוכב: התחלה = סיום
                      });
                    }
                    return;
                  }
                  setState(() {
                    _startPointId = value;
                    _endPointId = value; // כוכב: התחלה = סיום
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                'המנווט יוצא מהנקודה המרכזית, הולך לנקודה, וחוזר אליה',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ] else ...[
              // רגיל — נקודת התחלה + סיום (צנחנים: ללא התחלה)
              if (!isParachute) ...[
                DropdownButtonFormField<String>(
                  value: _startPointId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'נקודת התחלה (משותפת) *',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '__pick_on_map__',
                      child: Row(
                        children: [
                          Icon(Icons.map, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('בחר במפה'),
                        ],
                      ),
                    ),
                    ..._checkpoints.map((cp) => DropdownMenuItem(
                      value: cp.id,
                      child: Text(cp.displayLabel),
                    )),
                  ],
                  validator: (value) {
                    if (value == null) return 'חובה לבחור נקודת התחלה';
                    return null;
                  },
                  onChanged: (value) async {
                    if (value == '__pick_on_map__') {
                      final selectedId = await Navigator.push<String>(context,
                        MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                          checkpoints: _checkpoints,
                          boundary: _boundary,
                        )));
                      if (selectedId != null) setState(() => _startPointId = selectedId);
                      return;
                    }
                    setState(() => _startPointId = value);
                  },
                ),
              ],
              const SizedBox(height: 12),

              // נקודת החלפה — רק למאבטח
              if (_forceComposition == 'guard') ...[
                DropdownButtonFormField<String>(
                  value: _swapPointId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'נקודת החלפה *',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '__pick_on_map__',
                      child: Row(
                        children: [
                          Icon(Icons.map, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('בחר במפה'),
                        ],
                      ),
                    ),
                    ..._checkpoints.map((cp) => DropdownMenuItem(
                      value: cp.id,
                      child: Text(cp.displayLabel),
                    )),
                  ],
                  onChanged: (value) async {
                    if (value == '__pick_on_map__') {
                      final selectedId = await Navigator.push<String>(context,
                        MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                          checkpoints: _checkpoints,
                          boundary: _boundary,
                        )));
                      if (selectedId != null) setState(() => _swapPointId = selectedId);
                      return;
                    }
                    setState(() => _swapPointId = value);
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  _swapPointId == null
                      ? 'יש לבחור נקודה כדי לאפשר חלוקה'
                      : 'כל הזוגות יתחלפו בין המנווט למאבטח בנקודה זו',
                  style: TextStyle(
                    fontSize: 12,
                    color: _swapPointId == null ? Colors.orange[700] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // נקודת סיום
              DropdownButtonFormField<String>(
                value: _endPointId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'נקודת סיום (משותפת) *',
                ),
                items: [
                  DropdownMenuItem(
                    value: '__pick_on_map__',
                    child: Row(
                      children: [
                        Icon(Icons.map, size: 18, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('בחר במפה'),
                      ],
                    ),
                  ),
                  ..._checkpoints.map((cp) => DropdownMenuItem(
                    value: cp.id,
                    child: Text(cp.displayLabel),
                  )),
                ],
                validator: (value) {
                  if (value == null) return 'חובה לבחור נקודת סיום';
                  return null;
                },
                onChanged: (value) async {
                  if (value == '__pick_on_map__') {
                    final selectedId = await Navigator.push<String>(context,
                      MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                        checkpoints: _checkpoints,
                        boundary: _boundary,
                      )));
                    if (selectedId != null) setState(() => _endPointId = selectedId);
                    return;
                  }
                  setState(() => _endPointId = value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'נקודות ביניים (נ.צ. משותפות)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Switch(
                  value: _waypointsEnabled,
                  onChanged: (value) {
                    setState(() => _waypointsEnabled = value);
                  },
                ),
              ],
            ),
            if (_waypointsEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'נקודות ציון שכל המנווטים יעברו בהן',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // רשימת נקודות ביניים
              ..._waypoints.asMap().entries.map((entry) {
                final index = entry.key;
                final waypoint = entry.value;
                return _buildWaypointCard(index, waypoint);
              }),

              const SizedBox(height: 12),

              // כפתור הוספת נקודת ביניים
              OutlinedButton.icon(
                onPressed: _addWaypoint,
                icon: const Icon(Icons.add),
                label: const Text('הוסף נקודת ביניים'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointCard(int index, WaypointCheckpoint waypoint) {
    return Card(
      color: Colors.blue[50],
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'נקודת ביניים ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () => _removeWaypoint(index),
                  color: Colors.red,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // בחירת נקודת ציון
            DropdownButtonFormField<String>(
              value: waypoint.checkpointId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר נקודת ציון',
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                DropdownMenuItem(
                  value: '__pick_on_map__',
                  child: Row(
                    children: [
                      Icon(Icons.map, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('בחר במפה'),
                    ],
                  ),
                ),
                ..._checkpoints.map((cp) => DropdownMenuItem(
                  value: cp.id,
                  child: Text(cp.displayLabel),
                )),
              ],
              onChanged: (value) async {
                if (value == '__pick_on_map__') {
                  final selectedId = await Navigator.push<String>(context,
                    MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                      checkpoints: _checkpoints,
                      boundary: _boundary,
                    )));
                  if (selectedId != null) _updateWaypointCheckpoint(index, selectedId);
                  return;
                }
                if (value != null) {
                  _updateWaypointCheckpoint(index, value);
                }
              },
            ),
            const SizedBox(height: 12),

            // סוג מיקום לבניית צירים
            DropdownButtonFormField<String>(
              value: waypoint.placementType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'הגדרות לבניית צירים',
                filled: true,
                fillColor: Colors.white,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'distance',
                  child: Text('לפי מרחק'),
                ),
                DropdownMenuItem(
                  value: 'between_checkpoints',
                  child: Text('בין נקודות ספציפיות'),
                ),
              ],
              onChanged: (value) => _updateWaypointPlacementType(index, value!),
            ),
            const SizedBox(height: 12),

            // שדות לפי סוג
            if (waypoint.placementType == 'distance') ...[
              Text(
                'לעבור בה אחרי ${waypoint.afterDistanceMinKm?.toStringAsFixed(1) ?? "2.0"}-${waypoint.afterDistanceMaxKm?.toStringAsFixed(1) ?? "5.0"} ק"מ',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              RangeSlider(
                min: 0.0,
                max: _maxRouteLength,
                divisions: (_maxRouteLength * 10).toInt().clamp(1, 1000),
                values: RangeValues(
                  (waypoint.afterDistanceMinKm ?? 2.0).clamp(0.0, _maxRouteLength),
                  (waypoint.afterDistanceMaxKm ?? 5.0).clamp(0.0, _maxRouteLength),
                ),
                labels: RangeLabels(
                  (waypoint.afterDistanceMinKm ?? 2.0).toStringAsFixed(1),
                  (waypoint.afterDistanceMaxKm ?? 5.0).toStringAsFixed(1),
                ),
                onChanged: (values) {
                  _updateWaypointDistanceRange(index, values.start, values.end);
                },
              ),
            ] else if (waypoint.placementType == 'between_checkpoints')
              DropdownButtonFormField<int>(
                value: (waypoint.afterCheckpointIndex ?? -1).clamp(-1, _checkpointsPerNavigator - 1),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'מיקום',
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: List.generate(_checkpointsPerNavigator + 1, (i) {
                  final gapIndex = i - 1; // -1..K-1
                  final String label;
                  if (gapIndex == -1) {
                    label = 'בין התחלה לנקודה 1';
                  } else if (gapIndex == _checkpointsPerNavigator - 1) {
                    label = 'בין נקודה $_checkpointsPerNavigator לסיום';
                  } else {
                    label = 'בין נקודה ${gapIndex + 1} לנקודה ${gapIndex + 2}';
                  }
                  return DropdownMenuItem(
                    value: gapIndex,
                    child: Text(label),
                  );
                }),
                onChanged: (value) {
                  if (value != null) {
                    _updateWaypointGap(index, value);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _addWaypoint() {
    if (_checkpoints.isEmpty) return;
    setState(() {
      _waypoints.add(WaypointCheckpoint(
        checkpointId: _checkpoints.first.id,
        placementType: 'distance',
        afterDistanceMinKm: 2.0,
        afterDistanceMaxKm: 5.0,
      ));
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
    });
  }

  void _updateWaypointCheckpoint(int index, String checkpointId) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(checkpointId: checkpointId);
    });
  }

  void _updateWaypointPlacementType(int index, String type) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = WaypointCheckpoint(
        checkpointId: current.checkpointId,
        placementType: type,
        afterDistanceMinKm: type == 'distance' ? (current.afterDistanceMinKm ?? 2.0) : null,
        afterDistanceMaxKm: type == 'distance' ? (current.afterDistanceMaxKm ?? 5.0) : null,
        afterCheckpointIndex: type == 'between_checkpoints' ? (current.afterCheckpointIndex ?? -1) : null,
      );
    });
  }

  void _updateWaypointDistanceRange(int index, double minKm, double maxKm) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(
        afterDistanceMinKm: minKm,
        afterDistanceMaxKm: maxKm,
      );
    });
  }

  void _updateWaypointGap(int index, int gapIndex) {
    setState(() {
      final current = _waypoints[index];
      _waypoints[index] = current.copyWith(afterCheckpointIndex: gapIndex);
    });
  }

  void _autoAssignGroups() {
    final baseSize = ForceComposition(type: _forceComposition).baseGroupSize;
    final groups = RoutesDistributionService.autoGroupNavigators(
      navigators: _navigatorsList,
      baseGroupSize: baseSize,
      compositionType: _forceComposition,
    );
    setState(() => _manualGroups = groups);
  }

  Widget _buildForceCompositionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'הרכב הכוח',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _forceComposition,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'בחר הרכב',
              ),
              items: [
                const DropdownMenuItem(value: 'solo', child: Text('בדד')),
                if (_navigationType != 'star' && _navigationType != 'clusters' && _navigationType != 'clusters_reverse' && _navigationType != 'parachute')
                  const DropdownMenuItem(value: 'guard', child: Text('מאבטח')),
                const DropdownMenuItem(value: 'pair', child: Text('צמד')),
                const DropdownMenuItem(value: 'squad', child: Text('חוליה')),
              ],
              onChanged: (value) {
                setState(() {
                  _forceComposition = value!;
                  _manualGroups = {};
                  if (value != 'guard') _swapPointId = null;
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              switch (_forceComposition) {
                'solo' => 'כל מנווט מקבל ציר עצמאי',
                'guard' => 'זוגות מנווטים — כל אחד מקבל חצי ציר עם נקודת החלפה',
                'pair' => 'צמדי מנווטים — כל צמד מקבל ציר משותף',
                'squad' => 'חוליות של 4 מנווטים — כל חוליה מקבלת ציר משותף',
                _ => '',
              },
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildGroupsSection() {
    final baseSize = ForceComposition(type: _forceComposition).baseGroupSize;
    final compositionLabel = switch (_forceComposition) {
      'guard' => 'זוג',
      'pair' => 'צמד',
      'squad' => 'חוליה',
      _ => 'קבוצה',
    };
    final compositionLabelPlural = switch (_forceComposition) {
      'guard' => 'זוגות',
      'pair' => 'צמדים',
      'squad' => 'חוליות',
      _ => 'קבוצות',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'שיבוץ $compositionLabelPlural',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _autoAssignGroups,
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: Text(_manualGroups.isEmpty ? 'שיבוץ אוטומטי' : 'ערבב מחדש'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_navigatorsList.length} מנווטים, גודל בסיס: $baseSize',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),

            if (_manualGroups.isEmpty) ...[
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'לחץ "שיבוץ אוטומטי" או שהחלוקה תבוצע אוטומטית',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              ..._manualGroups.entries.toList().asMap().entries.map((entry) {
                final groupIndex = entry.key;
                final groupId = entry.value.key;
                final members = entry.value.value;
                final sizeLabel = members.length == 1
                    ? ' (בדד)'
                    : members.length == 3 && baseSize == 2
                        ? ' (שלישייה)'
                        : members.length != baseSize
                            ? ' (${members.length} חברים)'
                            : '';

                return Card(
                  color: Colors.blue[50],
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$compositionLabel ${groupIndex + 1}$sizeLabel',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...members.asMap().entries.map((memberEntry) {
                          final memberId = memberEntry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.person, size: 18, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                Expanded(child: Text(memberId, style: const TextStyle(fontSize: 13))),
                                // Dropdown לשינוי קבוצה
                                DropdownButton<String>(
                                  value: groupId,
                                  underline: const SizedBox(),
                                  isDense: true,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                  items: [
                                    ..._manualGroups.keys.toList().asMap().entries.map((gEntry) {
                                      final targetSize = _manualGroups[gEntry.value]!.length;
                                      final maxSize = ForceComposition(type: _forceComposition).maxGroupSize;
                                      final isFull = targetSize >= maxSize;
                                      return DropdownMenuItem(
                                        value: gEntry.value,
                                        enabled: !isFull || gEntry.value == groupId,
                                        child: Text(
                                          '$compositionLabel ${gEntry.key + 1}${isFull && gEntry.value != groupId ? " (מלא)" : ""}',
                                          style: isFull && gEntry.value != groupId
                                              ? TextStyle(color: Colors.grey[400])
                                              : null,
                                        ),
                                      );
                                    }),
                                    DropdownMenuItem(
                                      value: '__new_group__',
                                      child: Text('+ $compositionLabel חדש'),
                                    ),
                                  ],
                                  onChanged: (newGroupId) {
                                    if (newGroupId == null || newGroupId == groupId) return;
                                    setState(() {
                                      _manualGroups[groupId]!.remove(memberId);
                                      if (newGroupId == '__new_group__') {
                                        final newId = 'group_${DateTime.now().millisecondsSinceEpoch}';
                                        _manualGroups[newId] = [memberId];
                                      } else {
                                        _manualGroups[newGroupId]!.add(memberId);
                                      }
                                      _manualGroups.removeWhere((_, v) => v.isEmpty);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropPointsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'נקודות הצנחה',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'בחר נקודות ציון שישמשו כנקודות הצנחה (התחלה) למנווטים',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            // רשימת נקודות ציון כ-chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _checkpoints.map((cp) {
                final isSelected = _dropPointIds.contains(cp.id);
                return FilterChip(
                  label: Text(cp.displayLabel),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _dropPointIds.add(cp.id);
                      } else {
                        _dropPointIds.remove(cp.id);
                      }
                    });
                  },
                  selectedColor: Colors.orange[100],
                  checkmarkColor: Colors.orange[800],
                );
              }).toList(),
            ),
            if (_dropPointIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_dropPointIds.length} נקודות הצנחה נבחרו',
                style: TextStyle(fontSize: 12, color: Colors.orange[700]),
              ),
            ],
            const Divider(height: 24),
            // שיטת שיבוץ
            const Text(
              'שיטת שיבוץ לנקודות הצנחה',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _parachuteAssignmentMethod,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'שיטת שיבוץ',
              ),
              items: const [
                DropdownMenuItem(value: 'random', child: Text('אקראי')),
                DropdownMenuItem(value: 'manual', child: Text('ידני')),
                DropdownMenuItem(value: 'by_sub_framework', child: Text('לפי תת-מסגרת')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _parachuteAssignmentMethod = value);
                }
              },
            ),
            if (_parachuteAssignmentMethod == 'by_sub_framework') ...[
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('אותה נקודה לכל מנווטי תת-מסגרת'),
                value: _samePointPerSubFramework,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _samePointPerSubFramework = v),
              ),
            ],
            const Divider(height: 24),
            // מצב מסלול
            const Text(
              'מצב מסלול',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _routeMode,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'מצב מסלול',
              ),
              items: const [
                DropdownMenuItem(value: 'checkpoints', child: Text('נקודות ציון')),
                DropdownMenuItem(value: 'clusters', child: Text('אשכולות')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _routeMode = value);
                }
              },
            ),
            const SizedBox(height: 4),
            Text(
              _routeMode == 'clusters'
                  ? 'כל נקודה תוקף באשכול נקודות מטעות'
                  : 'נקודות ציון רגילות ללא נקודות מטעות',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClustersSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'הגדרות אשכולות',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'כל נקודה אמיתית מוקפת בנקודות מטעות — המנווט לא יודע איזו הנקודה שלו',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // מספר נקודות באשכול
            Row(
              children: [
                const Expanded(child: Text('מספר נקודות באשכול')),
                Text('$_clusterSize', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _clusterSize.toDouble(),
              min: 2,
              max: 8,
              divisions: 6,
              label: '$_clusterSize',
              onChanged: (v) => setState(() => _clusterSize = v.round()),
            ),
            Text(
              'כולל הנקודה האמיתית + ${_clusterSize - 1} נקודות מטעות',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            // רדיוס אשכול
            Row(
              children: [
                const Expanded(child: Text('רדיוס אשכול (מטרים)')),
                Text('$_clusterSpreadMeters', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _clusterSpreadMeters.toDouble(),
              min: 50,
              max: 6000,
              divisions: 119,
              label: '$_clusterSpreadMeters מ\'',
              onChanged: (v) => setState(() => _clusterSpreadMeters = (v / 50).round() * 50),
            ),
            Text(
              'נקודות מטעות ייבחרו מתוך נ"צ בטווח הרדיוס',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const Divider(height: 24),
            // חשיפת נקודות
            SwitchListTile(
              title: const Text('חשיפת נקודות אמיתיות'),
              subtitle: const Text('אפשר למנווטים לראות את הנקודה האמיתית לאחר זמן מוגדר'),
              value: _revealEnabled,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _revealEnabled = v),
            ),
            if (_revealEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('חשיפה אחרי (דקות)')),
                  Text('$_revealAfterMinutes', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _revealAfterMinutes.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '$_revealAfterMinutes דקות',
                onChanged: (v) => setState(() => _revealAfterMinutes = (v / 5).round() * 5),
              ),
              Text(
                'הנקודות האמיתיות ייחשפו $_revealAfterMinutes דקות אחרי תחילת הניווט',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
