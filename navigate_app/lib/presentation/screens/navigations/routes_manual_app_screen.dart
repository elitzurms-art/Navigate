import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_settings.dart';
import '../../../domain/entities/checkpoint.dart';
import '../../../domain/entities/coordinate.dart';
import '../../../domain/entities/nav_layer.dart';
import '../../../domain/entities/user.dart';
import '../../../data/repositories/nav_layer_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/navigation_tree_repository.dart';
import '../../../data/repositories/checkpoint_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../services/navigation_layer_copy_service.dart';
import '../../../services/routes_distribution_service.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../widgets/map_with_selector.dart';
import '../../widgets/fullscreen_map_screen.dart';
import '../../widgets/map_controls.dart';
import '../../../core/map_config.dart';
import 'checkpoint_map_picker_screen.dart';
import 'routes_verification_screen.dart';

/// מסך חלוקה ידנית באפליקציה
class RoutesManualAppScreen extends StatefulWidget {
  final domain.Navigation navigation;

  const RoutesManualAppScreen({super.key, required this.navigation});

  @override
  State<RoutesManualAppScreen> createState() => _RoutesManualAppScreenState();
}

class _RoutesManualAppScreenState extends State<RoutesManualAppScreen> {
  final NavLayerRepository _navLayerRepo = NavLayerRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final NavigationTreeRepository _treeRepo = NavigationTreeRepository();
  final CheckpointRepository _checkpointRepo = CheckpointRepository();
  final NavigationLayerCopyService _layerCopyService = NavigationLayerCopyService();
  final MapController _mapController = MapController();
  final UserRepository _userRepo = UserRepository();

  // Data
  List<Checkpoint> _checkpoints = [];
  List<NavBoundary> _boundaries = [];
  List<String> _navigatorIds = [];
  Map<String, User> _usersCache = {};

  // Shared points
  String? _startPointId;
  String? _endPointId;
  List<String> _intermediatePointIds = [];

  // Per-navigator assignments: uid → [checkpointIds in order]
  Map<String, List<String>> _navigatorCheckpoints = {};

  // סוג ניווט והגדרות
  String _navigationType = 'regular';
  String _executionOrder = 'sequential';
  String _scoringCriterion = 'fairness';

  // הרכב הכוח
  String _forceComposition = 'solo';
  String? _swapPointId;
  Map<String, List<String>> _manualGroups = {};

  // כוכב
  int _starLearningMinutes = 5;
  int _starNavigatingMinutes = 15;
  bool _starAutoMode = false;

  // אשכולות
  int _clusterSize = 3;
  int _clusterSpreadMeters = 200;
  String _clusterDecoyMode = 'automatic'; // 'automatic' or 'manual'
  // אשכולות ידניים: uid → set של checkpoint IDs שסומנו כנקודות הסחה
  Map<String, Set<String>> _navigatorDecoyPoints = {};

  // צנחנים
  List<String> _dropPointIds = [];
  String _parachuteAssignmentMethod = 'random';
  Map<String, String> _navigatorDropPoints = {};
  Map<String, List<String>> _subFrameworkDropPoints = {};
  bool _samePointPerSubFramework = false;
  String _routeMode = 'checkpoints';

  // UI state
  String? _expandedNavigatorId;
  bool _isLoading = true;
  bool _isSaving = false;
  // סינון מנווטים במפה
  Set<String> _mapVisibleNavigatorIds = {};

  @override
  void initState() {
    super.initState();
    _initFromNavigation();
    _loadData();
  }

  void _initFromNavigation() {
    final nav = widget.navigation;
    final knownTypes = {'regular', 'star', 'reverse', 'parachute', 'clusters', 'clusters_reverse'};
    _navigationType = knownTypes.contains(nav.navigationType) ? nav.navigationType! : 'regular';
    _executionOrder = nav.executionOrder ?? 'sequential';
    _scoringCriterion = nav.scoringCriterion ?? 'fairness';
    // composition
    _forceComposition = nav.forceComposition.type;
    _swapPointId = nav.forceComposition.swapPointId;
    _manualGroups = Map.from(nav.forceComposition.manualGroups.map(
      (k, v) => MapEntry(k, List<String>.from(v)),
    ));
    // star
    _starLearningMinutes = nav.starLearningMinutes ?? 5;
    _starNavigatingMinutes = nav.starNavigatingMinutes ?? 15;
    _starAutoMode = nav.starAutoMode;
    // clusters
    _clusterSize = nav.clusterSettings.clusterSize;
    _clusterSpreadMeters = nav.clusterSettings.clusterSpreadMeters;
    // parachute
    if (nav.parachuteSettings != null) {
      final ps = nav.parachuteSettings!;
      _dropPointIds = List.from(ps.dropPointIds);
      _parachuteAssignmentMethod = ps.assignmentMethod;
      _navigatorDropPoints = Map.from(ps.navigatorDropPoints);
      _subFrameworkDropPoints = ps.subFrameworkDropPoints.map((k, v) => MapEntry(k, List<String>.from(v)));
      _samePointPerSubFramework = ps.samePointPerSubFramework;
      _routeMode = ps.routeMode;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // טעינת נקודות ציון (אותה לוגיקה כמו routes_automatic_setup_screen)
      var navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
        widget.navigation.id,
      );

      if (navCheckpoints.isEmpty) {
        await _layerCopyService.copyLayersForNavigation(
          navigationId: widget.navigation.id,
          boundaryIds: widget.navigation.boundaryLayerIds,
          areaId: widget.navigation.areaId,
          createdBy: '',
        );
        navCheckpoints = await _navLayerRepo.getCheckpointsByNavigation(
          widget.navigation.id,
        );
      }

      List<Checkpoint> checkpoints;
      if (navCheckpoints.isEmpty) {
        checkpoints = await _checkpointRepo.getByArea(widget.navigation.areaId);
      } else {
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

      // זיהוי מנווטים — מנווטים בלבד (ללא מפקדים/מנהלים)
      List<String> navigators = [];
      if (widget.navigation.selectedParticipantIds.isNotEmpty) {
        // סינון לפי תפקיד — רק מנווטים מקבלים צירים
        for (final uid in widget.navigation.selectedParticipantIds) {
          final user = await _userRepo.getUser(uid);
          if (user != null && user.role == 'navigator') {
            navigators.add(uid);
          }
        }
      } else {
        final unitId = widget.navigation.selectedUnitId ?? tree?.unitId;
        if (unitId != null) {
          if (tree != null && widget.navigation.selectedSubFrameworkIds.isNotEmpty) {
            final navigatorSet = <String>{};
            for (final sf in tree.subFrameworks) {
              if (!widget.navigation.selectedSubFrameworkIds.contains(sf.id)) continue;
              // דילוג על תת-מסגרות קבועות (מפקדים/מנהלת)
              if (sf.isFixed) continue;
              // שימוש ב-userIds של התת-מסגרת
              if (sf.userIds.isNotEmpty) {
                for (final uid in sf.userIds) {
                  final user = await _userRepo.getUser(uid);
                  if (user != null && user.role == 'navigator') {
                    navigatorSet.add(uid);
                  }
                }
              } else {
                final users = await _userRepo.getNavigatorsForUnit(unitId);
                navigatorSet.addAll(users.map((u) => u.uid));
              }
            }
            navigators = navigatorSet.toList();
          } else {
            final users = await _userRepo.getNavigatorsForUnit(unitId);
            navigators = users.map((u) => u.uid).toList();
          }
        }
      }

      // טעינת פרטי משתמשים
      final usersCache = <String, User>{};
      for (final uid in navigators) {
        final user = await _userRepo.getUser(uid);
        if (user != null) {
          usersCache[uid] = user;
        }
      }

      // אתחול מפות הקצאה ריקות
      final navigatorCheckpoints = <String, List<String>>{};
      for (final uid in navigators) {
        navigatorCheckpoints[uid] = [];
      }

      // אתחול מהגדרות קיימות (אם יש)
      String? startPointId = widget.navigation.startPoint;
      String? endPointId = widget.navigation.endPoint;
      List<String> intermediatePointIds = [];
      if (widget.navigation.waypointSettings.enabled) {
        intermediatePointIds = widget.navigation.waypointSettings.waypoints
            .map((w) => w.checkpointId)
            .toList();
      }

      // אם יש צירים קיימים — טעינה חזרה
      if (widget.navigation.routes.isNotEmpty) {
        for (final entry in widget.navigation.routes.entries) {
          if (navigatorCheckpoints.containsKey(entry.key)) {
            navigatorCheckpoints[entry.key] = List.from(entry.value.checkpointIds);
            startPointId ??= entry.value.startPointId;
            endPointId ??= entry.value.endPointId;
            if (entry.value.waypointIds.isNotEmpty && intermediatePointIds.isEmpty) {
              intermediatePointIds = List.from(entry.value.waypointIds);
            }
          }
        }
      }

      // טעינת גבולות ניווט (לשימוש במפה ובמפת בחירת נקודות)
      final navBoundaries = await _navLayerRepo.getBoundariesByNavigation(widget.navigation.id);

      setState(() {
        _checkpoints = checkpoints;
        _boundaries = navBoundaries;
        _navigatorIds = navigators;
        _usersCache = usersCache;
        _navigatorCheckpoints = navigatorCheckpoints;
        _startPointId = startPointId;
        _endPointId = endPointId;
        _intermediatePointIds = intermediatePointIds;
        _mapVisibleNavigatorIds = navigators.toSet();
        // אתחול מפת הסחה ריקה לכל מנווט
        for (final uid in navigators) {
          _navigatorDecoyPoints.putIfAbsent(uid, () => {});
        }
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

  /// האם במצב אשכולות ידני
  bool get _isManualClusterMode =>
      (_navigationType == 'clusters' || _navigationType == 'clusters_reverse' ||
          (_navigationType == 'parachute' && _routeMode == 'clusters')) &&
      _clusterDecoyMode == 'manual';

  Checkpoint? _getCheckpoint(String id) {
    try {
      return _checkpoints.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  String _getNavigatorName(String uid) {
    final user = _usersCache[uid];
    if (user != null && user.fullName.isNotEmpty) return user.fullName;
    return uid;
  }

  /// אופטימיזציית nearest-neighbor על נקודות המנווט
  /// מסדרת את הנקודות לפי שכן קרוב ביותר, החל מנקודת ההתחלה
  List<String> _optimizeByNearestNeighbor(List<String> cpIds) {
    if (cpIds.length <= 1) return List.from(cpIds);

    // בניית מפת קואורדינטות
    final coordMap = <String, Coordinate>{};
    for (final id in cpIds) {
      final cp = _getCheckpoint(id);
      if (cp?.coordinates != null) {
        coordMap[id] = cp!.coordinates!;
      }
    }
    // אם אין קואורדינטות — מחזיר כמות שהוא
    if (coordMap.isEmpty) return List.from(cpIds);

    final remaining = List<String>.from(cpIds);
    final result = <String>[];

    // מציאת נקודת ההתחלה הקרובה ביותר ל-startPoint (או ראשונה)
    String current;
    if (_startPointId != null) {
      final startCp = _getCheckpoint(_startPointId!);
      if (startCp?.coordinates != null) {
        double bestDist = double.infinity;
        int bestIdx = 0;
        for (int i = 0; i < remaining.length; i++) {
          final coord = coordMap[remaining[i]];
          if (coord == null) continue;
          final d = GeometryUtils.distanceBetweenMeters(startCp!.coordinates!, coord);
          if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
          }
        }
        current = remaining.removeAt(bestIdx);
      } else {
        current = remaining.removeAt(0);
      }
    } else {
      current = remaining.removeAt(0);
    }
    result.add(current);

    // שלב NN: בכל פעם בוחרים את הנקודה הקרובה ביותר לנוכחית
    while (remaining.isNotEmpty) {
      final currentCoord = coordMap[current];
      if (currentCoord == null) {
        result.add(remaining.removeAt(0));
        if (result.isNotEmpty) current = result.last;
        continue;
      }
      double bestDist = double.infinity;
      int bestIdx = 0;
      for (int i = 0; i < remaining.length; i++) {
        final coord = coordMap[remaining[i]];
        if (coord == null) continue;
        final d = GeometryUtils.distanceBetweenMeters(currentCoord, coord);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      current = remaining.removeAt(bestIdx);
      result.add(current);
    }

    return result;
  }

  /// בניית רצף סופי: התחלה → [רשימת המנווט כמו שהוא סידר] → סיום
  /// נקודות הביניים כבר נמצאות ברשימת המנווט (הוכנסו אוטומטית) — הוא מסדר הכל ידנית
  List<String> _buildFullSequence(List<String> navigatorCps) {
    if (navigatorCps.isEmpty) return [];
    final result = <String>[];
    if (_startPointId != null) result.add(_startPointId!);
    result.addAll(navigatorCps);
    if (_endPointId != null) result.add(_endPointId!);
    return result;
  }

  /// הוספת נקודות ביניים חובה לכל המנווטים (שעדיין אין להם)
  void _syncIntermediateToAll() {
    for (final uid in _navigatorIds) {
      final cps = _navigatorCheckpoints[uid] ?? [];
      for (final ipId in _intermediatePointIds) {
        if (!cps.contains(ipId)) {
          cps.add(ipId);
        }
      }
    }
  }

  /// הסרת נקודת ביניים מכל המנווטים
  void _removeIntermediateFromAll(String cpId) {
    for (final uid in _navigatorIds) {
      _navigatorCheckpoints[uid]?.remove(cpId);
    }
  }

  /// חישוב אורך ציר בק"מ
  double _calculateRouteLength(List<String> sequence) {
    final coords = <Coordinate>[];
    for (final cpId in sequence) {
      final cp = _getCheckpoint(cpId);
      if (cp?.coordinates != null) {
        coords.add(cp!.coordinates!);
      }
    }
    return GeometryUtils.calculatePathLengthKm(coords);
  }

  /// קביעת סטטוס ציר לפי טווח אורך
  String _getRouteStatus(double lengthKm) {
    final range = widget.navigation.routeLengthKm;
    if (range == null) return 'optimal';
    if (lengthKm < range.min) return 'too_short';
    if (lengthKm > range.max) return 'too_long';
    return 'optimal';
  }

  /// ספירת כמה מנווטים קיבלו נקודה מסוימת
  /// [currentNavigatorId] — המנווט שנמצא כרגע ב-bottom sheet (מדלגים על הרשומה הישנה שלו)
  /// [currentSelected] — הבחירות הנוכחיות של אותו מנווט ב-bottom sheet
  int _getCheckpointAssignmentCount(String checkpointId, {String? currentNavigatorId, Set<String>? currentSelected}) {
    int count = 0;
    for (final entry in _navigatorCheckpoints.entries) {
      if (entry.key == currentNavigatorId) continue; // דילוג על הנתון הישן
      if (entry.value.contains(checkpointId)) count++;
    }
    // הוספת הבחירה הנוכחית של המנווט הפעיל
    if (currentSelected != null && currentSelected.contains(checkpointId)) count++;
    return count;
  }

  // ===================== BOTTOM SHEET — בחירת נקודות למנווט =====================

  void _showCheckpointSelector(String navigatorId) {
    final selected = Set<String>.from(_navigatorCheckpoints[navigatorId] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // סינון נקודות: לא כולל התחלה/סיום/ביניים
            final excludedIds = <String>{
              if (_startPointId != null) _startPointId!,
              if (_endPointId != null) _endPointId!,
              ..._intermediatePointIds,
            };
            final availableCheckpoints = _checkpoints
                .where((c) => !excludedIds.contains(c.id))
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'בחירת נקודות — ${_getNavigatorName(navigatorId)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${selected.length} נבחרו',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _navigatorCheckpoints[navigatorId] =
                                    selected.toList();
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('אישור'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Checkpoint list
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: availableCheckpoints.length,
                        itemBuilder: (_, index) {
                          final cp = availableCheckpoints[index];
                          final isSelected = selected.contains(cp.id);
                          final assignCount = _getCheckpointAssignmentCount(cp.id, currentNavigatorId: navigatorId, currentSelected: selected);

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setSheetState(() {
                                if (val == true) {
                                  selected.add(cp.id);
                                } else {
                                  selected.remove(cp.id);
                                }
                              });
                            },
                            title: Text(
                              cp.displayLabel,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: assignCount > 0
                                ? Text(
                                    '$assignCount מנווטים קיבלו',
                                    style: TextStyle(
                                      color: Colors.orange[700],
                                      fontSize: 12,
                                    ),
                                  )
                                : cp.description.isNotEmpty
                                    ? Text(
                                        cp.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                            secondary: assignCount > 0
                                ? CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.orange[100],
                                    child: Text(
                                      '$assignCount',
                                      style: TextStyle(
                                        color: Colors.orange[800],
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ===================== MAP PREVIEW =====================

  List<Marker> _buildMarkers({String? navigatorId, Set<String>? visibleNavigators}) {
    final markers = <Marker>[];
    final effectiveVisible = visibleNavigators ?? _mapVisibleNavigatorIds;

    // אסוף את כל הנקודות של המנווטים הנראים
    final visibleSequenceSet = <String>{};
    for (final uid in _navigatorIds) {
      if (!effectiveVisible.contains(uid)) continue;
      final cps = _navigatorCheckpoints[uid] ?? [];
      visibleSequenceSet.addAll(cps);
      // הוסף גם התחלה/סיום
      if (_startPointId != null) visibleSequenceSet.add(_startPointId!);
      if (_endPointId != null) visibleSequenceSet.add(_endPointId!);
    }

    // אם יש מנווט ספציפי (מפה מוטמעת), הציג רק אותו + מנווטים נראים
    final focusSequence = navigatorId != null
        ? _buildFullSequence(_navigatorCheckpoints[navigatorId] ?? []).toSet()
        : null;

    // מזהי נקודות החלפה (מאבטח)
    final swapIds = <String>{};
    if (_swapPointId != null) swapIds.add(_swapPointId!);
    for (final r in widget.navigation.routes.values) {
      if (r.swapPointId != null) swapIds.add(r.swapPointId!);
    }

    // אשכולות ידני: אסוף את כל נקודות ההסחה של המנווטים הנראים
    final allVisibleDecoys = <String>{};
    final allVisibleReal = <String>{};
    if (_isManualClusterMode) {
      for (final uid in _navigatorIds) {
        if (!effectiveVisible.contains(uid)) continue;
        final cps = _navigatorCheckpoints[uid] ?? [];
        final decoys = _navigatorDecoyPoints[uid] ?? {};
        for (final cpId in cps) {
          if (decoys.contains(cpId)) {
            allVisibleDecoys.add(cpId);
          } else {
            allVisibleReal.add(cpId);
          }
        }
      }
    }

    for (final cp in _checkpoints) {
      if (cp.coordinates == null) continue;
      final isSwapPoint = swapIds.contains(cp.id);
      final isStart = cp.id == _startPointId;
      final isEnd = cp.id == _endPointId && !isSwapPoint;
      final isIntermediate = _intermediatePointIds.contains(cp.id);
      final isInVisibleSequence = visibleSequenceSet.contains(cp.id);
      final isInFocusSequence = focusSequence?.contains(cp.id) ?? false;

      // סטנדרט H/F/S/B כמו בשאר האפליקציה — נקודות מיוחדות תמיד בצבע שלהן
      Color bgColor;
      String letter;
      Color borderColor = Colors.white;
      Color textColor = Colors.white;

      if (isSwapPoint) {
        bgColor = Colors.white;
        borderColor = Colors.grey[700]!;
        textColor = Colors.grey[800]!;
        letter = 'S';
      } else if (isStart) {
        bgColor = const Color(0xFF4CAF50);
        letter = _navigationType == 'star' ? '*' : 'H';
      } else if (isEnd) {
        bgColor = const Color(0xFFF44336);
        letter = 'F';
      } else if (isIntermediate) {
        bgColor = const Color(0xFFFFC107);
        letter = 'B';
      } else if (_isManualClusterMode) {
        // אשכולות ידני: הסחה=כחול, אמת=סגול, לא נבחר=אפור
        if (allVisibleDecoys.contains(cp.id)) {
          bgColor = Colors.blue;
          letter = '';
        } else if (allVisibleReal.contains(cp.id)) {
          bgColor = Colors.deepPurple;
          letter = '';
        } else {
          bgColor = Colors.grey;
          letter = '';
        }
      } else if (navigatorId != null) {
        bgColor = isInFocusSequence ? Colors.blue : Colors.grey;
        letter = '';
      } else {
        bgColor = isInVisibleSequence ? Colors.blue : Colors.grey;
        letter = '';
      }

      final label = letter.isNotEmpty
          ? '${cp.sequenceNumber}$letter'
          : '${cp.sequenceNumber}';

      markers.add(Marker(
        point: cp.coordinates!.toLatLng(),
        width: 38,
        height: 38,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  // צבעים לצירים — ללא אדום (אדום שמור למנווט הנבחר)
  static const _nonRedRouteColors = [
    Color(0xFF2196F3), // כחול
    Color(0xFF4CAF50), // ירוק
    Color(0xFF9C27B0), // סגול
    Color(0xFFFF9800), // כתום
    Color(0xFF00BCD4), // תכלת
    Color(0xFF795548), // חום
    Color(0xFF3F51B5), // אינדיגו
    Color(0xFF009688), // טורקיז
    Color(0xFF8BC34A), // ירוק בהיר
    Color(0xFFE91E63), // ורוד
  ];

  List<Polyline> _buildPolylines({String? selectedNavigatorId, Set<String>? visibleNavigators}) {
    final polylines = <Polyline>[];
    int colorIdx = 0;
    final effectiveVisible = visibleNavigators ?? _mapVisibleNavigatorIds;

    for (final uid in _navigatorIds) {
      if (!effectiveVisible.contains(uid)) continue;
      final cps = _navigatorCheckpoints[uid] ?? [];
      if (cps.isEmpty) continue;

      final isSelected = uid == selectedNavigatorId;
      final color = isSelected
          ? Colors.red
          : _nonRedRouteColors[colorIdx % _nonRedRouteColors.length].withValues(alpha: 0.6);
      final strokeWidth = isSelected ? 4.0 : 2.5;

      if (_navigationType == 'star' && _startPointId != null) {
        // כוכב: קו מהמרכז לכל נקודה וחזרה
        final centerCp = _getCheckpoint(_startPointId!);
        if (centerCp?.coordinates == null) continue;
        final centerPoint = centerCp!.coordinates!.toLatLng();

        for (final cpId in cps) {
          if (cpId == _startPointId) continue; // דילוג על הנקודה המרכזית עצמה
          final cp = _getCheckpoint(cpId);
          if (cp?.coordinates == null) continue;
          final cpPoint = cp!.coordinates!.toLatLng();
          polylines.add(Polyline(
            points: [centerPoint, cpPoint],
            color: color,
            strokeWidth: strokeWidth,
          ));
        }
      } else {
        // ציר רגיל: רצף רציף
        final seq = _buildFullSequence(cps);
        final points = <LatLng>[];
        for (final cpId in seq) {
          final cp = _getCheckpoint(cpId);
          if (cp?.coordinates != null) {
            points.add(cp!.coordinates!.toLatLng());
          }
        }
        if (points.length < 2) continue;

        polylines.add(Polyline(
          points: points,
          color: color,
          strokeWidth: strokeWidth,
        ));
      }

      if (!isSelected) colorIdx++;
    }
    return polylines;
  }

  LatLngBounds? _getMapBounds() {
    final allCoords = <LatLng>[];

    // גבולות ניווט (עדיפות למרכוז ראשוני)
    for (final b in _boundaries) {
      allCoords.addAll(b.allCoordinates.map((c) => c.toLatLng()));
    }

    // נקודות ציון
    allCoords.addAll(
      _checkpoints
          .where((c) => c.coordinates != null)
          .map((c) => c.coordinates!.toLatLng()),
    );

    if (allCoords.isEmpty) return null;
    return LatLngBounds.fromPoints(allCoords);
  }

  // ===================== SAVE =====================

  Future<void> _saveAndContinue() async {
    // Validation per navigation type
    if (_navigationType == 'star') {
      if (_startPointId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('חובה לבחור נקודה מרכזית'), backgroundColor: Colors.red),
        );
        return;
      }
      _endPointId = _startPointId;
    } else if (_navigationType == 'parachute') {
      if (_endPointId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('חובה לבחור נקודת סיום'), backgroundColor: Colors.red),
        );
        return;
      }
    } else {
      if (_startPointId == null || _endPointId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('יש לבחור נקודת התחלה ונקודת סיום')),
        );
        return;
      }
      if (_forceComposition == 'guard' && _swapPointId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('יש לבחור נקודת החלפה'), backgroundColor: Colors.red),
        );
        return;
      }
    }

    // בדיקה אם יש מנווטים ללא חלוקה (נקודות חובה בלבד לא נחשבות)
    final mandatorySet = _intermediatePointIds.toSet();
    final unassigned = _navigatorIds
        .where((uid) {
          final cps = _navigatorCheckpoints[uid] ?? [];
          final manualCount = cps.where((c) => !mandatorySet.contains(c)).length;
          return manualCount == 0;
        })
        .toList();

    if (unassigned.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('מנווטים ללא חלוקה'),
          content: Text(
            '${unassigned.length} מנווטים עדיין לא קיבלו נקודות.\n'
            'האם להמשיך בכל זאת?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('חזור'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('המשך'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isSaving = true);

    try {
      // בניית routes map
      final routes = <String, domain.AssignedRoute>{};

      final mandatorySet = _intermediatePointIds.toSet();
      for (final uid in _navigatorIds) {
        final cps = _navigatorCheckpoints[uid] ?? [];
        // רק נקודות שנבחרו ידנית (לא כולל חובה)
        final manualCps = cps.where((c) => !mandatorySet.contains(c)).toList();
        if (manualCps.isEmpty) continue;

        // אופטימיזציית NN — מיון נקודות לפי שכן קרוב לפני בניית sequence
        final optimizedCps = _optimizeByNearestNeighbor(cps);
        final sequence = _buildFullSequence(optimizedCps);
        final lengthKm = _calculateRouteLength(sequence);
        final status = _getRouteStatus(lengthKm);

        routes[uid] = domain.AssignedRoute(
          checkpointIds: manualCps,
          routeLengthKm: lengthKm,
          sequence: sequence,
          startPointId: _startPointId,
          endPointId: _endPointId,
          waypointIds: _intermediatePointIds,
          status: status,
        );
      }

      // עדכון ניווט
      final updatedNavigation = widget.navigation.copyWith(
        routes: routes,
        routesStage: 'verification',
        routesDistributed: true,
        startPoint: _startPointId,
        endPoint: _endPointId,
        navigationType: _navigationType,
        executionOrder: _executionOrder,
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
            ? widget.navigation.clusterSettings.copyWith(
                clusterSize: _clusterSize,
                clusterSpreadMeters: _clusterSpreadMeters,
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

      await _navRepo.update(updatedNavigation);

      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                RoutesVerificationScreen(navigation: updatedNavigation),
          ),
        );
        if (result == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('חלוקה ידנית'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _checkpoints.isEmpty
              ? const Center(child: Text('לא נמצאו נקודות ציון'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- הגדרות חלוקה ---
                      _buildNavigationTypeSection(),
                      const SizedBox(height: 16),

                      _buildForceCompositionSection(),
                      const SizedBox(height: 16),

                      if (_forceComposition != 'solo') ...[
                        _buildGroupsSection(),
                        const SizedBox(height: 16),
                      ],

                      if (_navigationType == 'parachute') ...[
                        _buildDropPointsSection(),
                        const SizedBox(height: 16),
                      ],

                      if (_navigationType != 'star') ...[
                        _buildExecutionOrderSection(),
                        const SizedBox(height: 16),
                      ],

                      if (_navigationType == 'star') ...[
                        _buildStarTimeSection(),
                        const SizedBox(height: 16),
                      ],

                      if (_navigationType == 'clusters' || _navigationType == 'clusters_reverse' ||
                          (_navigationType == 'parachute' && _routeMode == 'clusters')) ...[
                        _buildClustersSection(),
                        const SizedBox(height: 16),
                      ],

                      // --- נקודות משותפות ומנווטים ---
                      _buildSharedPointsSection(),
                      const SizedBox(height: 16),
                      _buildNavigatorsSection(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      bottomNavigationBar: _isLoading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveAndContinue,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'שומר...' : 'שמור והמשך'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ===================== SECTION 1: נקודות משותפות =====================

  Widget _buildSharedPointsSection() {
    final isStar = _navigationType == 'star';
    final isParachute = _navigationType == 'parachute';
    final isGuard = _forceComposition == 'guard';

    final sectionTitle = isStar
        ? 'נקודה מרכזית'
        : isParachute
            ? 'נקודת סיום'
            : isGuard
                ? 'נקודות התחלה, החלפה וסיום'
                : 'נקודות התחלה וסיום';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sectionTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (isStar) ...[
              // כוכב — נקודה מרכזית אחת
              _buildPointDropdown(
                label: 'נקודה מרכזית (חובה)',
                value: _startPointId,
                icon: Icons.star,
                color: Colors.amber,
                excludeIds: {},
                onChanged: (val) => setState(() {
                  _startPointId = val;
                  _endPointId = val; // כוכב: התחלה = סיום
                }),
              ),
              const SizedBox(height: 4),
              Text(
                'המנווט יוצא מהנקודה המרכזית, הולך לנקודה, וחוזר אליה',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ] else ...[
              // נקודת התחלה (לא לצנחנים)
              if (!isParachute) ...[
                _buildPointDropdown(
                  label: 'נקודת התחלה (חובה)',
                  value: _startPointId,
                  icon: Icons.play_arrow,
                  color: Colors.green,
                  excludeIds: {
                    ..._intermediatePointIds,
                  },
                  onChanged: (val) => setState(() => _startPointId = val),
                ),
                const SizedBox(height: 12),
              ],

              // נקודת החלפה — רק למאבטח
              if (isGuard) ...[
                _buildPointDropdown(
                  label: 'נקודת החלפה (חובה)',
                  value: _swapPointId,
                  icon: Icons.swap_horiz,
                  color: Colors.grey[700]!,
                  excludeIds: {},
                  onChanged: (val) => setState(() => _swapPointId = val),
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
              _buildPointDropdown(
                label: 'נקודת סיום (חובה)',
                value: _endPointId,
                icon: Icons.stop,
                color: Colors.red,
                excludeIds: {
                  ..._intermediatePointIds,
                },
                onChanged: (val) => setState(() => _endPointId = val),
              ),
            ],

            // נקודות ביניים (לא לכוכב)
            if (!isStar) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.more_horiz, color: Colors.purple[400], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'נקודות ביניים (${_intermediatePointIds.length}/10)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_intermediatePointIds.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _intermediatePointIds.map((cpId) {
                    final cp = _getCheckpoint(cpId);
                    return Chip(
                      label: Text(cp?.displayLabel ?? cpId),
                      backgroundColor: Colors.purple.shade50,
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() {
                          _intermediatePointIds.remove(cpId);
                          _removeIntermediateFromAll(cpId);
                        });
                      },
                    );
                  }).toList(),
                ),

              if (_intermediatePointIds.length < 10)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildAddIntermediateButton(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPointDropdown({
    required String label,
    required String? value,
    required IconData icon,
    required Color color,
    required Set<String> excludeIds,
    required ValueChanged<String?> onChanged,
  }) {
    final items = <DropdownMenuItem<String>>[
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
      ..._checkpoints
          .where((c) => !excludeIds.contains(c.id))
          .map((c) => DropdownMenuItem<String>(
                value: c.id,
                child: Text(c.displayLabel),
              )),
    ];

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: value != null && _checkpoints.any((c) => c.id == value)
                ? value
                : null,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            items: items,
            onChanged: (val) async {
              if (val == '__pick_on_map__') {
                final selectedId = await Navigator.push<String>(context,
                  MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                    checkpoints: _checkpoints,
                    boundary: _boundaries.isNotEmpty ? _boundaries.first : null,
                    excludeIds: excludeIds,
                  )));
                if (selectedId != null) onChanged(selectedId);
                return;
              }
              onChanged(val);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddIntermediateButton() {
    final excludeIds = <String>{
      if (_startPointId != null) _startPointId!,
      if (_endPointId != null) _endPointId!,
      ..._intermediatePointIds,
    };
    final available = _checkpoints.where((c) => !excludeIds.contains(c.id)).toList();

    return PopupMenuButton<String>(
      onSelected: (cpId) async {
        if (cpId == '__pick_on_map__') {
          final selectedId = await Navigator.push<String>(context,
            MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
              checkpoints: _checkpoints,
              boundary: _boundaries.isNotEmpty ? _boundaries.first : null,
              excludeIds: excludeIds,
            )));
          if (selectedId != null) {
            setState(() {
              _intermediatePointIds.add(selectedId);
              _syncIntermediateToAll();
            });
          }
          return;
        }
        setState(() {
          _intermediatePointIds.add(cpId);
          _syncIntermediateToAll();
        });
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: '__pick_on_map__',
          child: Row(
            children: [
              Icon(Icons.map, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('בחר במפה'),
            ],
          ),
        ),
        ...available.map((cp) {
          return PopupMenuItem(
            value: cp.id,
            child: Text(cp.displayLabel),
          );
        }),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.purple.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: Colors.purple[400]),
            const SizedBox(width: 4),
            Text(
              'הוסף נקודת ביניים',
              style: TextStyle(color: Colors.purple[400]),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== SECTION 2: רשימת מנווטים =====================

  Widget _buildNavigatorsSection() {
    if (_navigatorIds.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'לא נמצאו מנווטים',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final mandatorySet = _intermediatePointIds.toSet();
    final assignedCount = _navigatorIds
        .where((uid) {
          final cps = _navigatorCheckpoints[uid] ?? [];
          return cps.any((c) => !mandatorySet.contains(c));
        })
        .length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'מנווטים ($assignedCount/${_navigatorIds.length} חולקו)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final uid in _navigatorIds) ...[
              _buildNavigatorTile(uid),
              if (_expandedNavigatorId == uid)
                _buildInlineMap(uid),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavigatorTile(String uid) {
    final cps = _navigatorCheckpoints[uid] ?? [];
    final isExpanded = _expandedNavigatorId == uid;
    final mandatorySet = _intermediatePointIds.toSet();
    final manualCount = cps.where((c) => !mandatorySet.contains(c)).length;
    final hasCheckpoints = manualCount > 0;
    final sequence = cps.isNotEmpty ? _buildFullSequence(cps) : <String>[];
    final lengthKm = cps.isNotEmpty ? _calculateRouteLength(sequence) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: hasCheckpoints ? Colors.green.shade200 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() {
                _expandedNavigatorId = isExpanded ? null : uid;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    hasCheckpoints ? Icons.check_circle : Icons.circle_outlined,
                    color: hasCheckpoints ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getNavigatorName(uid),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (cps.isNotEmpty)
                          Text(
                            '$manualCount נקודות${_intermediatePointIds.isNotEmpty ? ' + ${_intermediatePointIds.length} חובה' : ''} · ${lengthKm.toStringAsFixed(1)} ק"מ',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasCheckpoints ? Colors.grey[600] : Colors.orange[400],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // כפתור בחירת נקודות
                  IconButton(
                    icon: const Icon(Icons.checklist, size: 20),
                    tooltip: 'בחר נקודות',
                    onPressed: () => _showCheckpointSelector(uid),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content — ReorderableListView
          if (isExpanded && cps.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: cps.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = cps.removeAt(oldIndex);
                    cps.insert(newIndex, item);
                  });
                },
                itemBuilder: (_, index) {
                  final cpId = cps[index];
                  final cp = _getCheckpoint(cpId);
                  final isMandatory = _intermediatePointIds.contains(cpId);
                  final isManualCluster = _isManualClusterMode;
                  final isDecoy = _navigatorDecoyPoints[uid]?.contains(cpId) ?? false;
                  return ListTile(
                    key: ValueKey('$uid-$cpId'),
                    dense: true,
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle, size: 20),
                    ),
                    title: Text(
                      '${index + 1}. ${cp?.name ?? cpId}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isMandatory
                            ? Colors.purple[700]
                            : isManualCluster && isDecoy
                                ? Colors.blue[400]
                                : isManualCluster
                                    ? Colors.deepPurple[700]
                                    : null,
                        fontWeight: isMandatory ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: isMandatory
                        ? Text('נקודת ביניים (חובה)',
                            style: TextStyle(fontSize: 11, color: Colors.purple[400]))
                        : isManualCluster
                            ? Text(
                                isDecoy ? 'נקודת הסחה' : 'נקודת אמת',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDecoy ? Colors.blue[400] : Colors.deepPurple[400],
                                ),
                              )
                            : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // טוגל הסחה/אמת — רק באשכולות ידני ולא חובה
                        if (isManualCluster && !isMandatory)
                          IconButton(
                            icon: Icon(
                              isDecoy ? Icons.blur_on : Icons.adjust,
                              size: 18,
                              color: isDecoy ? Colors.blue[400] : Colors.deepPurple[400],
                            ),
                            tooltip: isDecoy ? 'סמן כנקודת אמת' : 'סמן כנקודת הסחה',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32),
                            onPressed: () {
                              setState(() {
                                final set = _navigatorDecoyPoints.putIfAbsent(uid, () => {});
                                if (isDecoy) {
                                  set.remove(cpId);
                                } else {
                                  set.add(cpId);
                                }
                              });
                            },
                          ),
                        if (isMandatory)
                          Icon(Icons.lock, size: 14, color: Colors.purple[300])
                        else
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32),
                            onPressed: () {
                              setState(() {
                                cps.removeAt(index);
                                _navigatorDecoyPoints[uid]?.remove(cpId);
                              });
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (isExpanded && cps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'לא נבחרו נקודות — לחץ על הכפתור לבחירה',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  // ===================== SETTINGS SECTIONS =====================

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
                DropdownMenuItem(value: 'parachute', child: Text('צנחן')),
                DropdownMenuItem(value: 'clusters', child: Text('אשכולות')),
                DropdownMenuItem(value: 'clusters_reverse', child: Text('אשכולות הפוך')),
              ],
              onChanged: (value) {
                setState(() {
                  _navigationType = value!;
                  if (value == 'star') {
                    if (_forceComposition == 'guard') {
                      _forceComposition = 'solo';
                      _swapPointId = null;
                      _manualGroups = {};
                    }
                    if (_scoringCriterion != 'uniqueness' && _scoringCriterion != 'doubleCheck') {
                      _scoringCriterion = 'uniqueness';
                    }
                    _endPointId = _startPointId;
                  }
                  if (value == 'clusters' || value == 'clusters_reverse') {
                    if (_forceComposition == 'guard') {
                      _forceComposition = 'solo';
                      _swapPointId = null;
                      _manualGroups = {};
                    }
                  }
                  if (value == 'parachute') {
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
              onChanged: (value) => setState(() => _executionOrder = value!),
            ),
            RadioListTile<String>(
              title: const Text('לפי בחירת המנווט'),
              subtitle: const Text('המנווט יכול לבחור את סדר הנקודות'),
              value: 'navigator_choice',
              groupValue: _executionOrder,
              onChanged: (value) => setState(() => _executionOrder = value!),
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

  void _autoAssignDropPoints() {
    final navigators = List<String>.from(_navigatorIds);
    navigators.shuffle();
    final result = <String, String>{};
    for (var i = 0; i < navigators.length; i++) {
      result[navigators[i]] = _dropPointIds[i % _dropPointIds.length];
    }
    setState(() => _navigatorDropPoints = result);
  }

  void _autoAssignGroups() {
    final baseSize = ForceComposition(type: _forceComposition).baseGroupSize;
    final groups = RoutesDistributionService.autoGroupNavigators(
      navigators: _navigatorIds,
      baseGroupSize: baseSize,
      compositionType: _forceComposition,
    );
    setState(() => _manualGroups = groups);
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
              '${_navigatorIds.length} מנווטים, גודל בסיס: $baseSize',
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final selectedId = await Navigator.push<String>(context,
                  MaterialPageRoute(builder: (_) => CheckpointMapPickerScreen(
                    checkpoints: _checkpoints,
                    boundary: _boundaries.isNotEmpty ? _boundaries.first : null,
                  )));
                if (selectedId != null && !_dropPointIds.contains(selectedId)) {
                  setState(() => _dropPointIds.add(selectedId));
                }
              },
              icon: const Icon(Icons.map, size: 18),
              label: const Text('בחר במפה'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
              ),
            ),
            if (_dropPointIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_dropPointIds.length} נקודות הצנחה נבחרו',
                style: TextStyle(fontSize: 12, color: Colors.orange[700]),
              ),
            ],
            const Divider(height: 24),
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
                  if (value == 'manual' && _dropPointIds.isNotEmpty) {
                    _autoAssignDropPoints();
                  }
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
            if (_parachuteAssignmentMethod == 'manual' && _dropPointIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'שיבוץ מנווטים לנקודות',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _autoAssignDropPoints,
                    icon: const Icon(Icons.shuffle, size: 18),
                    label: Text(_navigatorDropPoints.isEmpty ? 'חלק שווה' : 'ערבב מחדש'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_navigatorIds.length} מנווטים, ${_dropPointIds.length} נקודות הצנחה',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (_navigatorDropPoints.isEmpty) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'לחץ "חלק שווה" לחלוקה אוטומטית',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                ..._dropPointIds.map((dropPointId) {
                  final cp = _checkpoints.cast<Checkpoint?>().firstWhere(
                    (c) => c!.id == dropPointId,
                    orElse: () => null,
                  );
                  final dropPointName = cp?.name ?? dropPointId;
                  final assignedNavigators = _navigatorDropPoints.entries
                      .where((e) => e.value == dropPointId)
                      .map((e) => e.key)
                      .toList();
                  return Card(
                    color: Colors.orange[50],
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 18, color: Colors.orange),
                              const SizedBox(width: 6),
                              Text(
                                '$dropPointName (${assignedNavigators.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (assignedNavigators.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ...assignedNavigators.map((navId) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person, size: 18, color: Colors.blueGrey),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(navId, style: const TextStyle(fontSize: 13))),
                                    DropdownButton<String>(
                                      value: dropPointId,
                                      underline: const SizedBox(),
                                      isDense: true,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                      items: _dropPointIds.map((dpId) {
                                        final dpCp = _checkpoints.cast<Checkpoint?>().firstWhere(
                                          (c) => c!.id == dpId,
                                          orElse: () => null,
                                        );
                                        return DropdownMenuItem(
                                          value: dpId,
                                          child: Text(dpCp?.name ?? dpId),
                                        );
                                      }).toList(),
                                      onChanged: (newDropPointId) {
                                        if (newDropPointId != null && newDropPointId != dropPointId) {
                                          setState(() {
                                            _navigatorDropPoints[navId] = newDropPointId;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
            const Divider(height: 24),
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
            const SizedBox(height: 12),
            // טוגל אוטומטי / ידני
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'automatic', label: Text('אוטומטי'), icon: Icon(Icons.auto_awesome, size: 16)),
                ButtonSegment(value: 'manual', label: Text('ידני'), icon: Icon(Icons.edit, size: 16)),
              ],
              selected: {_clusterDecoyMode},
              onSelectionChanged: (selected) {
                setState(() => _clusterDecoyMode = selected.first);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _clusterDecoyMode == 'automatic'
                  ? 'המערכת תוסיף נקודות הסחה אוטומטית לפי הכמות והרדיוס'
                  : 'סמן ידנית בכל מנווט אילו נקודות הן הסחה ואילו אמת',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (_clusterDecoyMode == 'automatic') ...[
              const SizedBox(height: 16),
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
            ],
          ],
        ),
      ),
    );
  }

  // ===================== INLINE MAP — מפה בתוך רשימת המנווטים =====================

  Widget _buildInlineMap(String navigatorId) {
    final bounds = _getMapBounds();
    if (bounds == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'אין נקודות עם קואורדינטות',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // --- סינון מנווטים ---
          if (_navigatorIds.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _navigatorIds.map((uid) {
                    final isVisible = _mapVisibleNavigatorIds.contains(uid);
                    final isThis = uid == navigatorId;
                    final colorIdx = _navigatorIds.indexOf(uid);
                    final routeColor = isThis
                        ? Colors.red
                        : _nonRedRouteColors[colorIdx % _nonRedRouteColors.length];
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: FilterChip(
                        label: Text(
                          _getNavigatorName(uid),
                          style: TextStyle(fontSize: 11, color: isVisible ? routeColor : Colors.grey),
                        ),
                        selected: isVisible,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _mapVisibleNavigatorIds.add(uid);
                            } else {
                              _mapVisibleNavigatorIds.remove(uid);
                            }
                          });
                        },
                        selectedColor: routeColor.withValues(alpha: 0.15),
                        checkmarkColor: routeColor,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          // --- מפה ---
          ClipRRect(
            borderRadius: _navigatorIds.length > 1
                ? const BorderRadius.vertical(bottom: Radius.circular(8))
                : BorderRadius.circular(8),
            child: SizedBox(
              height: 300,
              child: Stack(
                children: [
                  MapWithTypeSelector(
                    mapController: _mapController,
                    initialMapType: MapConfig.resolveMapType(widget.navigation.displaySettings.defaultMap),
                    options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(40),
                      ),
                    ),
                    layers: [
                      PolylineLayer(polylines: _buildPolylines(selectedNavigatorId: navigatorId)),
                      MarkerLayer(markers: _buildMarkers(navigatorId: navigatorId)),
                    ],
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          final camera = _mapController.camera;
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => FullscreenMapScreen(
                              title: 'חלוקה ידנית',
                              initialCenter: camera.center,
                              initialZoom: camera.zoom,
                              layerConfigs: [
                                MapLayerConfig(id: 'routes', label: 'צירים', color: Colors.orange, visible: true, onVisibilityChanged: (_) {}),
                                MapLayerConfig(id: 'checkpoints', label: 'נקודות ציון', color: Colors.blue, visible: true, onVisibilityChanged: (_) {}),
                              ],
                              layerBuilder: (visibility, opacity) => [
                                if (visibility['routes'] == true)
                                  PolylineLayer(polylines: _buildPolylines(selectedNavigatorId: navigatorId)),
                                if (visibility['checkpoints'] == true)
                                  MarkerLayer(markers: _buildMarkers(navigatorId: navigatorId)),
                              ],
                            ),
                          ));
                        },
                        child: const SizedBox(
                          width: 40, height: 40,
                          child: Icon(Icons.fullscreen, size: 22),
                        ),
                      ),
                    ),
                  ),
                  // מקרא צבעים
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isManualClusterMode) ...[
                            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle)),
                            const SizedBox(width: 3),
                            const Text('אמת', style: TextStyle(fontSize: 9)),
                            const SizedBox(width: 6),
                            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                            const SizedBox(width: 3),
                            const Text('הסחה', style: TextStyle(fontSize: 9)),
                          ] else ...[
                            Container(width: 12, height: 3, color: Colors.red),
                            const SizedBox(width: 4),
                            Text(_usersCache[navigatorId]?.fullName ?? navigatorId,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
      ),
    );
  }
}
