import 'dart:math';
import 'dart:isolate';
import 'package:turf/turf.dart' as turf;
import '../domain/entities/navigation.dart' as domain;
import '../domain/entities/checkpoint.dart';
import '../domain/entities/navigation_tree.dart';
import '../domain/entities/navigation_settings.dart';
import '../domain/entities/boundary.dart';
import '../core/utils/geometry_utils.dart';
import '../domain/entities/safety_point.dart';
import '../data/repositories/user_repository.dart';

/// פרמטרים לריצה ב-Isolate (חייבים להיות serializable)
class _DistributionParams {
  final List<String> navigators;
  final List<Map<String, dynamic>> checkpointMaps; // serializable checkpoint data
  final String? startPointId;
  final String? endPointId;
  final List<Map<String, dynamic>> waypointMaps; // serializable waypoint data
  final String executionOrder;
  final int checkpointsPerNavigator;
  final double minRouteLength;
  final double maxRouteLength;
  final String scoringCriterion; // 'fairness', 'midpoint', 'uniqueness'
  final int maxIterations;
  final SendPort progressPort;
  final bool isGuard;
  final String? swapPointId;
  final List<List<double>>? boundaryCoords;
  final List<List<List<double>>>? safetyPolygons;

  _DistributionParams({
    required this.navigators,
    required this.checkpointMaps,
    this.startPointId,
    this.endPointId,
    required this.waypointMaps,
    required this.executionOrder,
    required this.checkpointsPerNavigator,
    required this.minRouteLength,
    required this.maxRouteLength,
    required this.scoringCriterion,
    required this.maxIterations,
    required this.progressPort,
    this.isGuard = false,
    this.swapPointId,
    this.boundaryCoords,
    this.safetyPolygons,
  });
}

/// נתוני נקודה פשוטים (serializable) לשימוש ב-Isolate
class _SimpleCheckpoint {
  final String id;
  final double lat;
  final double lng;

  _SimpleCheckpoint({required this.id, required this.lat, required this.lng});

  factory _SimpleCheckpoint.fromMap(Map<String, dynamic> map) {
    return _SimpleCheckpoint(
      id: map['id'] as String,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
    );
  }
}

/// נתוני waypoint פשוטים
class _SimpleWaypoint {
  final String checkpointId;
  final String placementType;
  final double? afterDistanceMinKm;
  final double? afterDistanceMaxKm;
  final int? afterCheckpointIndex;

  _SimpleWaypoint({
    required this.checkpointId,
    required this.placementType,
    this.afterDistanceMinKm,
    this.afterDistanceMaxKm,
    this.afterCheckpointIndex,
  });

  factory _SimpleWaypoint.fromMap(Map<String, dynamic> map) {
    // תאימות לאחור: afterDistanceKm ישן → min=max=afterDistanceKm
    final oldDistance = (map['afterDistanceKm'] as num?)?.toDouble();
    return _SimpleWaypoint(
      checkpointId: map['checkpointId'] as String,
      placementType: map['placementType'] as String,
      afterDistanceMinKm: (map['afterDistanceMinKm'] as num?)?.toDouble() ?? oldDistance,
      afterDistanceMaxKm: (map['afterDistanceMaxKm'] as num?)?.toDouble() ?? oldDistance,
      afterCheckpointIndex: map['afterCheckpointIndex'] as int?,
    );
  }
}

/// סוג הפרת קטע — יציאה מגבול או חיתוך נת"ב
class _SegmentViolation {
  final int boundaryCrossings; // 0 = אין יציאה, >0 = מספר חציות של צלעות הגבול
  final int safetyPolygonsCrossed;
  const _SegmentViolation(this.boundaryCrossings, this.safetyPolygonsCrossed);
  static const none = _SegmentViolation(0, 0);
  bool get exitsBoundary => boundaryCrossings > 0;
  bool get hasViolation => boundaryCrossings > 0 || safetyPolygonsCrossed > 0;
}

/// תוצאת ציר פנימית
class _RouteResult {
  final List<String> checkpointIds;
  final List<String> sequence;
  final List<String> waypointIds;
  final double routeLengthKm;
  final bool inRange;
  // Guard mode: אורכי חצאי ציר (null כשלא במצב מאבטח)
  final double? firstHalfLengthKm;
  final double? secondHalfLengthKm;
  // הפרות גיאומטריות — קטעים שחוצים גבול או נת"בים
  final int boundaryExits;
  final int safetyIntersections;

  _RouteResult({
    required this.checkpointIds,
    required this.sequence,
    required this.waypointIds,
    required this.routeLengthKm,
    required this.inRange,
    this.firstHalfLengthKm,
    this.secondHalfLengthKm,
    this.boundaryExits = 0,
    this.safetyIntersections = 0,
  });
}

/// תוצאת חלוקה פנימית
class _InternalDistribution {
  final Map<String, _RouteResult> routes;
  final double score;
  final bool allInRange;
  final bool hasSharedCheckpoints;
  final int sharedCount;

  _InternalDistribution({
    required this.routes,
    required this.score,
    required this.allInRange,
    this.hasSharedCheckpoints = false,
    this.sharedCount = 0,
  });
}

/// שירות לחלוקה אוטומטית של צירים — אלגוריתם Monte Carlo
class RoutesDistributionService {
  RoutesDistributionService({UserRepository? userRepository})
      : _injectedUserRepository = userRepository;

  final UserRepository? _injectedUserRepository;

  /// שיבוץ אוטומטי של מנווטים לקבוצות
  /// מנווטים שכבר משובצים ב-manualGroups נשארים; שאר המנווטים מתחלקים בין הקבוצות.
  static Map<String, List<String>> autoGroupNavigators({
    required List<String> navigators,
    required int baseGroupSize,
    Map<String, List<String>> manualGroups = const {},
    String compositionType = 'solo',
  }) {
    final result = <String, List<String>>{};
    final assigned = <String>{};

    // העתקת קבוצות ידניות קיימות
    for (final entry in manualGroups.entries) {
      final validMembers = entry.value.where((id) => navigators.contains(id)).toList();
      if (validMembers.isNotEmpty) {
        result[entry.key] = validMembers;
        assigned.addAll(validMembers);
      }
    }

    // מנווטים לא משובצים
    final unassigned = navigators.where((id) => !assigned.contains(id)).toList()..shuffle();

    // יצירת קבוצות חדשות
    int groupCounter = result.length;
    while (unassigned.isNotEmpty) {
      // בדיקה אם יש קבוצה קיימת שצריכה השלמה
      final incompleteGroup = result.entries
          .where((e) => e.value.length < baseGroupSize)
          .firstOrNull;

      if (incompleteGroup != null) {
        final needed = baseGroupSize - incompleteGroup.value.length;
        final toAdd = unassigned.take(needed).toList();
        incompleteGroup.value.addAll(toAdd);
        unassigned.removeRange(0, toAdd.length);
      } else if (unassigned.length >= baseGroupSize) {
        // קבוצה חדשה מלאה
        groupCounter++;
        final groupId = 'group_$groupCounter';
        result[groupId] = unassigned.take(baseGroupSize).toList();
        unassigned.removeRange(0, baseGroupSize);
      } else {
        // שארית — טיפול לפי הרכב הכוח
        if (compositionType == 'pair') {
          // צמד: שארית מצטרפת לקבוצה האחרונה → שלישייה
          final lastGroupKey = result.keys.last;
          result[lastGroupKey]!.addAll(unassigned);
          unassigned.clear();
        } else if (compositionType == 'guard') {
          // מאבטח: כל שארית מקבלת קבוצה בודדת
          while (unassigned.isNotEmpty) {
            groupCounter++;
            result['group_$groupCounter'] = [unassigned.removeAt(0)];
          }
        } else {
          // ברירת מחדל — round-robin
          final groupKeys = result.keys.toList();
          for (int i = 0; unassigned.isNotEmpty; i++) {
            result[groupKeys[i % groupKeys.length]]!.add(unassigned.removeAt(0));
          }
        }
      }
    }

    return result;
  }

  /// חלוקה אוטומטית של צירים לפי הגדרות
  Future<domain.DistributionResult> distributeAutomatically({
    required domain.Navigation navigation,
    required NavigationTree tree,
    required List<Checkpoint> checkpoints,
    Boundary? boundary,
    String? startPointId,
    String? endPointId,
    List<WaypointCheckpoint> waypoints = const [],
    required String executionOrder,
    required int checkpointsPerNavigator,
    required double minRouteLength,
    required double maxRouteLength,
    String scoringCriterion = 'fairness',
    ForceComposition? forceComposition,
    List<SafetyPoint> safetyPoints = const [],
    void Function(int current, int total)? onProgress,
    List<String>? navigatorIds,
  }) async {
    final composition = forceComposition ?? const ForceComposition();

    // --- שלב 1: הכנה ---
    // מציאת משתתפים
    List<String> navigators = navigatorIds ?? await _findNavigators(navigation, tree);

    if (navigators.isEmpty) {
      throw Exception('לא נמצאו משתתפים - יש לבחור תתי-מסגרות עם משתמשים');
    }

    if (checkpoints.isEmpty) {
      throw Exception('לא נמצאו נקודות ציון');
    }

    // ולידציות הרכב הכוח
    if (composition.isGrouped) {
      if (navigators.length < 2) {
        throw Exception('נדרשים לפחות 2 מנווטים להרכב ${_compositionLabel(composition.type)}');
      }
      if (composition.type == 'squad' && navigators.length < 4) {
        throw Exception('נדרשים לפחות 4 מנווטים להרכב חוליה');
      }
    }

    if (navigation.navigationType == 'parachute' && composition.isGuard) {
      throw Exception('הרכב מאבטח לא נתמך בניווט צנחנים');
    }

    // --- שיבוץ קבוצות ---
    Map<String, List<String>> groups = {};
    List<String> virtualNavigators = navigators;

    if (composition.isGrouped) {
      groups = autoGroupNavigators(
        navigators: navigators,
        baseGroupSize: composition.baseGroupSize,
        manualGroups: composition.manualGroups,
      );
      // "מנווטים וירטואליים" — מזהה קבוצה אחד לכל קבוצה
      virtualNavigators = groups.keys.toList();
    }

    // סינון נקודות לפי גבול גזרה
    List<Checkpoint> availableCheckpoints = checkpoints;
    if (boundary != null && boundary.coordinates.isNotEmpty) {
      final pointCheckpoints = checkpoints.where((cp) => !cp.isPolygon && cp.coordinates != null).toList();
      availableCheckpoints = GeometryUtils.filterPointsInPolygon(
        points: pointCheckpoints,
        getCoordinate: (checkpoint) => checkpoint.coordinates!,
        polygon: boundary.coordinates,
      );
    }

    // סינון נקודות הנמצאות על נת"בים או בקרבתם (50 מטר)
    if (safetyPoints.isNotEmpty) {
      availableCheckpoints = availableCheckpoints.where((cp) {
        if (cp.isPolygon || cp.coordinates == null) return true;
        final coord = cp.coordinates!;
        for (final sp in safetyPoints) {
          if (sp.type == 'point' && sp.coordinates != null) {
            if (GeometryUtils.distanceBetweenMeters(coord, sp.coordinates!) <= 50) {
              return false;
            }
          } else if (sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.length >= 3) {
            if (GeometryUtils.distanceFromPointToPolygonMeters(coord, sp.polygonCoordinates!) <= 50) {
              return false;
            }
          }
        }
        return true;
      }).toList();
    }

    // חישוב נקודות זמינות (בניכוי התחלה/סיום)
    int excludedCount = 0;
    if (startPointId != null) excludedCount++;
    if (endPointId != null && endPointId != startPointId) excludedCount++;
    final effectiveAvailable = availableCheckpoints.length - excludedCount;

    if (effectiveAvailable < checkpointsPerNavigator) {
      throw Exception(
        'אין מספיק נקודות: $effectiveAvailable נקודות זמינות לחלוקה, '
        'נדרשות לפחות $checkpointsPerNavigator נקודות למנווט אחד'
      );
    }

    // הכנת נתונים serializable ל-Isolate
    final checkpointMaps = availableCheckpoints
        .where((cp) => !cp.isPolygon && cp.coordinates != null)
        .map((cp) => {
          'id': cp.id,
          'lat': cp.coordinates!.lat,
          'lng': cp.coordinates!.lng,
        })
        .toList();

    // מאבטח: נקודת ההחלפה חייבת להיות ברשימת הנקודות (גם אם סוננה ע"י גבול גזרה)
    if (composition.isGuard && composition.swapPointId != null) {
      final swapInMaps = checkpointMaps.any((m) => m['id'] == composition.swapPointId);
      if (!swapInMaps) {
        final swapCp = checkpoints.where((cp) => cp.id == composition.swapPointId).firstOrNull;
        if (swapCp != null && !swapCp.isPolygon && swapCp.coordinates != null) {
          checkpointMaps.add({
            'id': swapCp.id,
            'lat': swapCp.coordinates!.lat,
            'lng': swapCp.coordinates!.lng,
          });
        }
      }
    }

    var waypointMaps = waypoints.map((w) => w.toMap()).toList();

    // מאבטח: נקודת ההחלפה הגלובלית כ-waypoint חובה — כך האלגוריתם מייעל את הציר דרכה
    if (composition.isGuard && composition.swapPointId != null) {
      final alreadyWaypoint = waypointMaps.any((w) => w['checkpointId'] == composition.swapPointId);
      if (!alreadyWaypoint) {
        waypointMaps = [
          ...waypointMaps,
          WaypointCheckpoint(
            checkpointId: composition.swapPointId!,
            placementType: 'distance',
            afterDistanceMinKm: minRouteLength * 0.3,
            afterDistanceMaxKm: maxRouteLength * 0.7,
          ).toMap(),
        ];
      }
    }

    // --- צנחנים: כל מנווט מתחיל מנקודת הצנחה שונה ---
    if (navigation.navigationType == 'parachute') {
      return _distributeParachuteNavigation(
        navigation: navigation,
        tree: tree,
        navigators: navigators,
        virtualNavigators: virtualNavigators,
        groups: groups,
        checkpointMaps: checkpointMaps,
        waypointMaps: waypointMaps,
        availableCheckpoints: availableCheckpoints,
        boundary: boundary,
        startPointId: startPointId,
        endPointId: endPointId,
        executionOrder: executionOrder,
        checkpointsPerNavigator: checkpointsPerNavigator,
        minRouteLength: minRouteLength,
        maxRouteLength: maxRouteLength,
        scoringCriterion: scoringCriterion,
        composition: composition,
        safetyPoints: safetyPoints,
        onProgress: onProgress,
      );
    }

    // --- כוכב: אלגוריתם חלוקה ייעודי ---
    if (navigation.navigationType == 'star') {
      return _distributeStarNavigation(
        navigators: virtualNavigators,
        checkpoints: availableCheckpoints,
        centralPointId: startPointId!,
        checkpointsPerNavigator: checkpointsPerNavigator,
        minDistance: minRouteLength,
        maxDistance: maxRouteLength,
        scoringCriterion: scoringCriterion,
        composition: composition,
        groups: groups,
        onProgress: onProgress,
      );
    }

    // --- שלב 2: הרצת אלגוריתם ב-Isolate עם מנווטים וירטואליים ---
    // מאבטח: כל מנווט וירטואלי מייצג 2 מנווטים שמתחלקים בציר — כפול נקודות
    final effectiveCpPerNav = composition.isGuard
        ? checkpointsPerNavigator * 2
        : checkpointsPerNavigator;

    // מאבטח: הציר המשותף צריך להיות כפול כדי שכל חצי יהיה בטווח
    final effectiveMinRoute = composition.isGuard ? minRouteLength * 2 : minRouteLength;
    final effectiveMaxRoute = composition.isGuard ? maxRouteLength * 2 : maxRouteLength;

    // סריאליזציית גיאומטריה ל-Isolate — גבול גזרה ונת"בים
    final List<List<double>>? serializedBoundary = (boundary != null && boundary.coordinates.length >= 3)
        ? boundary.coordinates.map((c) => [c.lat, c.lng]).toList()
        : null;
    final List<List<List<double>>>? serializedSafetyPolygons = safetyPoints
        .where((sp) => sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.length >= 3)
        .map((sp) => sp.polygonCoordinates!.map((c) => [c.lat, c.lng]).toList())
        .toList();
    final effectiveSafetyPolygons = (serializedSafetyPolygons != null && serializedSafetyPolygons.isNotEmpty)
        ? serializedSafetyPolygons : null;

    final result = await _runInIsolate(
      navigators: virtualNavigators,
      checkpointMaps: checkpointMaps,
      startPointId: startPointId,
      endPointId: endPointId,
      waypointMaps: waypointMaps,
      executionOrder: executionOrder,
      checkpointsPerNavigator: effectiveCpPerNav,
      minRouteLength: effectiveMinRoute,
      maxRouteLength: effectiveMaxRoute,
      scoringCriterion: scoringCriterion,
      onProgress: onProgress,
      isGuard: composition.isGuard,
      swapPointId: composition.swapPointId,
      boundaryCoords: serializedBoundary,
      safetyPolygons: effectiveSafetyPolygons,
    );

    // --- שלב 3: הרחבת תוצאות לפי הרכב הכוח ---
    if (composition.isSolo) {
      return result;
    }

    return _expandForComposition(
      result: result,
      composition: composition,
      groups: groups,
      checkpoints: checkpoints,
      startPointId: startPointId,
      endPointId: endPointId,
      executionOrder: executionOrder,
      minRouteLength: minRouteLength,
      maxRouteLength: maxRouteLength,
    );
  }

  /// חלוקת ניווט כוכב — כל נקודה חייבת להיות בטווח מרחק מהנקודה המרכזית
  domain.DistributionResult _distributeStarNavigation({
    required List<String> navigators,
    required List<Checkpoint> checkpoints,
    required String centralPointId,
    required int checkpointsPerNavigator,
    required double minDistance,
    required double maxDistance,
    required String scoringCriterion,
    required ForceComposition composition,
    required Map<String, List<String>> groups,
    void Function(int current, int total)? onProgress,
  }) {
    final K = checkpointsPerNavigator;
    final N = navigators.length;

    // מציאת הנקודה המרכזית
    final centralCp = checkpoints.where((cp) => cp.id == centralPointId).firstOrNull;
    if (centralCp == null || centralCp.coordinates == null) {
      throw Exception('נקודה מרכזית לא נמצאה');
    }
    final centralCoord = centralCp.coordinates!;

    // חישוב מרחק כל נקודה מהנקודה המרכזית וסינון לפי טווח
    final eligibleCheckpoints = <Checkpoint>[];
    final distancesFromCenter = <String, double>{};
    for (final cp in checkpoints) {
      if (cp.id == centralPointId) continue;
      if (cp.isPolygon || cp.coordinates == null) continue;
      final distKm = GeometryUtils.distanceBetweenMeters(centralCoord, cp.coordinates!) / 1000.0;
      distancesFromCenter[cp.id] = distKm;
      if (distKm >= minDistance && distKm <= maxDistance) {
        eligibleCheckpoints.add(cp);
      }
    }

    onProgress?.call(10, 100);

    if (eligibleCheckpoints.length < K) {
      throw Exception(
        'אין מספיק נקודות בטווח ${minDistance.toStringAsFixed(1)}-${maxDistance.toStringAsFixed(1)} ק"מ '
        'מהנקודה המרכזית: ${eligibleCheckpoints.length} נקודות זמינות, נדרשות $K',
      );
    }

    final isDoubleCheck = scoringCriterion == 'doubleCheck';
    final needsSharing = eligibleCheckpoints.length < N * K;

    if (!isDoubleCheck && !needsSharing && eligibleCheckpoints.length < N * K) {
      throw Exception(
        'אין מספיק נקודות ייחודיות: ${eligibleCheckpoints.length} זמינות, '
        'נדרשות ${N * K} ($N מנווטים × $K נקודות)',
      );
    }

    onProgress?.call(20, 100);

    // חלוקת נקודות — Monte Carlo optimization
    final random = Random();
    Map<String, domain.AssignedRoute>? bestRoutes;
    double bestScore = double.negativeInfinity;
    bool bestAllInRange = false;
    bool bestHasSharing = false;
    int bestSharedCount = 0;

    final iterations = 500;
    for (int iter = 0; iter < iterations; iter++) {
      if (iter % 10 == 0) {
        onProgress?.call(20 + (iter * 70 ~/ iterations), 100);
      }

      // חלוקה רנדומלית
      final shuffled = List<Checkpoint>.from(eligibleCheckpoints)..shuffle(random);
      final routeMap = <String, domain.AssignedRoute>{};
      bool valid = true;

      if (isDoubleCheck) {
        // אימות כפול: כל נקודה ל-2 מנווטים
        // מקסם כיסוי כפול ע"י חלוקה מחזורית
        final pool = <Checkpoint>[];
        // כל נקודה פעמיים (אם מספיק)
        for (int pass = 0; pass < 2; pass++) {
          pool.addAll(shuffled);
        }
        pool.shuffle(random);

        for (int i = 0; i < N; i++) {
          final navId = navigators[i];
          final points = <Checkpoint>[];
          final seen = <String>{};
          for (final cp in pool) {
            if (points.length >= K) break;
            if (!seen.contains(cp.id)) {
              seen.add(cp.id);
              points.add(cp);
            }
          }
          if (points.length < K) { valid = false; break; }
          // הסר נקודות שנתפסו (אחרת אימות כפול לא מובטח)
          for (final cp in points) {
            final idx = pool.indexWhere((p) => p.id == cp.id);
            if (idx >= 0) pool.removeAt(idx);
          }

          final totalRoundTrip = points.fold<double>(0, (sum, cp) =>
            sum + 2 * (distancesFromCenter[cp.id] ?? 0));

          routeMap[navId] = domain.AssignedRoute(
            checkpointIds: points.map((cp) => cp.id).toList(),
            routeLengthKm: totalRoundTrip,
            sequence: points.map((cp) => cp.id).toList(),
            startPointId: centralPointId,
            endPointId: centralPointId,
            status: _starRouteStatus(points, distancesFromCenter, minDistance, maxDistance)
          );
        }
      } else {
        // ייחודיות: כל נקודה למנווט אחד (אם אפשר)
        if (needsSharing) {
          // שיתוף — חלוקה מחזורית
          final pool = <Checkpoint>[];
          while (pool.length < N * K) {
            pool.addAll(shuffled);
          }
          for (int i = 0; i < N; i++) {
            final navId = navigators[i];
            final points = pool.skip(i * K).take(K).toList();
            final totalRoundTrip = points.fold<double>(0, (sum, cp) =>
              sum + 2 * (distancesFromCenter[cp.id] ?? 0));
            routeMap[navId] = domain.AssignedRoute(
              checkpointIds: points.map((cp) => cp.id).toList(),
              routeLengthKm: totalRoundTrip,
              sequence: points.map((cp) => cp.id).toList(),
              startPointId: centralPointId,
              endPointId: centralPointId,
              status: _starRouteStatus(points, distancesFromCenter, minDistance, maxDistance),
            );
          }
        } else {
          // ייחודי — כל נקודה פעם אחת
          for (int i = 0; i < N; i++) {
            final navId = navigators[i];
            final points = shuffled.skip(i * K).take(K).toList();
            if (points.length < K) { valid = false; break; }
            final totalRoundTrip = points.fold<double>(0, (sum, cp) =>
              sum + 2 * (distancesFromCenter[cp.id] ?? 0));
            routeMap[navId] = domain.AssignedRoute(
              checkpointIds: points.map((cp) => cp.id).toList(),
              routeLengthKm: totalRoundTrip,
              sequence: points.map((cp) => cp.id).toList(),
              startPointId: centralPointId,
              endPointId: centralPointId,
              status: _starRouteStatus(points, distancesFromCenter, minDistance, maxDistance),
            );
          }
        }
      }

      if (!valid) continue;

      // ניקוד
      final allCpIds = routeMap.values.expand((r) => r.checkpointIds).toList();
      final uniqueCount = allCpIds.toSet().length;
      final hasSharing = allCpIds.length != uniqueCount;
      final sharedCount = allCpIds.length - uniqueCount;

      double score = 0;
      if (isDoubleCheck) {
        // ניקוד: מקסימום נקודות שנדקרו ע"י 2 מנווטים
        final cpCounts = <String, int>{};
        for (final id in allCpIds) {
          cpCounts[id] = (cpCounts[id] ?? 0) + 1;
        }
        final doubleVisited = cpCounts.values.where((c) => c >= 2).length;
        score = doubleVisited / uniqueCount; // 1.0 = כל הנקודות נבדקו כפול
      } else {
        // ניקוד ייחודיות: מקסימום נקודות ייחודיות
        score = uniqueCount / allCpIds.length; // 1.0 = אין שיתוף כלל
      }

      if (score > bestScore) {
        bestScore = score;
        bestRoutes = routeMap;
        bestAllInRange = true; // כל הנקודות כבר סוננו לטווח
        bestHasSharing = hasSharing;
        bestSharedCount = sharedCount;
      }

      // early exit — תוצאה מושלמת
      if (score >= 1.0) break;
    }

    onProgress?.call(100, 100);

    if (bestRoutes == null) {
      throw Exception('לא נמצאה חלוקה מתאימה');
    }

    // הרחבת קבוצות (pair/squad)
    if (composition.isGrouped) {
      final expandedRoutes = <String, domain.AssignedRoute>{};
      for (final entry in bestRoutes.entries) {
        final groupId = entry.key;
        final route = entry.value;
        final members = groups[groupId];
        if (members == null || members.isEmpty) continue;
        for (final memberId in members) {
          expandedRoutes[memberId] = route.copyWith(groupId: groupId);
        }
      }
      bestRoutes = expandedRoutes;
    }

    return domain.DistributionResult(
      status: 'success',
      routes: bestRoutes,
      approvalOptions: [],
      hasSharedCheckpoints: bestHasSharing,
      sharedCheckpointCount: bestSharedCount,
      forceComposition: composition,
    );
  }

  /// תווית הרכב הכוח
  static String _compositionLabel(String type) => switch (type) {
    'guard' => 'מאבטח',
    'pair' => 'צמד',
    'squad' => 'חוליה',
    _ => 'בדד',
  };

  /// סטטוס ציר לפי אורך וטווח
  static String _routeStatus(double length, double min, double max) {
    if (length < min) return 'too_short';
    if (length > max) return 'too_long';
    return 'optimal';
  }

  /// סטטוס ציר כוכב — בדיקת מרחק כל נקודה מהנקודה המרכזית
  static String _starRouteStatus(List<Checkpoint> points, Map<String, double> distances, double min, double max) {
    for (final cp in points) {
      final dist = distances[cp.id];
      if (dist == null) return 'invalid';
      if (dist < min) return 'too_short';
      if (dist > max) return 'too_long';
    }
    return 'optimal';
  }

  /// הרחבת תוצאות חלוקה לפי הרכב הכוח
  domain.DistributionResult _expandForComposition({
    required domain.DistributionResult result,
    required ForceComposition composition,
    required Map<String, List<String>> groups,
    required List<Checkpoint> checkpoints,
    String? startPointId,
    String? endPointId,
    String executionOrder = 'sequential',
    double minRouteLength = 0,
    double maxRouteLength = double.infinity,
  }) {
    final expandedRoutes = <String, domain.AssignedRoute>{};

    if (composition.isGuard) {
      // --- מאבטח: פיצול לפי כמות נקודות (חלוקה שווה) ---
      String? swapId = composition.swapPointId;

      // בניית נתוני אופטימיזציה לחצאי ציר (NN+2-opt)
      final cpMap = <String, Checkpoint>{};
      for (final cp in checkpoints) {
        if (!cp.isPolygon && cp.coordinates != null) cpMap[cp.id] = cp;
      }
      final simpleCheckpoints = cpMap.values
          .map((cp) => _SimpleCheckpoint(id: cp.id, lat: cp.coordinates!.lat, lng: cp.coordinates!.lng))
          .toList();
      final simpleCpMap = <String, _SimpleCheckpoint>{};
      for (final sc in simpleCheckpoints) simpleCpMap[sc.id] = sc;
      final distMatrix = _buildDistanceMatrix(simpleCheckpoints);

      final startCp = startPointId != null ? simpleCpMap[startPointId] : null;
      final endCp = endPointId != null ? simpleCpMap[endPointId] : null;
      final swapCp = swapId != null ? simpleCpMap[swapId] : null;

      for (final entry in result.routes.entries) {
        final groupId = entry.key;
        final route = entry.value;
        final members = groups[groupId];
        if (members == null || members.isEmpty) continue;

        // אין נקודת חלוקה — החזר ציר משולב ודרוש בחירה ידנית
        if (swapId == null) {
          for (final memberId in members) {
            expandedRoutes[memberId] = route.copyWith(
              groupId: groupId, segmentType: 'full', swapPointId: null,
            );
          }
          continue;
        }

        final seq = route.sequence;

        // מיון נ"צ לפי סדרן ברצף — מבטיח חלוקה גיאוגרפית נכונה
        final orderedCps = List<String>.from(route.checkpointIds);
        // נקודת החלפה לא נחשבת נקודה של מנווט (לא ניקוד, לא דקירה)
        orderedCps.remove(swapId);
        orderedCps.sort((a, b) {
          final ai = seq.indexOf(a);
          final bi = seq.indexOf(b);
          return (ai < 0 ? 999999 : ai).compareTo(bi < 0 ? 999999 : bi);
        });

        // חלוקה שווה: חצי ראשון ← מנווט 1, חצי שני ← מנווט 2
        final half = orderedCps.length ~/ 2;
        if (half == 0) {
          for (final memberId in members) {
            expandedRoutes[memberId] = route.copyWith(
              groupId: groupId, segmentType: 'full', swapPointId: swapId,
            );
          }
          continue;
        }

        final firstHalfCps = orderedCps.sublist(0, half);
        final secondHalfCps = orderedCps.sublist(half);

        assert(firstHalfCps.isNotEmpty, 'Guard mode: firstHalfCps is empty');
        assert(secondHalfCps.isNotEmpty, 'Guard mode: secondHalfCps is empty');

        // אופטימיזציית NN+2-opt לכל חצי ציר בנפרד
        final firstHalfSimple = firstHalfCps
            .map((id) => simpleCpMap[id])
            .whereType<_SimpleCheckpoint>()
            .toList();
        final firstResult = _rebuildRoute(
          firstHalfSimple, startCp, swapCp,
          const [], // waypoints — כבר שולבו בציר המשולב
          simpleCheckpoints, executionOrder,
          minRouteLength, maxRouteLength, distMatrix,
        );

        final secondHalfSimple = secondHalfCps
            .map((id) => simpleCpMap[id])
            .whereType<_SimpleCheckpoint>()
            .toList();
        final secondResult = _rebuildRoute(
          secondHalfSimple, swapCp, endCp,
          const [],
          simpleCheckpoints, executionOrder,
          minRouteLength, maxRouteLength, distMatrix,
        );

        final firstHalfLength = firstResult.routeLengthKm;
        final secondHalfLength = secondResult.routeLengthKm;
        final firstHalfStatus = _routeStatus(firstHalfLength, minRouteLength, maxRouteLength);
        final secondHalfStatus = _routeStatus(secondHalfLength, minRouteLength, maxRouteLength);

        if (members.length == 1) {
          // בדד מאבטח — מקבל חצי ציר ראשון בלבד (start → swap)
          expandedRoutes[members[0]] = domain.AssignedRoute(
            checkpointIds: firstResult.checkpointIds,
            routeLengthKm: firstResult.routeLengthKm,
            sequence: firstResult.sequence,
            startPointId: route.startPointId,
            endPointId: swapId,
            waypointIds: firstResult.waypointIds,
            status: firstHalfStatus,
            groupId: groupId,
            segmentType: 'first_half',
            swapPointId: swapId,
          );
        } else {
          // מנווט ראשון: first_half
          expandedRoutes[members[0]] = domain.AssignedRoute(
            checkpointIds: firstResult.checkpointIds,
            routeLengthKm: firstResult.routeLengthKm,
            sequence: firstResult.sequence,
            startPointId: route.startPointId,
            endPointId: swapId,
            waypointIds: firstResult.waypointIds,
            status: firstHalfStatus,
            groupId: groupId,
            segmentType: 'first_half',
            swapPointId: swapId,
          );

          // מנווט שני ואילך: second_half
          for (int i = 1; i < members.length; i++) {
            expandedRoutes[members[i]] = domain.AssignedRoute(
              checkpointIds: secondResult.checkpointIds,
              routeLengthKm: secondResult.routeLengthKm,
              sequence: secondResult.sequence,
              startPointId: swapId,
              endPointId: route.endPointId,
              waypointIds: secondResult.waypointIds,
              status: secondHalfStatus,
              groupId: groupId,
              segmentType: 'second_half',
              swapPointId: swapId,
            );
          }
        }
      }
    } else {
      // --- צמד / חוליה: כל חבר בקבוצה מקבל אותו ציר ---
      // copyWith() יוצר אובייקט חדש (AssignedRoute הוא immutable Equatable) — בטוח לשיתוף
      for (final entry in result.routes.entries) {
        final groupId = entry.key;
        final route = entry.value;
        final members = groups[groupId];
        if (members == null) continue;

        for (final memberId in members) {
          expandedRoutes[memberId] = route.copyWith(groupId: groupId);
        }
      }
    }

    // עדכון forceComposition עם הקבוצות הסופיות
    final updatedComposition = composition.copyWith(manualGroups: groups);

    // מאבטח ללא נקודת חלוקה — דרוש בחירה ידנית
    if (composition.isGuard && expandedRoutes.values.any((r) => r.swapPointId == null)) {
      return domain.DistributionResult(
        status: 'needs_swap_point',
        routes: expandedRoutes,
        approvalOptions: const [
          domain.ApprovalOption(
            type: 'needs_swap_point',
            label: 'יש לבחור נקודת חלוקה',
          ),
        ],
        hasSharedCheckpoints: result.hasSharedCheckpoints,
        sharedCheckpointCount: result.sharedCheckpointCount,
        forceComposition: updatedComposition,
      );
    }

    // חישוב סטטוס כולל מחדש לפי הצירים המורחבים
    final allOptimal = expandedRoutes.values.every((r) => r.status == 'optimal');
    final expandedStatus = allOptimal ? result.status : 'needs_approval';

    // יצירת אפשרויות אישור חדשות כשיש צירים חורגים (Bug A fix)
    List<domain.ApprovalOption> expandedApprovalOptions;
    if (!allOptimal) {
      final outOfRangeCount = expandedRoutes.values.where((r) => r.status != 'optimal').length;
      expandedApprovalOptions = [
        domain.ApprovalOption(
          type: 'expand_range',
          label: 'הרחב טווח ל-${(minRouteLength * 0.8).toStringAsFixed(1)} — ${(maxRouteLength * 1.2).toStringAsFixed(1)} ק"מ',
          expandedMin: minRouteLength * 0.8,
          expandedMax: maxRouteLength * 1.2,
        ),
        domain.ApprovalOption(
          type: 'accept_best',
          label: 'אשר חלוקה ($outOfRangeCount צירים חורגים)',
          outOfRangeCount: outOfRangeCount,
        ),
      ];
    } else {
      expandedApprovalOptions = result.approvalOptions;
    }

    return domain.DistributionResult(
      status: expandedStatus,
      routes: expandedRoutes,
      approvalOptions: expandedApprovalOptions,
      hasSharedCheckpoints: result.hasSharedCheckpoints,
      sharedCheckpointCount: result.sharedCheckpointCount,
      forceComposition: updatedComposition,
    );
  }

  UserRepository? _lazyUserRepository;
  UserRepository get _userRepository =>
      _injectedUserRepository ?? (_lazyUserRepository ??= UserRepository());

  /// מציאת משתתפים — מנווטים בלבד (ללא מפקדים/מנהלים)
  Future<List<String>> _findNavigators(domain.Navigation navigation, NavigationTree tree) async {
    // 1. אם נבחרו משתתפים ספציפיים — סינון לפי תפקיד
    if (navigation.selectedParticipantIds.isNotEmpty) {
      final navigators = <String>[];
      for (final uid in navigation.selectedParticipantIds) {
        final user = await _userRepository.getUser(uid);
        if (user != null && user.role == 'navigator') {
          navigators.add(uid);
        }
      }
      return navigators;
    }

    final unitId = navigation.selectedUnitId ?? tree.unitId;
    if (unitId == null) return [];

    // 2. אם נבחרו תתי-מסגרות — דילוג על מסגרות מפקדים, שליפת מנווטים בלבד
    if (navigation.selectedSubFrameworkIds.isNotEmpty) {
      final navigatorSet = <String>{};
      for (final sf in tree.subFrameworks) {
        if (!navigation.selectedSubFrameworkIds.contains(sf.id)) continue;
        // דילוג על תת-מסגרות קבועות (מפקדים/מנהלת) — מפקדים לא מקבלים צירים
        if (sf.isFixed) continue;
        // שימוש ב-userIds של התת-מסגרת (לא כל היחידה)
        if (sf.userIds.isNotEmpty) {
          // סינון נוסף: רק מנווטים (הגנה כפולה)
          for (final uid in sf.userIds) {
            final user = await _userRepository.getUser(uid);
            if (user != null && user.role == 'navigator') {
              navigatorSet.add(uid);
            }
          }
        } else {
          // fallback: אם אין userIds בתת-מסגרת — שליפה מהיחידה
          final users = await _userRepository.getNavigatorsForUnit(unitId);
          navigatorSet.addAll(users.map((u) => u.uid));
        }
      }
      return navigatorSet.toList();
    }

    // 3. fallback — כל המנווטים ביחידה
    final navigators = await _userRepository.getNavigatorsForUnit(unitId);
    return navigators.map((u) => u.uid).toList();
  }

  /// הרצת האלגוריתם ב-Isolate עם progress reporting
  Future<domain.DistributionResult> _runInIsolate({
    required List<String> navigators,
    required List<Map<String, dynamic>> checkpointMaps,
    String? startPointId,
    String? endPointId,
    required List<Map<String, dynamic>> waypointMaps,
    required String executionOrder,
    required int checkpointsPerNavigator,
    required double minRouteLength,
    required double maxRouteLength,
    required String scoringCriterion,
    void Function(int current, int total)? onProgress,
    bool isGuard = false,
    String? swapPointId,
    List<List<double>>? boundaryCoords,
    List<List<List<double>>>? safetyPolygons,
  }) async {
    final receivePort = ReceivePort();
    const maxIterations = 1000;

    final params = _DistributionParams(
      navigators: navigators,
      checkpointMaps: checkpointMaps,
      startPointId: startPointId,
      endPointId: endPointId,
      waypointMaps: waypointMaps,
      executionOrder: executionOrder,
      checkpointsPerNavigator: checkpointsPerNavigator,
      minRouteLength: minRouteLength,
      maxRouteLength: maxRouteLength,
      scoringCriterion: scoringCriterion,
      maxIterations: maxIterations,
      progressPort: receivePort.sendPort,
      isGuard: isGuard,
      swapPointId: swapPointId,
      boundaryCoords: boundaryCoords,
      safetyPolygons: safetyPolygons,
    );

    // הרצה ב-Isolate עם error handling
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _isolateWorker,
      params,
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    Map<String, dynamic>? resultData;
    String? isolateError;

    // מאזין למסרי error/exit מה-isolate
    errorPort.listen((message) {
      isolateError = message.toString();
      receivePort.close(); // שובר את ה-await for
    });
    exitPort.listen((_) {
      receivePort.close(); // שובר את ה-await for אם ה-isolate מת
    });

    await for (final message in receivePort) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String;
        if (type == 'progress') {
          onProgress?.call(
            message['current'] as int,
            message['total'] as int,
          );
        } else if (type == 'result') {
          resultData = message;
          break;
        } else if (type == 'error') {
          isolateError = message['message'] as String?;
          break;
        }
      }
    }

    receivePort.close();
    errorPort.close();
    exitPort.close();
    isolate.kill(priority: Isolate.immediate);

    if (isolateError != null) {
      throw Exception('שגיאה בחלוקה: $isolateError');
    }
    if (resultData == null) {
      throw Exception('שגיאה בחלוקה אוטומטית');
    }

    // המרת תוצאה ל-DistributionResult
    return _parseIsolateResult(resultData, navigators, startPointId, endPointId,
      minRouteLength, maxRouteLength, checkpointsPerNavigator);
  }

  /// Worker function שרץ ב-Isolate
  static void _isolateWorker(_DistributionParams params) {
    final port = params.progressPort;
    try {
    _isolateWorkerInner(params);
    } catch (e, st) {
      port.send({'type': 'error', 'message': e.toString(), 'stack': st.toString()});
    }
  }

  static void _isolateWorkerInner(_DistributionParams params) {
    final port = params.progressPort;
    final random = Random();

    // המרת נתונים
    final checkpoints = params.checkpointMaps.map((m) => _SimpleCheckpoint.fromMap(m)).toList();
    final waypoints = params.waypointMaps.map((m) => _SimpleWaypoint.fromMap(m)).toList();
    final navigators = params.navigators;
    final K = params.checkpointsPerNavigator;
    final N = navigators.length;

    // מציאת נקודות התחלה/סיום/החלפה
    final startCp = params.startPointId != null
        ? checkpoints.where((cp) => cp.id == params.startPointId).firstOrNull
        : null;
    final endCp = params.endPointId != null
        ? checkpoints.where((cp) => cp.id == params.endPointId).firstOrNull
        : null;
    final swapCp = params.swapPointId != null
        ? checkpoints.where((cp) => cp.id == params.swapPointId).firstOrNull
        : null;

    // סינון נקודות התחלה/סיום/waypoints מהפול — waypoints הם חובה כמו התחלה/סיום
    final waypointCpIds = waypoints.map((wp) => wp.checkpointId).toSet();
    final pool = checkpoints
        .where((cp) => cp.id != params.startPointId && cp.id != params.endPointId && !waypointCpIds.contains(cp.id))
        .toList();

    // Phase 1: בניית מטריצת מרחקים פעם אחת — כל הנקודות הייחודיות
    final allPoints = <_SimpleCheckpoint>[];
    final seenIds = <String>{};
    for (final cp in checkpoints) {
      if (seenIds.add(cp.id)) allPoints.add(cp);
    }
    final distMatrix = _buildDistanceMatrix(allPoints);

    // בניית מטריצת הפרות גיאומטריות (nullable — מדולג כשאין גבול/נת"בים)
    final Map<String, Map<String, _SegmentViolation>>? violationMatrix =
        (params.boundaryCoords != null || params.safetyPolygons != null)
            ? _buildSegmentViolationMatrix(allPoints, params.boundaryCoords, params.safetyPolygons)
            : null;

    final bool needsSharing = pool.length < N * K;
    final bool isDoubleCheck = params.scoringCriterion == 'doubleCheck';

    // --- שלב 2: חיפוש Monte Carlo (ייחודי) ---
    _InternalDistribution? bestDistribution;

    // doubleCheck: מריץ גם ייחודי וגם שיתוף — שני השלבים תמיד
    if (!needsSharing) {
      bestDistribution = _targetLengthWithSA(
        pool: pool,
        navigators: navigators,
        K: K,
        startCp: startCp,
        endCp: endCp,
        waypoints: waypoints,
        allCheckpoints: checkpoints,
        minRoute: params.minRouteLength,
        maxRoute: params.maxRouteLength,
        criterion: params.scoringCriterion,
        executionOrder: params.executionOrder,
        maxIterations: params.maxIterations,
        random: random,
        port: port,
        allowSharing: false,
        iterationOffset: 0,
        distMatrix: distMatrix,
        isGuard: params.isGuard,
        swapCp: swapCp,
        violationMatrix: violationMatrix,
      );
    }

    // --- שלב 2.5: שיתוף נקודות — fallback או חובה ב-doubleCheck ---
    if (bestDistribution == null || !bestDistribution.allInRange || isDoubleCheck) {
      final sharedResult = _targetLengthWithSA(
        pool: pool,
        navigators: navigators,
        K: K,
        startCp: startCp,
        endCp: endCp,
        waypoints: waypoints,
        allCheckpoints: checkpoints,
        minRoute: params.minRouteLength,
        maxRoute: params.maxRouteLength,
        criterion: params.scoringCriterion,
        executionOrder: params.executionOrder,
        maxIterations: needsSharing ? params.maxIterations : (params.maxIterations ~/ 2),
        random: random,
        port: port,
        allowSharing: true,
        iterationOffset: needsSharing ? 0 : params.maxIterations,
        distMatrix: distMatrix,
        isGuard: params.isGuard,
        swapCp: swapCp,
        violationMatrix: violationMatrix,
      );

      // העדפת תוצאה טובה יותר
      if (bestDistribution == null ||
          sharedResult.score > bestDistribution.score) {
        bestDistribution = sharedResult;
      }
    }

    // ולידציית K-invariant סופית לפני שליחה
    assert(_validKInvariant(bestDistribution.routes, K),
        'K-invariant broken before sending isolate result');

    // שליחת תוצאה
    final routesData = <String, Map<String, dynamic>>{};
    for (final entry in bestDistribution.routes.entries) {
      routesData[entry.key] = {
        'checkpointIds': entry.value.checkpointIds,
        'sequence': entry.value.sequence,
        'waypointIds': entry.value.waypointIds,
        'routeLengthKm': entry.value.routeLengthKm,
        'inRange': entry.value.inRange,
      };
    }

    port.send({
      'type': 'result',
      'routes': routesData,
      'allInRange': bestDistribution.allInRange,
      'score': bestDistribution.score,
      'hasSharedCheckpoints': bestDistribution.hasSharedCheckpoints,
      'sharedCount': bestDistribution.sharedCount,
    });
  }

  /// אלגוריתם משופר: בניית ציר לפי אורך יעד + Simulated Annealing
  static _InternalDistribution _targetLengthWithSA({
    required List<_SimpleCheckpoint> pool,
    required List<String> navigators,
    required int K,
    required _SimpleCheckpoint? startCp,
    required _SimpleCheckpoint? endCp,
    required List<_SimpleWaypoint> waypoints,
    required List<_SimpleCheckpoint> allCheckpoints,
    required double minRoute,
    required double maxRoute,
    required String criterion,
    required String executionOrder,
    required int maxIterations,
    required Random random,
    required SendPort port,
    required bool allowSharing,
    required int iterationOffset,
    required Map<String, Map<String, double>> distMatrix,
    bool isGuard = false,
    _SimpleCheckpoint? swapCp,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  }) {
    _InternalDistribution? best;
    final targetLength = (minRoute + maxRoute) / 2;

    // 500 בניות התחלתיות × SA על כל אחת (חיפוש מקיף)
    final constructionRounds = min(500, maxIterations);
    final saStepsPerRound = 800;

    for (int iter = 0; iter < constructionRounds; iter++) {
      // דיווח התקדמות
      if (iter % 2 == 0) {
        port.send({
          'type': 'progress',
          'current': iterationOffset + (iter * maxIterations ~/ constructionRounds),
          'total': iterationOffset + maxIterations,
        });
      }

      // שלב 1: בניית פתרון התחלתי לפי אורך יעד
      // ג'יטר ±15% ליצירת מגוון בין איטרציות
      final jitter = 1.0 + (random.nextDouble() - 0.5) * 0.3;
      final iterTarget = targetLength * jitter;

      final initialSolution = _constructTargetLengthSolution(
        pool: pool,
        navigators: navigators,
        K: K,
        startCp: startCp,
        endCp: endCp,
        waypoints: waypoints,
        allCheckpoints: allCheckpoints,
        targetLength: iterTarget,
        minRoute: minRoute,
        maxRoute: maxRoute,
        executionOrder: executionOrder,
        random: random,
        allowSharing: allowSharing,
        distMatrix: distMatrix,
        violationMatrix: violationMatrix,
      );

      if (initialSolution == null) continue;

      // שלב 2: Simulated Annealing — אופטימיזציה לפי הקריטריון
      final optimized = _simulatedAnnealing(
        initial: initialSolution,
        navigators: navigators,
        K: K,
        startCp: startCp,
        endCp: endCp,
        waypoints: waypoints,
        allCheckpoints: allCheckpoints,
        minRoute: minRoute,
        maxRoute: maxRoute,
        criterion: criterion,
        executionOrder: executionOrder,
        random: random,
        steps: saStepsPerRound,
        allowSharing: allowSharing,
        pool: pool,
        distMatrix: distMatrix,
        isGuard: isGuard,
        swapCp: swapCp,
        violationMatrix: violationMatrix,
      );

      // ולידציית K: דילוג על פתרון שבור
      final validK = optimized.values.every((r) => r.checkpointIds.length == K);
      if (!validK) continue;

      // ניקוד
      final allCpIds = optimized.values.expand((r) => r.checkpointIds).toList();
      final uniqueCpIds = allCpIds.toSet();
      final hasSharing = allCpIds.length != uniqueCpIds.length;
      final sharedCount = hasSharing ? allCpIds.length - uniqueCpIds.length : 0;
      final allInRange = optimized.values.every((r) => r.inRange);

      final score = _scoreDistribution(
        distribution: optimized,
        criterion: criterion,
        minRoute: minRoute,
        maxRoute: maxRoute,
        allInRange: allInRange,
        hasSharing: hasSharing,
        totalUniqueCheckpoints: uniqueCpIds.length,
        isGuard: isGuard,
        violationMatrix: violationMatrix,
      );

      final result = _InternalDistribution(
        routes: optimized,
        score: score,
        allInRange: allInRange,
        hasSharedCheckpoints: hasSharing,
        sharedCount: sharedCount,
      );

      if (best == null || score > best.score) {
        best = result;
      }

      // early exit: תוצאה מושלמת — שונות נמוכה + הכל בטווח
      // סף דינמי: 1% מריבוע טווח אורך המסלול (מתאים לטווחים שונים)
      if (allInRange && !hasSharing) {
        final routeLengths = optimized.values.map((r) => r.routeLengthKm).toList();
        final meanLen = routeLengths.reduce((a, b) => a + b) / routeLengths.length;
        final varianceLen = routeLengths.map((l) => (l - meanLen) * (l - meanLen)).reduce((a, b) => a + b) / routeLengths.length;
        final rangeSpan = maxRoute - minRoute;
        final earlyExitThreshold = max(0.001, 0.01 * rangeSpan * rangeSpan);
        if (varianceLen < earlyExitThreshold) break;
      }

      // --- Multi-start restart (רופיש 6): כל 100 סיבובים, SA נוסף מהפתרון הטוב ביותר ---
      if (iter > 0 && iter % 100 == 0 && best != null) {
        final restartSA = _simulatedAnnealing(
          initial: best.routes,
          navigators: navigators,
          K: K,
          startCp: startCp,
          endCp: endCp,
          waypoints: waypoints,
          allCheckpoints: allCheckpoints,
          minRoute: minRoute,
          maxRoute: maxRoute,
          criterion: criterion,
          executionOrder: executionOrder,
          random: random,
          steps: saStepsPerRound,
          allowSharing: allowSharing,
          pool: pool,
          distMatrix: distMatrix,
          isGuard: isGuard,
          swapCp: swapCp,
          violationMatrix: violationMatrix,
        );

        // ולידציית K על restart SA
        final restartValidK = restartSA.values.every((r) => r.checkpointIds.length == K);
        if (!restartValidK) continue;

        final restartAllCpIds = restartSA.values.expand((r) => r.checkpointIds).toList();
        final restartUniqueCpIds = restartAllCpIds.toSet();
        final restartHasSharing = restartAllCpIds.length != restartUniqueCpIds.length;
        final restartAllInRange = restartSA.values.every((r) => r.inRange);

        final restartScore = _scoreDistribution(
          distribution: restartSA,
          criterion: criterion,
          minRoute: minRoute,
          maxRoute: maxRoute,
          allInRange: restartAllInRange,
          hasSharing: restartHasSharing,
          totalUniqueCheckpoints: restartUniqueCpIds.length,
          isGuard: isGuard,
          violationMatrix: violationMatrix,
        );

        if (restartScore > best.score) {
          best = _InternalDistribution(
            routes: restartSA,
            score: restartScore,
            allInRange: restartAllInRange,
            hasSharedCheckpoints: restartHasSharing,
            sharedCount: restartHasSharing ? restartAllCpIds.length - restartUniqueCpIds.length : 0,
          );
        }
      }
    }

    // progress סופי
    port.send({
      'type': 'progress',
      'current': iterationOffset + maxIterations,
      'total': iterationOffset + maxIterations,
    });

    if (best == null) {
      best = _createFallbackDistribution(
        pool: pool,
        navigators: navigators,
        K: K,
        startCp: startCp,
        endCp: endCp,
        waypoints: waypoints,
        allCheckpoints: allCheckpoints,
        minRoute: minRoute,
        maxRoute: maxRoute,
        executionOrder: executionOrder,
        distMatrix: distMatrix,
        violationMatrix: violationMatrix,
      );
    }

    return best;
  }

  /// בניית פתרון התחלתי לפי אורך יעד — בחירת נקודות גיאוגרפית
  static Map<String, _RouteResult>? _constructTargetLengthSolution({
    required List<_SimpleCheckpoint> pool,
    required List<String> navigators,
    required int K,
    required _SimpleCheckpoint? startCp,
    required _SimpleCheckpoint? endCp,
    required List<_SimpleWaypoint> waypoints,
    required List<_SimpleCheckpoint> allCheckpoints,
    required double targetLength,
    required double minRoute,
    required double maxRoute,
    required String executionOrder,
    required Random random,
    required bool allowSharing,
    required Map<String, Map<String, double>> distMatrix,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  }) {
    final N = navigators.length;
    final usedGlobally = <String>{};
    final distribution = <String, _RouteResult>{};

    // סדר אקראי של מנווטים למניעת הטיה למנווט הראשון
    final navOrder = List.generate(N, (i) => i)..shuffle(random);

    // Phase 3: חלוקה גיאוגרפית — כל מנווט מקבל אזור משלו
    final partitions = _geographicPartition(pool, N, random);

    for (int idx = 0; idx < navOrder.length; idx++) {
      final navIdx = navOrder[idx];

      List<_SimpleCheckpoint> candidatePool;
      if (allowSharing) {
        // עם שיתוף: נקודות מהמחיצה בעדיפות, אחר כך השאר
        final partition = idx < partitions.length ? partitions[idx] : <_SimpleCheckpoint>[];
        final partitionIds = partition.map((cp) => cp.id).toSet();
        final rest = pool.where((cp) => !partitionIds.contains(cp.id)).toList();
        candidatePool = [...partition, ...rest];
      } else {
        // ללא שיתוף: מחיצה + השלמה ממחיצות אחרות
        final partition = idx < partitions.length
            ? partitions[idx].where((cp) => !usedGlobally.contains(cp.id)).toList()
            : <_SimpleCheckpoint>[];
        candidatePool = List.from(partition);
        if (candidatePool.length < K) {
          final remaining = pool.where((cp) =>
              !usedGlobally.contains(cp.id) &&
              !candidatePool.any((p) => p.id == cp.id)).toList();
          candidatePool.addAll(remaining);
        }
      }

      if (candidatePool.length < K && !allowSharing) {
        return null;
      }

      // בניית ציר בודד לפי אורך יעד
      final chunk = _constructSingleRoute(
        candidatePool: candidatePool,
        K: K,
        startCp: startCp,
        endCp: endCp,
        targetLength: targetLength,
        random: random,
        distMatrix: distMatrix,
        violationMatrix: violationMatrix,
      );

      if (chunk.length < K) return null;

      if (!allowSharing) {
        for (final cp in chunk) {
          usedGlobally.add(cp.id);
        }
      }

      // אופטימיזציית רצף (כולל הכנסת waypoints)
      final sequence = _optimizeSequence(chunk, startCp, endCp, executionOrder, distMatrix, waypoints, allCheckpoints, violationMatrix);

      // בניית ציר מלא עם waypoints
      final fullResult = _buildRouteWithWaypoints(
        chunk: chunk,
        sequence: sequence,
        startCp: startCp,
        endCp: endCp,
        waypoints: waypoints,
        allCheckpoints: allCheckpoints,
        distMatrix: distMatrix,
      );

      final routeLength = fullResult['length'] as double;
      final waypointIds = fullResult['waypointIds'] as List<String>;
      final inRange = routeLength >= minRoute && routeLength <= maxRoute;

      final violations = violationMatrix != null
          ? _countSequenceViolations(
              sequence.map((cp) => cp.id).toList(), startCp?.id, endCp?.id, violationMatrix)
          : (boundaryExits: 0, safetyIntersections: 0);

      distribution[navigators[navIdx]] = _RouteResult(
        checkpointIds: chunk.map((cp) => cp.id).toList(),
        sequence: sequence.map((cp) => cp.id).toList(),
        waypointIds: waypointIds,
        routeLengthKm: routeLength,
        inRange: inRange,
        boundaryExits: violations.boundaryExits,
        safetyIntersections: violations.safetyIntersections,
      );
    }

    return distribution;
  }

  /// חלוקה גיאוגרפית — K-Means clustering (10 איטרציות) + איזון דליים ריקים
  static List<List<_SimpleCheckpoint>> _geographicPartition(
    List<_SimpleCheckpoint> pool,
    int N,
    Random random,
  ) {
    if (N <= 0 || pool.isEmpty) return [];
    if (N == 1) return [List.from(pool)];

    // K-Means initialization: בחירת N מרכזים אקראיים מהפול
    final shuffled = List<_SimpleCheckpoint>.from(pool)..shuffle(random);
    var centroids = shuffled.take(N).map((c) => [c.lat, c.lng]).toList();

    var buckets = List.generate(N, (_) => <_SimpleCheckpoint>[]);

    for (int iter = 0; iter < 10; iter++) {
      buckets = List.generate(N, (_) => <_SimpleCheckpoint>[]);

      // שיוך כל נקודה למרכז הקרוב ביותר
      for (final cp in pool) {
        int bestCluster = 0;
        double bestDist = double.infinity;
        for (int c = 0; c < N; c++) {
          final d = _haversine(cp.lat, cp.lng, centroids[c][0], centroids[c][1]);
          if (d < bestDist) { bestDist = d; bestCluster = c; }
        }
        buckets[bestCluster].add(cp);
      }

      // עדכון מרכזים
      for (int c = 0; c < N; c++) {
        if (buckets[c].isEmpty) continue;
        centroids[c] = [
          buckets[c].map((p) => p.lat).reduce((a, b) => a + b) / buckets[c].length,
          buckets[c].map((p) => p.lng).reduce((a, b) => a + b) / buckets[c].length,
        ];
      }
    }

    // איזון: אם יש דלי ריק, העבר מדלי גדול
    bool balanced = false;
    while (!balanced) {
      balanced = true;
      final emptyBuckets = <int>[];
      int largestIdx = 0;
      for (int i = 0; i < N; i++) {
        if (buckets[i].isEmpty) emptyBuckets.add(i);
        if (buckets[i].length > buckets[largestIdx].length) largestIdx = i;
      }
      for (final emptyIdx in emptyBuckets) {
        if (buckets[largestIdx].length > 1) {
          buckets[emptyIdx].add(buckets[largestIdx].removeLast());
          balanced = false;
        }
      }
    }

    // ערבוב סדר הדליים
    buckets.shuffle(random);

    return buckets;
  }

  /// בניית ציר בודד: בחירת K נקודות לפי מרחק יעד מצטבר + Boltzmann selection
  static List<_SimpleCheckpoint> _constructSingleRoute({
    required List<_SimpleCheckpoint> candidatePool,
    required int K,
    required _SimpleCheckpoint? startCp,
    required _SimpleCheckpoint? endCp,
    required double targetLength,
    required Random random,
    required Map<String, Map<String, double>> distMatrix,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  }) {
    final route = <_SimpleCheckpoint>[];
    final remaining = List<_SimpleCheckpoint>.from(candidatePool);

    // חישוב מספר קטעים: start → cp1 → ... → cpK → end
    final totalSegments = K - 1 + (startCp != null ? 1 : 0) + (endCp != null ? 1 : 0);
    var idealSegment = totalSegments > 0 ? targetLength / totalSegments : 0.5;

    // מעקב אחר נקודה נוכחית לפי ID לשימוש במטריצת מרחקים
    var currentId = startCp?.id ?? (remaining.isNotEmpty ? remaining.first.id : null);

    for (int j = 0; j < K; j++) {
      if (remaining.isEmpty) break;

      // ניקוד כל מועמד לפי קרבה למרחק היעד + penalty על הפרות גבול
      final scored = <MapEntry<_SimpleCheckpoint, double>>[];
      for (final cp in remaining) {
        final dist = currentId != null
            ? _dist(currentId, cp.id, distMatrix)
            : 0.0;
        final diff = (dist - idealSegment).abs();

        // boundary violation penalty
        double violationPenalty = 0;
        if (violationMatrix != null && currentId != null) {
          final v = violationMatrix[currentId]?[cp.id];
          if (v != null && v.exitsBoundary) {
            violationPenalty = 100.0; // הרבה יותר גדול מ-diff טיפוסי (~0-2 km)
          }
        }

        scored.add(MapEntry(cp, diff + violationPenalty));
      }

      // מיון לפי קרבה למרחק אידיאלי
      scored.sort((a, b) => a.value.compareTo(b.value));

      // Phase 6: Boltzmann selection מתוך 10 מועמדים — τ אדפטיבי לפי מרחק היעד
      final topN = min(10, scored.length);
      final candidates = scored.sublist(0, topN);
      final bestDiff = candidates.first.value;
      final boltzmannTau = max(0.05, idealSegment * 0.15);
      final weights = candidates.map((e) => exp(-(e.value - bestDiff) / boltzmannTau)).toList();
      final totalWeight = weights.reduce((a, b) => a + b);
      var roll = random.nextDouble() * totalWeight;
      _SimpleCheckpoint pick = candidates.first.key;
      for (int k = 0; k < candidates.length; k++) {
        roll -= weights[k];
        if (roll <= 0) {
          pick = candidates[k].key;
          break;
        }
      }

      route.add(pick);
      remaining.removeWhere((cp) => cp.id == pick.id);
      currentId = pick.id;

      // עדכון מרחק יעד לקטעים הנותרים
      if (j < K - 1) {
        double usedLength = 0;
        var prevId = startCp?.id ?? route.first.id;
        for (final cp in route) {
          usedLength += _dist(prevId, cp.id, distMatrix);
          prevId = cp.id;
        }

        final remainingLength = targetLength - usedLength;
        final remainingSegments = (K - j - 1) + (endCp != null ? 1 : 0);
        idealSegment = remainingSegments > 0 ? remainingLength / remainingSegments : 0.1;
        if (idealSegment < 0) idealSegment = 0.1;
      }
    }

    // Fallback מודע-גבול: השלמה מ-candidatePool — מיון לפי crossings + מרחק
    if (route.length < K) {
      final usedIds = route.map((c) => c.id).toSet();
      final leftover = candidatePool.where((c) => !usedIds.contains(c.id)).toList();

      if (violationMatrix != null && route.isNotEmpty) {
        final lastId = route.last.id;
        leftover.sort((a, b) {
          final va = violationMatrix[lastId]?[a.id];
          final vb = violationMatrix[lastId]?[b.id];
          final aCrossings = (va != null && va.exitsBoundary) ? va.boundaryCrossings : 0;
          final bCrossings = (vb != null && vb.exitsBoundary) ? vb.boundaryCrossings : 0;
          if (aCrossings != bCrossings) return aCrossings.compareTo(bCrossings);
          return _dist(lastId, a.id, distMatrix).compareTo(_dist(lastId, b.id, distMatrix));
        });
      }

      for (final cp in leftover) {
        if (route.length >= K) break;
        route.add(cp);
      }
    }

    return route;
  }

  /// ולידציה: כל ציר מכיל בדיוק K נקודות
  static bool _isValidKSolution(Map<String, List<_SimpleCheckpoint>> routeChunks, int K) {
    return routeChunks.values.every((r) => r.length == K);
  }

  /// ולידציית K-invariant על תוצאות סופיות (_RouteResult)
  static bool _validKInvariant(Map<String, _RouteResult> routes, int K) {
    for (final route in routes.values) {
      if (route.checkpointIds.length != K) return false;
    }
    return true;
  }

  /// ולידציה: סך הנקודות המוקצות + freePool = סך הנקודות הכולל (ללא שיתוף)
  static bool _isConserved(
    Map<String, List<_SimpleCheckpoint>> routeChunks,
    Set<String> freePool,
    int totalPoolSize,
  ) {
    final totalAssigned = routeChunks.values.expand((r) => r).map((c) => c.id).toSet().length;
    return totalAssigned + freePool.length == totalPoolSize;
  }

  /// Simulated Annealing — 5 סוגי מהלכים + auto-calibrate + reheat
  static Map<String, _RouteResult> _simulatedAnnealing({
    required Map<String, _RouteResult> initial,
    required List<String> navigators,
    required int K,
    required _SimpleCheckpoint? startCp,
    required _SimpleCheckpoint? endCp,
    required List<_SimpleWaypoint> waypoints,
    required List<_SimpleCheckpoint> allCheckpoints,
    required double minRoute,
    required double maxRoute,
    required String criterion,
    required String executionOrder,
    required Random random,
    required int steps,
    required bool allowSharing,
    required List<_SimpleCheckpoint> pool,
    required Map<String, Map<String, double>> distMatrix,
    bool isGuard = false,
    _SimpleCheckpoint? swapCp,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  }) {
    if (navigators.length < 2) return Map.from(initial);

    // בניית מפת נקודות לפי ID
    final cpMap = <String, _SimpleCheckpoint>{};
    for (final cp in pool) cpMap[cp.id] = cp;
    for (final cp in allCheckpoints) cpMap[cp.id] = cp;
    if (startCp != null) cpMap[startCp.id] = startCp;
    if (endCp != null) cpMap[endCp.id] = endCp;

    // בניית רשימות נקודות מוטביליות לכל מנווט
    final routeChunks = <String, List<_SimpleCheckpoint>>{};
    for (final nav in navigators) {
      if (initial[nav] == null) continue;
      routeChunks[nav] = initial[nav]!.checkpointIds
          .map((id) => cpMap[id])
          .where((cp) => cp != null)
          .cast<_SimpleCheckpoint>()
          .toList();
    }

    var currentRoutes = Map<String, _RouteResult>.from(initial);

    // Guard-aware route evaluation: פיצול לחצאים + NN עצמאי לכל חצי
    _RouteResult evalLight(List<_SimpleCheckpoint> chunk) {
      if (isGuard && swapCp != null) {
        return _evaluateGuardRoute(chunk, startCp, endCp, swapCp, waypoints, allCheckpoints, minRoute, maxRoute, distMatrix, violationMatrix);
      }
      return _rebuildRouteLight(chunk, startCp, endCp, waypoints, allCheckpoints, minRoute, maxRoute, distMatrix, violationMatrix);
    }
    _RouteResult evalFull(List<_SimpleCheckpoint> chunk) {
      if (isGuard && swapCp != null) {
        // Full rebuild: פיצול + NN+2-opt לכל חצי
        final halfMin = minRoute / 2;
        final halfMax = maxRoute / 2;
        final halves = _splitGuardCheckpoints(chunk, startCp, endCp, swapCp, distMatrix);
        final first = _rebuildRoute(halves[0], startCp, swapCp, const [], allCheckpoints, executionOrder, halfMin, halfMax, distMatrix, violationMatrix);
        final second = _rebuildRoute(halves[1], swapCp, endCp, const [], allCheckpoints, executionOrder, halfMin, halfMax, distMatrix, violationMatrix);
        final combinedLength = first.routeLengthKm + second.routeLengthKm;
        return _RouteResult(
          checkpointIds: [...first.checkpointIds, ...second.checkpointIds],
          sequence: [...first.sequence, ...second.sequence],
          waypointIds: [...first.waypointIds, ...second.waypointIds],
          routeLengthKm: combinedLength,
          inRange: first.inRange && second.inRange,
          firstHalfLengthKm: first.routeLengthKm,
          secondHalfLengthKm: second.routeLengthKm,
          boundaryExits: first.boundaryExits + second.boundaryExits,
          safetyIntersections: first.safetyIntersections + second.safetyIntersections,
        );
      }
      return _rebuildRoute(chunk, startCp, endCp, waypoints, allCheckpoints, executionOrder, minRoute, maxRoute, distMatrix, violationMatrix);
    }

    var currentScore = _calculateFullScore(currentRoutes, criterion, minRoute, maxRoute, isGuard: isGuard, violationMatrix: violationMatrix);

    // בניית free pool — נקודות שלא בשום ציר
    final freePool = <String>{};
    if (!allowSharing) {
      final usedIds = routeChunks.values.expand((r) => r.map((c) => c.id)).toSet();
      for (final cp in pool) {
        if (!usedIds.contains(cp.id)) freePool.add(cp.id);
      }
    }

    // --- כיול אוטומטי של טמפרטורה (רופיש 5) ---
    // דגימת 20 מהלכי SWAP אקראיים למדידת דלתות טיפוסיות
    final calibrationDeltas = <double>[];
    for (int c = 0; c < 20 && navigators.length >= 2; c++) {
      final i1 = random.nextInt(navigators.length);
      var i2 = random.nextInt(navigators.length - 1);
      if (i2 >= i1) i2++;
      final nav1 = navigators[i1], nav2 = navigators[i2];
      final r1 = routeChunks[nav1], r2 = routeChunks[nav2];
      if (r1 == null || r2 == null || r1.isEmpty || r2.isEmpty) continue;
      final ci1 = random.nextInt(r1.length), ci2 = random.nextInt(r2.length);
      if (r1[ci1].id == r2[ci2].id) continue;
      final old1 = r1[ci1], old2 = r2[ci2];
      r1[ci1] = old2; r2[ci2] = old1;
      final testR = Map<String, _RouteResult>.from(currentRoutes);
      testR[nav1] = evalFull(r1);
      testR[nav2] = evalFull(r2);
      final delta = (_calculateFullScore(testR, criterion, minRoute, maxRoute, isGuard: isGuard, violationMatrix: violationMatrix) - currentScore).abs();
      if (delta > 0) calibrationDeltas.add(delta);
      r1[ci1] = old1; r2[ci2] = old2; // undo
    }
    // טמפרטורה התחלתית = median של הדלתות (כך SA מקבל ~50% מהלכים גרועים בהתחלה)
    // רצפה דינמית — מבוססת על טווח אורכי המסלולים
    final dynamicFloor = max(0.01, (maxRoute - minRoute) * 0.05);
    double startTemperature = dynamicFloor;
    if (calibrationDeltas.isNotEmpty) {
      calibrationDeltas.sort();
      startTemperature = calibrationDeltas[calibrationDeltas.length ~/ 2];
      if (startTemperature < dynamicFloor) startTemperature = dynamicFloor;
    }

    double temperature = startTemperature;

    // Reheat tracking
    double bestSAScore = currentScore;
    int noImprovementCount = 0;

    // --- סטטיסטיקות מהלכים ---
    int acceptedSwaps = 0, acceptedRelocates = 0, acceptedMoves = 0;
    int acceptedCrossExchanges = 0, snapshotRestores = 0;

    for (int step = 0; step < steps; step++) {
      // Linear cooling: טמפרטורה יורדת ליניארית עם רצפה 0.01
      final progress = step / steps;
      temperature = startTemperature * (1 - progress);
      if (temperature < 0.01) temperature = 0.01;

      // Snapshot לפני המהלך — לשחזור אם K invariant נשבר
      final savedChunks = routeChunks.map((k, v) => MapEntry(k, List<_SimpleCheckpoint>.from(v)));
      final savedFreePool = Set<String>.from(freePool);
      final savedRoutes = Map<String, _RouteResult>.from(currentRoutes);
      final savedScore = currentScore;

      // בחירת סוג מהלך: 35% swap, 20% relocate, 25% move, 20% cross-exchange
      // (2-opt intra הוסר — NN ordering ב-_rebuildRouteLight מטפל בסדר)
      final moveRoll = random.nextDouble();

      if (moveRoll < 0.35) {
        // === SWAP: החלפת נקודה בין 2 מנווטים ===
        final i1 = random.nextInt(navigators.length);
        var i2 = random.nextInt(navigators.length - 1);
        if (i2 >= i1) i2++;

        final nav1 = navigators[i1];
        final nav2 = navigators[i2];
        final route1 = routeChunks[nav1];
        final route2 = routeChunks[nav2];

        if (route1 == null || route2 == null || route1.isEmpty || route2.isEmpty) continue;

        final idx1 = random.nextInt(route1.length);
        final idx2 = random.nextInt(route2.length);
        final cp1 = route1[idx1];
        final cp2 = route2[idx2];

        if (cp1.id == cp2.id) continue;
        // מניעת כפילויות בתוך ציר בודד (גם כש-allowSharing בין מנווטים)
        if (route1.any((c) => c.id == cp2.id) || route2.any((c) => c.id == cp1.id)) continue;

        route1[idx1] = cp2;
        route2[idx2] = cp1;

        final newResult1 = evalLight(route1);
        final newResult2 = evalLight(route2);

        final testRoutes = Map<String, _RouteResult>.from(currentRoutes);
        testRoutes[nav1] = newResult1;
        testRoutes[nav2] = newResult2;
        final newScore = _calculateFullScore(testRoutes, criterion, minRoute, maxRoute, isGuard: isGuard, violationMatrix: violationMatrix);

        final delta = newScore - currentScore;
        if (delta > 0 || random.nextDouble() < exp(delta / temperature)) {
          currentRoutes = testRoutes;
          currentScore = newScore;
          acceptedSwaps++;
        } else {
          route1[idx1] = cp1;
          route2[idx2] = cp2;
        }

      } else if (moveRoll < 0.55) {
        // === RELOCATE (רופיש 3): העברת נקודה מציר אחד לאחר עם פיצוי מהפול ===
        if (!allowSharing && freePool.isEmpty) continue;

        final i1 = random.nextInt(navigators.length);
        var i2 = random.nextInt(navigators.length - 1);
        if (i2 >= i1) i2++;

        final navFrom = navigators[i1];
        final navTo = navigators[i2];
        final routeFrom = routeChunks[navFrom];
        final routeTo = routeChunks[navTo];

        if (routeFrom == null || routeTo == null || routeFrom.length <= 1 || routeTo.isEmpty) continue;
        if (!allowSharing && routeTo.length >= K) continue;

        // הוצאת נקודה מ-routeFrom
        final removeIdx = random.nextInt(routeFrom.length);
        final movedCp = routeFrom[removeIdx];

        // בדיקת כפילויות בתוך ציר בודד
        if (routeTo.any((c) => c.id == movedCp.id)) continue;

        // הוספה ל-routeTo
        routeFrom.removeAt(removeIdx);
        routeTo.add(movedCp);

        // פיצוי: routeFrom מקבל נקודה מהפול
        _SimpleCheckpoint? compensationCp;
        String? compensationId;
        if (!allowSharing && freePool.isNotEmpty) {
          final freeList = freePool.toList();
          compensationId = freeList[random.nextInt(freeList.length)];
          compensationCp = cpMap[compensationId];
          if (compensationCp != null && !routeFrom.any((c) => c.id == compensationCp!.id)) {
            routeFrom.add(compensationCp);
            freePool.remove(compensationId);
          } else {
            compensationCp = null;
          }
        }

        // routeTo צריך להיפטר מנקודה אחת (שומר על K)
        _SimpleCheckpoint? removedFromTo;
        int removedFromToIdx = -1;
        if (routeTo.length > K) {
          removedFromToIdx = random.nextInt(routeTo.length);
          removedFromTo = routeTo.removeAt(removedFromToIdx);
          if (!allowSharing) freePool.add(removedFromTo.id);
        }

        final newResult1 = evalLight(routeFrom);
        final newResult2 = evalLight(routeTo);

        final testRoutes = Map<String, _RouteResult>.from(currentRoutes);
        testRoutes[navFrom] = newResult1;
        testRoutes[navTo] = newResult2;
        final newScore = _calculateFullScore(testRoutes, criterion, minRoute, maxRoute, isGuard: isGuard, violationMatrix: violationMatrix);

        final delta = newScore - currentScore;
        if (delta > 0 || random.nextDouble() < exp(delta / temperature)) {
          currentRoutes = testRoutes;
          currentScore = newScore;
          acceptedRelocates++;
        } else {
          // undo
          if (removedFromTo != null) {
            routeTo.insert(removedFromToIdx.clamp(0, routeTo.length), removedFromTo);
            if (!allowSharing) freePool.remove(removedFromTo.id);
          }
          routeTo.remove(movedCp);
          routeFrom.insert(removeIdx.clamp(0, routeFrom.length), movedCp);
          if (compensationCp != null) {
            routeFrom.remove(compensationCp);
            if (compensationId != null) freePool.add(compensationId);
          }
        }

      } else if (moveRoll < 0.80 && (freePool.isNotEmpty || allowSharing)) {
        // === MOVE: החלפת נקודה בציר עם נקודה מהפול — בחירה לפי שכנות ===
        final navIdx = random.nextInt(navigators.length);
        final nav = navigators[navIdx];
        final route = routeChunks[nav];
        if (route == null || route.isEmpty) continue;

        final removeIdx = random.nextInt(route.length);
        final oldCp = route[removeIdx];

        _SimpleCheckpoint? newCp;
        if (allowSharing) {
          // בחירה מבוססת שכנות: מיון לפי מרחק מהנקודה הנוכחית, בחירה מ-K קרובים
          final neighbors = List<_SimpleCheckpoint>.from(pool)
            ..removeWhere((c) => c.id == oldCp.id);
          if (neighbors.isEmpty) continue;
          neighbors.sort((a, b) =>
            _dist(oldCp.id, a.id, distMatrix).compareTo(_dist(oldCp.id, b.id, distMatrix)));
          final topK = min(8, neighbors.length);
          newCp = neighbors[random.nextInt(topK)];
        } else {
          if (freePool.isEmpty) continue;
          // בחירה מבוססת שכנות מהפול החופשי
          final freeList = freePool.toList();
          if (freeList.length <= 8) {
            newCp = cpMap[freeList[random.nextInt(freeList.length)]];
          } else {
            // מיון לפי מרחק מהנקודה הנוכחית, בחירה מ-8 קרובים
            freeList.sort((a, b) =>
              _dist(oldCp.id, a, distMatrix).compareTo(_dist(oldCp.id, b, distMatrix)));
            final pickId = freeList[random.nextInt(8)];
            newCp = cpMap[pickId];
          }
          if (newCp == null) continue;
        }

        // מניעת כפילויות בתוך ציר בודד
        if (route.any((c) => c.id == newCp!.id)) continue;

        route[removeIdx] = newCp;
        if (!allowSharing) {
          freePool.remove(newCp.id);
          freePool.add(oldCp.id);
        }

        final newResult = evalLight(route);
        final testRoutes = Map<String, _RouteResult>.from(currentRoutes);
        testRoutes[nav] = newResult;
        final newScore = _calculateFullScore(testRoutes, criterion, minRoute, maxRoute, isGuard: isGuard, violationMatrix: violationMatrix);

        final delta = newScore - currentScore;
        if (delta > 0 || random.nextDouble() < exp(delta / temperature)) {
          currentRoutes = testRoutes;
          currentScore = newScore;
          acceptedMoves++;
        } else {
          route[removeIdx] = oldCp;
          if (!allowSharing) {
            freePool.add(newCp.id);
            freePool.remove(oldCp.id);
          }
        }

      } else {
        // === CROSS-EXCHANGE (רופיש 4): החלפת שרשרת 1-2 נקודות בין 2 צירים ===
        final i1 = random.nextInt(navigators.length);
        var i2 = random.nextInt(navigators.length - 1);
        if (i2 >= i1) i2++;

        final nav1 = navigators[i1];
        final nav2 = navigators[i2];
        final route1 = routeChunks[nav1];
        final route2 = routeChunks[nav2];

        if (route1 == null || route2 == null || route1.length < 2 || route2.length < 2) continue;

        // בחירת אורך שרשרת (1-2)
        final maxChain = min(2, min(route1.length, route2.length));
        if (maxChain < 1) continue;
        final chainLen = 1 + random.nextInt(maxChain);
        if (chainLen > route1.length || chainLen > route2.length) continue;
        final start1 = random.nextInt(route1.length - chainLen + 1);
        final start2 = random.nextInt(route2.length - chainLen + 1);

        // שמירת שרשראות לצורך undo
        final chain1 = route1.sublist(start1, start1 + chainLen).toList();
        final chain2 = route2.sublist(start2, start2 + chainLen).toList();

        // בדיקת כפילויות בתוך ציר בודד (גם כש-allowSharing בין מנווטים)
        final route1Without = [...route1.sublist(0, start1), ...route1.sublist(start1 + chainLen)];
        final route2Without = [...route2.sublist(0, start2), ...route2.sublist(start2 + chainLen)];
        if (chain2.any((c) => route1Without.any((r) => r.id == c.id)) ||
            chain1.any((c) => route2Without.any((r) => r.id == c.id))) continue;

        // החלפה
        for (int c = 0; c < chainLen; c++) {
          route1[start1 + c] = chain2[c];
          route2[start2 + c] = chain1[c];
        }

        final newResult1 = evalLight(route1);
        final newResult2 = evalLight(route2);

        final testRoutes = Map<String, _RouteResult>.from(currentRoutes);
        testRoutes[nav1] = newResult1;
        testRoutes[nav2] = newResult2;
        final newScore = _calculateFullScore(testRoutes, criterion, minRoute, maxRoute, isGuard: isGuard, violationMatrix: violationMatrix);

        final delta = newScore - currentScore;
        if (delta > 0 || random.nextDouble() < exp(delta / temperature)) {
          currentRoutes = testRoutes;
          currentScore = newScore;
          acceptedCrossExchanges++;
        } else {
          // undo
          for (int c = 0; c < chainLen; c++) {
            route1[start1 + c] = chain1[c];
            route2[start2 + c] = chain2[c];
          }
        }

      }

      // Safety net: ולידציית K invariant אחרי כל מהלך שהתקבל
      if (!_isValidKSolution(routeChunks, K) ||
          (!allowSharing && !_isConserved(routeChunks, freePool, pool.length))) {
        // שחזור מלא מ-snapshot
        for (final nav in navigators) {
          routeChunks[nav] = savedChunks[nav]!;
        }
        freePool.clear();
        freePool.addAll(savedFreePool);
        currentRoutes = savedRoutes;
        currentScore = savedScore;
        snapshotRestores++;
        continue;
      }

      // Reheat: חימום מחדש בסטגנציה
      if (currentScore > bestSAScore) {
        bestSAScore = currentScore;
        noImprovementCount = 0;
      } else {
        noImprovementCount++;
        if (noImprovementCount > 40) {
          temperature *= 1.5;
          noImprovementCount = 0;
        }
      }
    }

    // --- לוג סטטיסטיקות ---
    final totalAccepted = acceptedSwaps + acceptedRelocates + acceptedMoves + acceptedCrossExchanges;
    print('[SA] steps=$steps accepted=$totalAccepted '
        '(swap=$acceptedSwaps reloc=$acceptedRelocates move=$acceptedMoves '
        'cross=$acceptedCrossExchanges) '
        'restores=$snapshotRestores score=${currentScore.toStringAsFixed(2)}');

    // ולידציה סופית: אם K invariant שבור, חזרה לפתרון ההתחלתי
    final finalChunksValid = routeChunks.values.every((r) => r.length == K);
    if (!finalChunksValid) {
      return Map.from(initial);
    }

    // --- אופטימיזציה סופית: NN-TSP + 2-opt על כל ציר ---
    // במהלך SA השתמשנו ב-_rebuildRouteLight (ללא 2-opt) למהירות.
    // כעת מריצים _rebuildRoute מלא לשיפור סדר הנקודות הסופי.
    final finalRoutes = <String, _RouteResult>{};
    for (final nav in navigators) {
      final chunk = routeChunks[nav];
      if (chunk == null) continue;
      finalRoutes[nav] = evalFull(chunk);
    }

    // --- תיקון הפרות שנותרו (repair sweep ±3 מיקומים) ---
    if (violationMatrix != null) {
      for (final nav in navigators) {
        final route = finalRoutes[nav];
        if (route == null || route.boundaryExits == 0) continue;

        final chunk = routeChunks[nav];
        if (chunk == null || chunk.isEmpty) continue;

        for (int attempt = 0; attempt < 3; attempt++) {
          if (finalRoutes[nav]!.boundaryExits == 0) break;

          final seq = chunk.toList();
          final seqIds = seq.map((c) => c.id).toList();
          final fullSeq = <String>[
            if (startCp != null) startCp.id,
            ...seqIds,
            if (endCp != null) endCp.id,
          ];

          final offset = startCp != null ? 1 : 0;
          final violatingIndices = <int>{};
          for (int i = 0; i < fullSeq.length - 1; i++) {
            if (_lookupViolationCount(fullSeq[i], fullSeq[i + 1], violationMatrix) > 0) {
              if (i >= offset && i - offset < seq.length) violatingIndices.add(i - offset);
              if (i + 1 >= offset && i + 1 - offset < seq.length) violatingIndices.add(i + 1 - offset);
            }
          }
          if (violatingIndices.isEmpty) break;

          int bestBE = finalRoutes[nav]!.boundaryExits;
          List<_SimpleCheckpoint>? bestChunk;

          for (final removeIdx in violatingIndices) {
            if (removeIdx >= seq.length) continue;
            final removed = seq[removeIdx];
            final trial = List<_SimpleCheckpoint>.from(seq)..removeAt(removeIdx);

            // הכנסה ב-±3 מיקומים בלבד
            final minIns = (removeIdx - 3).clamp(0, trial.length);
            final maxIns = (removeIdx + 3).clamp(0, trial.length);
            for (int ins = minIns; ins <= maxIns; ins++) {
              if (ins == removeIdx) continue;
              final candidate = List<_SimpleCheckpoint>.from(trial)..insert(ins, removed);
              final v = _countSequenceViolations(
                candidate.map((c) => c.id).toList(), startCp?.id, endCp?.id, violationMatrix,
              );
              if (v.boundaryExits < bestBE) {
                bestBE = v.boundaryExits;
                bestChunk = candidate;
              }
            }
          }

          if (bestChunk != null) {
            for (int i = 0; i < chunk.length; i++) chunk[i] = bestChunk[i];
            finalRoutes[nav] = evalFull(chunk);
          } else {
            break;
          }
        }

        if (finalRoutes[nav]!.boundaryExits > 0) {
          print('[WARNING] ציר של $nav עדיין מכיל ${finalRoutes[nav]!.boundaryExits} '
              'חציות גבול אחרי תיקון');
        }
      }
    }

    return finalRoutes;
  }

  /// בניית ציר מחדש אחרי שינוי נקודות
  static _RouteResult _rebuildRoute(
    List<_SimpleCheckpoint> chunk,
    _SimpleCheckpoint? startCp,
    _SimpleCheckpoint? endCp,
    List<_SimpleWaypoint> waypoints,
    List<_SimpleCheckpoint> allCheckpoints,
    String executionOrder,
    double minRoute,
    double maxRoute,
    Map<String, Map<String, double>> distMatrix, [
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  ]) {
    final sequence = _optimizeSequence(chunk, startCp, endCp, executionOrder, distMatrix, waypoints, allCheckpoints, violationMatrix);
    final result = _buildRouteWithWaypoints(
      chunk: chunk,
      sequence: sequence,
      startCp: startCp,
      endCp: endCp,
      waypoints: waypoints,
      allCheckpoints: allCheckpoints,
      distMatrix: distMatrix,
    );
    final length = result['length'] as double;
    final waypointIds = result['waypointIds'] as List<String>;
    final violations = _countSequenceViolations(
      sequence.map((c) => c.id).toList(), startCp?.id, endCp?.id, violationMatrix,
    );
    return _RouteResult(
      checkpointIds: chunk.map((c) => c.id).toList(),
      sequence: sequence.map((c) => c.id).toList(),
      waypointIds: waypointIds,
      routeLengthKm: length,
      inRange: length >= minRoute && length <= maxRoute,
      boundaryExits: violations.boundaryExits,
      safetyIntersections: violations.safetyIntersections,
    );
  }

  /// סידור Nearest-Neighbor מודע-גבול — effective distance = dist + crossings * 1000
  static void _nnOrder(
    List<_SimpleCheckpoint> chunk,
    _SimpleCheckpoint? startCp,
    Map<String, Map<String, double>> distMatrix, [
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  ]) {
    if (chunk.length <= 1) return;
    final remaining = List<_SimpleCheckpoint>.from(chunk);
    final ordered = <_SimpleCheckpoint>[];

    _SimpleCheckpoint current;
    if (startCp != null && remaining.isNotEmpty) {
      int bestIdx = 0;
      double bestScore = double.infinity;
      for (int i = 0; i < remaining.length; i++) {
        double d = _dist(startCp.id, remaining[i].id, distMatrix);
        if (violationMatrix != null) {
          final v = violationMatrix[startCp.id]?[remaining[i].id];
          if (v != null && v.exitsBoundary) d += v.boundaryCrossings * 1000.0;
        }
        if (d < bestScore) { bestScore = d; bestIdx = i; }
      }
      current = remaining.removeAt(bestIdx);
    } else {
      current = remaining.removeAt(0);
    }
    ordered.add(current);

    while (remaining.isNotEmpty) {
      int bestIdx = 0;
      double bestScore = double.infinity;
      for (int i = 0; i < remaining.length; i++) {
        double d = _dist(current.id, remaining[i].id, distMatrix);
        if (violationMatrix != null) {
          final v = violationMatrix[current.id]?[remaining[i].id];
          if (v != null && v.exitsBoundary) d += v.boundaryCrossings * 1000.0;
        }
        if (d < bestScore) { bestScore = d; bestIdx = i; }
      }
      current = remaining.removeAt(bestIdx);
      ordered.add(current);
    }

    for (int i = 0; i < chunk.length; i++) {
      chunk[i] = ordered[i];
    }
  }

  /// בניית ציר מחדש — גרסה קלה (NN ordering ללא 2-opt)
  /// מסדרת לפי nearest-neighbor, מכניסה waypoints ומחשבת אורך.
  /// משמשת ב-SA לצורך הערכה מהירה של מהלכי SWAP/MOVE/RELOCATE/CROSS.
  static _RouteResult _rebuildRouteLight(
    List<_SimpleCheckpoint> chunk,
    _SimpleCheckpoint? startCp,
    _SimpleCheckpoint? endCp,
    List<_SimpleWaypoint> waypoints,
    List<_SimpleCheckpoint> allCheckpoints,
    double minRoute,
    double maxRoute,
    Map<String, Map<String, double>> distMatrix, [
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  ]) {
    final sequence = List<_SimpleCheckpoint>.from(chunk);
    _nnOrder(sequence, startCp, distMatrix, violationMatrix);
    if (waypoints.isNotEmpty) {
      _insertWaypointsIntoSequence(sequence, startCp, endCp, waypoints, allCheckpoints, distMatrix);
    }
    final result = _buildRouteWithWaypoints(
      chunk: chunk,
      sequence: sequence,
      startCp: startCp,
      endCp: endCp,
      waypoints: waypoints,
      allCheckpoints: allCheckpoints,
      distMatrix: distMatrix,
    );
    final length = result['length'] as double;
    assert(chunk.map((c) => c.id).toSet().length == chunk.length,
        '_rebuildRouteLight: duplicate checkpoint IDs in chunk');
    final violations = _countSequenceViolations(
      sequence.map((c) => c.id).toList(), startCp?.id, endCp?.id, violationMatrix,
    );
    return _RouteResult(
      checkpointIds: chunk.map((c) => c.id).toList(),
      sequence: sequence.map((c) => c.id).toList(),
      waypointIds: result['waypointIds'] as List<String>,
      routeLengthKm: length,
      inRange: length >= minRoute && length <= maxRoute,
      boundaryExits: violations.boundaryExits,
      safetyIntersections: violations.safetyIntersections,
    );
  }

  /// חלוקת 2K נקודות לשני חצאים על בסיס קרבה גיאוגרפית
  /// חצי ראשון: start → swap, חצי שני: swap → end
  static List<List<_SimpleCheckpoint>> _splitGuardCheckpoints(
    List<_SimpleCheckpoint> chunk,
    _SimpleCheckpoint? startCp,
    _SimpleCheckpoint? endCp,
    _SimpleCheckpoint? swapCp,
    Map<String, Map<String, double>> distMatrix,
  ) {
    if (swapCp == null || chunk.length < 2) return [chunk, <_SimpleCheckpoint>[]];

    final half = chunk.length ~/ 2;

    // ניקוד כל נקודה: עלות שיוך לחצי ראשון מול חצי שני
    // firstCost = dist(start→cp) + dist(cp→swap), secondCost = dist(swap→cp) + dist(cp→end)
    final scored = chunk.map((cp) {
      final dStart = startCp != null ? _dist(startCp.id, cp.id, distMatrix) : 0.0;
      final dSwap = _dist(swapCp.id, cp.id, distMatrix);
      final dEnd = endCp != null ? _dist(cp.id, endCp.id, distMatrix) : 0.0;
      final firstCost = dStart + dSwap;
      final secondCost = dSwap + dEnd;
      return (cp: cp, score: firstCost - secondCost);
    }).toList();
    scored.sort((a, b) => a.score.compareTo(b.score));

    final firstHalf = scored.take(half).map((s) => s.cp).toList();
    final secondHalf = scored.skip(half).map((s) => s.cp).toList();
    return [firstHalf, secondHalf];
  }

  /// הערכת ציר מאבטח — פיצול ל-2 חצאים + NN עצמאי לכל חצי
  static _RouteResult _evaluateGuardRoute(
    List<_SimpleCheckpoint> chunk,
    _SimpleCheckpoint? startCp,
    _SimpleCheckpoint? endCp,
    _SimpleCheckpoint? swapCp,
    List<_SimpleWaypoint> waypoints,
    List<_SimpleCheckpoint> allCheckpoints,
    double minRoute,
    double maxRoute,
    Map<String, Map<String, double>> distMatrix, [
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  ]) {
    final halfMin = minRoute / 2;
    final halfMax = maxRoute / 2;

    final halves = _splitGuardCheckpoints(chunk, startCp, endCp, swapCp, distMatrix);

    final firstResult = _rebuildRouteLight(
      halves[0], startCp, swapCp, const [], allCheckpoints,
      halfMin, halfMax, distMatrix, violationMatrix,
    );
    final secondResult = _rebuildRouteLight(
      halves[1], swapCp, endCp, const [], allCheckpoints,
      halfMin, halfMax, distMatrix, violationMatrix,
    );

    final combinedLength = firstResult.routeLengthKm + secondResult.routeLengthKm;
    return _RouteResult(
      checkpointIds: [...firstResult.checkpointIds, ...secondResult.checkpointIds],
      sequence: [...firstResult.sequence, ...secondResult.sequence],
      waypointIds: [...firstResult.waypointIds, ...secondResult.waypointIds],
      routeLengthKm: combinedLength,
      inRange: firstResult.inRange && secondResult.inRange,
      firstHalfLengthKm: firstResult.routeLengthKm,
      secondHalfLengthKm: secondResult.routeLengthKm,
      boundaryExits: firstResult.boundaryExits + secondResult.boundaryExits,
      safetyIntersections: firstResult.safetyIntersections + secondResult.safetyIntersections,
    );
  }

  /// חישוב ניקוד כולל לחלוקה
  static double _calculateFullScore(
    Map<String, _RouteResult> distribution,
    String criterion,
    double minRoute,
    double maxRoute, {
    bool isGuard = false,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  }) {
    final allCpIds = distribution.values.expand((r) => r.checkpointIds).toList();
    final uniqueCpIds = allCpIds.toSet();
    final hasSharing = allCpIds.length != uniqueCpIds.length;
    final allInRange = distribution.values.every((r) => r.inRange);

    return _scoreDistribution(
      distribution: distribution,
      criterion: criterion,
      minRoute: minRoute,
      maxRoute: maxRoute,
      allInRange: allInRange,
      hasSharing: hasSharing,
      totalUniqueCheckpoints: uniqueCpIds.length,
      isGuard: isGuard,
      violationMatrix: violationMatrix,
    );
  }

  /// אופטימיזציית רצף: nearest-neighbor TSP + הכנסת waypoints + 2-opt (דילוג על waypoints)
  static List<_SimpleCheckpoint> _optimizeSequence(
    List<_SimpleCheckpoint> chunk,
    _SimpleCheckpoint? startCp,
    _SimpleCheckpoint? endCp,
    String executionOrder,
    Map<String, Map<String, double>> distMatrix, [
    List<_SimpleWaypoint> waypoints = const [],
    List<_SimpleCheckpoint> allCheckpoints = const [],
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  ]) {
    if (chunk.length <= 1 || executionOrder != 'sequential') {
      // גם אם אין אופטימיזציה, עדיין מכניסים waypoints
      final result = List<_SimpleCheckpoint>.from(chunk);
      if (waypoints.isNotEmpty) {
        _insertWaypointsIntoSequence(result, startCp, endCp, waypoints, allCheckpoints, distMatrix);
      }
      return result;
    }

    // שלב 1: Nearest-neighbor מודע-גבול — effective distance = dist + crossings * 1000
    final remaining = List<_SimpleCheckpoint>.from(chunk);
    final result = <_SimpleCheckpoint>[];

    _SimpleCheckpoint current;
    if (startCp != null && remaining.isNotEmpty) {
      int bestIdx = 0;
      double bestScore = double.infinity;
      for (int i = 0; i < remaining.length; i++) {
        double d = _dist(startCp.id, remaining[i].id, distMatrix);
        if (violationMatrix != null) {
          final v = violationMatrix[startCp.id]?[remaining[i].id];
          if (v != null && v.exitsBoundary) d += v.boundaryCrossings * 1000.0;
        }
        if (d < bestScore) { bestScore = d; bestIdx = i; }
      }
      current = remaining.removeAt(bestIdx);
    } else {
      current = remaining.removeAt(0);
    }
    result.add(current);

    while (remaining.isNotEmpty) {
      int bestIdx = 0;
      double bestScore = double.infinity;
      for (int i = 0; i < remaining.length; i++) {
        double d = _dist(current.id, remaining[i].id, distMatrix);
        if (violationMatrix != null) {
          final v = violationMatrix[current.id]?[remaining[i].id];
          if (v != null && v.exitsBoundary) d += v.boundaryCrossings * 1000.0;
        }
        if (d < bestScore) { bestScore = d; bestIdx = i; }
      }
      current = remaining.removeAt(bestIdx);
      result.add(current);
    }

    // שלב 2: הכנסת waypoints לפני 2-opt
    final waypointIdSet = <String>{};
    if (waypoints.isNotEmpty) {
      _insertWaypointsIntoSequence(result, startCp, endCp, waypoints, allCheckpoints, distMatrix);
      for (final wp in waypoints) {
        waypointIdSet.add(wp.checkpointId);
      }
    }

    // שלב 3: 2-opt improvement — דילוג על waypoints (נשארים במקום)
    if (result.length >= 3) {
      bool improved = true;
      int passes = 0;
      while (improved && passes < 10) {
        improved = false;
        passes++;
        for (int i = 0; i < result.length - 1; i++) {
          // דילוג על waypoints
          if (waypointIdSet.contains(result[i].id)) continue;
          for (int j = i + 1; j < result.length; j++) {
            if (waypointIdSet.contains(result[j].id)) continue;
            // בדיקה שאין waypoint בתוך הסגמנט
            bool hasWaypointInSegment = false;
            for (int k = i + 1; k < j; k++) {
              if (waypointIdSet.contains(result[k].id)) {
                hasWaypointInSegment = true;
                break;
              }
            }
            if (hasWaypointInSegment) continue;

            double saving = 0;

            // קצה לפני הסגמנט
            if (i > 0) {
              saving += _dist(result[i - 1].id, result[i].id, distMatrix);
              saving -= _dist(result[i - 1].id, result[j].id, distMatrix);
            } else if (startCp != null) {
              saving += _dist(startCp.id, result[i].id, distMatrix);
              saving -= _dist(startCp.id, result[j].id, distMatrix);
            }

            // קצה אחרי הסגמנט
            if (j < result.length - 1) {
              saving += _dist(result[j].id, result[j + 1].id, distMatrix);
              saving -= _dist(result[i].id, result[j + 1].id, distMatrix);
            } else if (endCp != null) {
              saving += _dist(result[j].id, endCp.id, distMatrix);
              saving -= _dist(result[i].id, endCp.id, distMatrix);
            }

            // בדיקת הפרות גיאומטריות — דחיית swap שמחמיר הפרות
            if (saving > 1e-10 && violationMatrix != null) {
              // חישוב הפרות ישנות על 2 הצלעות שנמחקות
              final prevI = i > 0 ? result[i - 1].id : startCp?.id;
              final nextJ = j < result.length - 1 ? result[j + 1].id : endCp?.id;
              int oldV = 0, newV = 0;
              if (prevI != null) {
                oldV += _lookupViolationCount(prevI, result[i].id, violationMatrix);
                newV += _lookupViolationCount(prevI, result[j].id, violationMatrix);
              }
              if (nextJ != null) {
                oldV += _lookupViolationCount(result[j].id, nextJ, violationMatrix);
                newV += _lookupViolationCount(result[i].id, nextJ, violationMatrix);
              }
              if (newV > oldV) continue; // דחיית swap שמחמיר הפרות
            }

            if (saving > 1e-10) {
              // היפוך סגמנט i..j
              int left = i, right = j;
              while (left < right) {
                final temp = result[left];
                result[left] = result[right];
                result[right] = temp;
                left++;
                right--;
              }
              improved = true;
            }
          }
        }
      }
    }

    // שלב 4: 2-opt תיקוני הפרות — מקבל swap שמקטין הפרות גם במחיר מרחק (עד 30%)
    if (result.length >= 3 && violationMatrix != null) {
      int currentViolations = 0;
      final prevFirst = startCp?.id;
      if (prevFirst != null) {
        currentViolations += _lookupViolationCount(prevFirst, result[0].id, violationMatrix);
      }
      for (int i = 0; i < result.length - 1; i++) {
        currentViolations += _lookupViolationCount(result[i].id, result[i + 1].id, violationMatrix);
      }
      if (endCp != null) {
        currentViolations += _lookupViolationCount(result.last.id, endCp.id, violationMatrix);
      }

      if (currentViolations > 0) {
        bool improved = true;
        int passes = 0;
        while (improved && passes < 10) {
          improved = false;
          passes++;
          for (int i = 0; i < result.length - 1; i++) {
            if (waypointIdSet.contains(result[i].id)) continue;
            for (int j = i + 1; j < result.length; j++) {
              if (waypointIdSet.contains(result[j].id)) continue;
              bool hasWpInSeg = false;
              for (int k = i + 1; k < j; k++) {
                if (waypointIdSet.contains(result[k].id)) { hasWpInSeg = true; break; }
              }
              if (hasWpInSeg) continue;

              final prevI = i > 0 ? result[i - 1].id : startCp?.id;
              final nextJ = j < result.length - 1 ? result[j + 1].id : endCp?.id;
              int oldV = 0, newV = 0;
              if (prevI != null) {
                oldV += _lookupViolationCount(prevI, result[i].id, violationMatrix);
                newV += _lookupViolationCount(prevI, result[j].id, violationMatrix);
              }
              if (nextJ != null) {
                oldV += _lookupViolationCount(result[j].id, nextJ, violationMatrix);
                newV += _lookupViolationCount(result[i].id, nextJ, violationMatrix);
              }
              // הפרות פנימיות
              int intOld = 0, intNew = 0;
              for (int k = i; k < j; k++) {
                intOld += _lookupViolationCount(result[k].id, result[k + 1].id, violationMatrix);
              }
              for (int k = j; k > i; k--) {
                intNew += _lookupViolationCount(result[k].id, result[k - 1].id, violationMatrix);
              }

              if ((newV + intNew) < (oldV + intOld)) {
                // תקציב מרחק — עד 30% עלייה
                double oldDist = 0, newDist = 0;
                if (prevI != null) {
                  oldDist += _dist(prevI, result[i].id, distMatrix);
                  newDist += _dist(prevI, result[j].id, distMatrix);
                }
                if (nextJ != null) {
                  oldDist += _dist(result[j].id, nextJ, distMatrix);
                  newDist += _dist(result[i].id, nextJ, distMatrix);
                }
                if (oldDist < 1e-10 || (newDist - oldDist) / oldDist <= 0.30) {
                  int left = i, right = j;
                  while (left < right) {
                    final temp = result[left];
                    result[left] = result[right];
                    result[right] = temp;
                    left++; right--;
                  }
                  improved = true;
                  currentViolations = currentViolations - (oldV + intOld) + (newV + intNew);
                  if (currentViolations <= 0) break;
                }
              }
            }
            if (currentViolations <= 0) break;
          }
          if (currentViolations <= 0) break;
        }
      }
    }

    return result;
  }

  /// הכנסת waypoints לתוך רצף קיים (in-place)
  static void _insertWaypointsIntoSequence(
    List<_SimpleCheckpoint> sequence,
    _SimpleCheckpoint? startCp,
    _SimpleCheckpoint? endCp,
    List<_SimpleWaypoint> waypoints,
    List<_SimpleCheckpoint> allCheckpoints,
    Map<String, Map<String, double>> distMatrix,
  ) {
    for (final wp in waypoints) {
      final wpCp = allCheckpoints.where((c) => c.id == wp.checkpointId).firstOrNull;
      if (wpCp == null) continue;
      // דילוג אם זהה להתחלה/סיום (כבר מופיעים בציר)
      if (startCp != null && wpCp.id == startCp.id) continue;
      if (endCp != null && wpCp.id == endCp.id) continue;
      // דילוג אם כבר ברצף (למניעת כפילות)
      if (sequence.any((c) => c.id == wpCp.id)) continue;

      if (wp.placementType == 'distance' && wp.afterDistanceMinKm != null && wp.afterDistanceMaxKm != null) {
        // הכנסה לפי טווח מרחק — מחפש מיקום אופטימלי בטווח [min, max]
        final minDist = wp.afterDistanceMinKm!;
        final maxDist = wp.afterDistanceMaxKm!;
        final midDist = (minDist + maxDist) / 2;

        // בניית רצף מלא עם start/end לחישוב מרחק מצטבר
        final fullSeq = <_SimpleCheckpoint>[];
        if (startCp != null) fullSeq.add(startCp);
        fullSeq.addAll(sequence);
        if (endCp != null) fullSeq.add(endCp);

        final startOffset = startCp != null ? 1 : 0;

        double cumDistance = 0;
        int bestInsertIndex = -1;
        double bestScore = double.infinity;

        for (int i = 0; i < fullSeq.length - 1; i++) {
          cumDistance += _dist(fullSeq[i].id, fullSeq[i + 1].id, distMatrix);
          if (cumDistance >= minDist && cumDistance <= maxDist) {
            final score = (cumDistance - midDist).abs();
            if (score < bestScore) {
              bestScore = score;
              bestInsertIndex = i + 1 - startOffset;
            }
          }
          if (cumDistance > maxDist && bestInsertIndex == -1) {
            // עברנו את הטווח בלי למצוא — הכנס כאן
            bestInsertIndex = i + 1 - startOffset;
            break;
          }
        }

        if (bestInsertIndex >= 0 && bestInsertIndex <= sequence.length) {
          sequence.insert(bestInsertIndex.clamp(0, sequence.length), wpCp);
        } else {
          // fallback: הכנס לפני הסוף
          sequence.insert(sequence.length, wpCp);
        }
      } else if (wp.placementType == 'between_checkpoints') {
        // הכנסה לפי אינדקס gap: -1 = לפני נקודה 1, 0 = אחרי נקודה 1, וכו'
        final gapIndex = wp.afterCheckpointIndex ?? -1;
        final insertAt = gapIndex + 1; // -1→0, 0→1, 1→2, ...
        sequence.insert(insertAt.clamp(0, sequence.length), wpCp);
      }
    }
  }

  /// בניית ציר מלא — הרצף כבר כולל waypoints מ-_optimizeSequence
  static Map<String, dynamic> _buildRouteWithWaypoints({
    required List<_SimpleCheckpoint> chunk,
    required List<_SimpleCheckpoint> sequence,
    required _SimpleCheckpoint? startCp,
    required _SimpleCheckpoint? endCp,
    required List<_SimpleWaypoint> waypoints,
    required List<_SimpleCheckpoint> allCheckpoints,
    required Map<String, Map<String, double>> distMatrix,
  }) {
    // בניית רצף מלא: start → sequence (כולל waypoints) → end
    final fullSequence = <_SimpleCheckpoint>[];
    if (startCp != null) fullSequence.add(startCp);
    fullSequence.addAll(sequence);
    if (endCp != null) fullSequence.add(endCp);

    // איסוף waypoint IDs מהרצף
    final waypointIdSet = waypoints.map((wp) => wp.checkpointId).toSet();
    final waypointIds = sequence
        .where((cp) => waypointIdSet.contains(cp.id))
        .map((cp) => cp.id)
        .toList();

    // חישוב אורך מלא
    double totalLength = 0;
    for (int i = 0; i < fullSequence.length - 1; i++) {
      totalLength += _dist(fullSequence[i].id, fullSequence[i + 1].id, distMatrix);
    }

    return {
      'length': totalLength,
      'waypointIds': waypointIds,
    };
  }

  /// פונקציית ניקוד — soft penalties עם גרדיאנט חלק
  static double _scoreDistribution({
    required Map<String, _RouteResult> distribution,
    required String criterion,
    required double minRoute,
    required double maxRoute,
    required bool allInRange,
    required bool hasSharing,
    required int totalUniqueCheckpoints,
    bool isGuard = false,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  }) {
    final lengths = distribution.values.map((r) => r.routeLengthKm).toList();
    if (lengths.isEmpty) return -999999;

    // Segment violation penalty — גבול = hard constraint, נת"בים = soft penalty
    double segmentPenalty = 0;
    if (violationMatrix != null) {
      int totalBE = 0;
      for (final r in distribution.values) {
        totalBE += r.boundaryExits;
        segmentPenalty += r.safetyIntersections * 5000.0;
      }
      if (totalBE > 0) return -999999.0 - totalBE * 1000.0;  // גבול ניווט — hard constraint מדורג
      if (segmentPenalty > 0) {
        final totalSI = distribution.values.fold(0, (sum, r) => sum + r.safetyIntersections);
        print('[ScoreDistribution] segmentPenalty=$segmentPenalty '
            '(safetyIntersections=$totalSI)');
      }
    }

    // Soft range penalty — ריבועי: SA "מרגיש" כמה רחוק מהטווח
    double rangePenalty = 0;
    if (isGuard) {
      // מאבטח: penalty לפי חצאי ציר בנפרד
      final halfMin = minRoute / 2;
      final halfMax = maxRoute / 2;
      for (final r in distribution.values) {
        if (r.firstHalfLengthKm != null && r.secondHalfLengthKm != null) {
          for (final halfLen in [r.firstHalfLengthKm!, r.secondHalfLengthKm!]) {
            if (halfLen < halfMin) {
              final diff = halfMin - halfLen;
              rangePenalty += diff * diff * 500;
            } else if (halfLen > halfMax) {
              final diff = halfLen - halfMax;
              rangePenalty += diff * diff * 500;
            }
          }
          // penalty על חוסר איזון בין החצאים
          final imbalance = (r.firstHalfLengthKm! - r.secondHalfLengthKm!).abs();
          rangePenalty += imbalance * imbalance * 100;
        } else {
          // fallback: שימוש באורך המשולב
          if (r.routeLengthKm < minRoute) {
            final diff = minRoute - r.routeLengthKm;
            rangePenalty += diff * diff * 500;
          } else if (r.routeLengthKm > maxRoute) {
            final diff = r.routeLengthKm - maxRoute;
            rangePenalty += diff * diff * 500;
          }
        }
      }
    } else {
      for (final r in distribution.values) {
        if (r.routeLengthKm < minRoute) {
          final diff = minRoute - r.routeLengthKm;
          rangePenalty += diff * diff * 500;
        } else if (r.routeLengthKm > maxRoute) {
          final diff = r.routeLengthKm - maxRoute;
          rangePenalty += diff * diff * 500;
        }
      }
    }

    final allInRangeBonus = allInRange ? 5000.0 : 0.0;
    final uniqueBonus = hasSharing ? 0.0 : 500.0;

    // חישוב סטטיסטיקות
    final mean = lengths.reduce((a, b) => a + b) / lengths.length;
    final variance = lengths.map((l) => (l - mean) * (l - mean)).reduce((a, b) => a + b) / lengths.length;
    final stdDev = sqrt(variance);
    final cv = mean > 0 ? stdDev / mean : 0.0; // Coefficient of Variation

    switch (criterion) {
      case 'fairness':
        // הוגנות — CV (סטיית תקן / ממוצע) כמדד יחסי לשונות
        return -cv * 5000 - rangePenalty - segmentPenalty + allInRangeBonus + uniqueBonus;

      case 'midpoint':
        // קרבה לאמצע הטווח
        final midpoint = (minRoute + maxRoute) / 2;
        final deviation = lengths.map((l) => (l - midpoint).abs()).reduce((a, b) => a + b);
        final maxDeviation = lengths.map((l) => (l - midpoint).abs()).reduce(max);
        return -deviation * 200 - maxDeviation * 300 - rangePenalty - segmentPenalty + allInRangeBonus + uniqueBonus;

      case 'uniqueness':
        // מקסימום ייחודיות
        return totalUniqueCheckpoints * 1000.0 - rangePenalty - segmentPenalty + allInRangeBonus - variance * 10;

      case 'doubleCheck':
        // אימות כפול — כל נקודה נבדקת ע"י בדיוק 2 מנווטים
        final allIds = distribution.values.expand((r) => r.checkpointIds).toList();
        final frequency = <String, int>{};
        for (final id in allIds) {
          frequency[id] = (frequency[id] ?? 0) + 1;
        }
        final doubleChecked = frequency.values.where((c) => c == 2).length;
        final singleOnly = frequency.values.where((c) => c == 1).length;
        final overChecked = frequency.values.where((c) => c > 2).length;
        return doubleChecked * 1500.0 - singleOnly * 500.0 - overChecked * 300.0
            - rangePenalty - segmentPenalty + allInRangeBonus - variance * 50;

      default:
        return -cv * 5000 - rangePenalty - segmentPenalty + allInRangeBonus + uniqueBonus;
    }
  }

  /// חלוקה בסיסית (fallback)
  static _InternalDistribution _createFallbackDistribution({
    required List<_SimpleCheckpoint> pool,
    required List<String> navigators,
    required int K,
    required _SimpleCheckpoint? startCp,
    required _SimpleCheckpoint? endCp,
    required List<_SimpleWaypoint> waypoints,
    required List<_SimpleCheckpoint> allCheckpoints,
    required double minRoute,
    required double maxRoute,
    required String executionOrder,
    required Map<String, Map<String, double>> distMatrix,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  }) {
    final distribution = <String, _RouteResult>{};
    bool allInRange = true;

    // שיטת Round-robin עם שיתוף: כל מנווט מקבל בדיוק K נקודות ללא כפילויות פנימיות
    final shuffled = List<_SimpleCheckpoint>.from(pool)..shuffle(Random());
    int poolIndex = 0;

    for (int i = 0; i < navigators.length; i++) {
      final chunk = <_SimpleCheckpoint>[];
      final usedInChunk = <String>{};

      while (chunk.length < K) {
        if (poolIndex >= shuffled.length) {
          shuffled.shuffle(Random());
          poolIndex = 0;
        }
        final cp = shuffled[poolIndex++];
        if (!usedInChunk.contains(cp.id)) {
          usedInChunk.add(cp.id);
          chunk.add(cp);
        }
      }

      final sequence = _optimizeSequence(chunk, startCp, endCp, executionOrder, distMatrix, waypoints, allCheckpoints, violationMatrix);
      final result = _buildRouteWithWaypoints(
        chunk: chunk,
        sequence: sequence,
        startCp: startCp,
        endCp: endCp,
        waypoints: waypoints,
        allCheckpoints: allCheckpoints,
        distMatrix: distMatrix,
      );

      final length = result['length'] as double;
      final waypointIds = result['waypointIds'] as List<String>;
      final inRange = length >= minRoute && length <= maxRoute;
      if (!inRange) allInRange = false;

      final violations = violationMatrix != null
          ? _countSequenceViolations(
              sequence.map((c) => c.id).toList(), startCp?.id, endCp?.id, violationMatrix)
          : (boundaryExits: 0, safetyIntersections: 0);

      distribution[navigators[i]] = _RouteResult(
        checkpointIds: chunk.map((c) => c.id).toList(),
        sequence: sequence.map((c) => c.id).toList(),
        waypointIds: waypointIds,
        routeLengthKm: length,
        inRange: inRange,
        boundaryExits: violations.boundaryExits,
        safetyIntersections: violations.safetyIntersections,
      );
    }

    final allCpIds = distribution.values.expand((r) => r.checkpointIds).toList();
    final uniqueCount = allCpIds.toSet().length;
    final hasSharing = allCpIds.length != uniqueCount;

    return _InternalDistribution(
      routes: distribution,
      score: -999,
      allInRange: allInRange,
      hasSharedCheckpoints: hasSharing,
      sharedCount: hasSharing ? allCpIds.length - uniqueCount : 0,
    );
  }

  /// Haversine distance (km)
  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// בניית מטריצת מרחקים — O(N²) חישובי haversine פעם אחת
  static Map<String, Map<String, double>> _buildDistanceMatrix(List<_SimpleCheckpoint> points) {
    final matrix = <String, Map<String, double>>{};
    for (final p in points) {
      matrix[p.id] = {};
    }
    for (int i = 0; i < points.length; i++) {
      matrix[points[i].id]![points[i].id] = 0.0;
      for (int j = i + 1; j < points.length; j++) {
        final d = _haversine(points[i].lat, points[i].lng, points[j].lat, points[j].lng);
        matrix[points[i].id]![points[j].id] = d;
        matrix[points[j].id]![points[i].id] = d;
      }
    }
    return matrix;
  }

  /// O(1) distance lookup from precomputed matrix
  static double _dist(String id1, String id2, Map<String, Map<String, double>> distMatrix) {
    if (id1 == id2) return 0.0;
    return distMatrix[id1]?[id2] ?? 0.0;
  }

  // === פונקציות גיאומטריה עצמאיות ל-Isolate (turf-based) ===

  /// point-in-polygon באמצעות turf — אלגברי מדויק
  static bool _pointInPolygon(double lat, double lng, List<List<double>> polygon) {
    if (polygon.length < 3) return false;
    final point = turf.Position(lng, lat); // GeoJSON: lng, lat order!
    final ring = polygon.map((c) => turf.Position(c[1], c[0])).toList();
    if (ring.first.lng != ring.last.lng || ring.first.lat != ring.last.lat) {
      ring.add(ring.first);
    }
    final poly = turf.Polygon(coordinates: [ring]);
    return turf.booleanPointInPolygon(point, poly);
  }

  /// בדיקה אם קטע חותך צלע כלשהי של הגבול — turf lineIntersect (אלגברי, ללא דגימה)
  static ({bool exits, int crossingCount}) _segmentExitsBoundary(
    double lat1, double lng1, double lat2, double lng2,
    List<List<double>> boundaryCoords,
    turf.Polygon boundaryPolygon,
  ) {
    final segment = turf.LineString(coordinates: [
      turf.Position(lng1, lat1),
      turf.Position(lng2, lat2),
    ]);
    final intersections = turf.lineIntersect(segment, boundaryPolygon);
    final crossingCount = intersections.features.length;
    if (crossingCount > 0) return (exits: true, crossingCount: crossingCount);
    // אין חציות צלעות — endpoint check
    // מתמטית: endpoints בפנים + 0 חציות → הקטע כולו בפנים (פוליגון פשוט)
    if (!_pointInPolygon(lat1, lng1, boundaryCoords) ||
        !_pointInPolygon(lat2, lng2, boundaryCoords)) {
      return (exits: true, crossingCount: 1);
    }
    return (exits: false, crossingCount: 0);
  }

  /// בדיקה אם קטע חותך פוליגון (נקודה בפנים או חיתוך צלעות) — turf-based
  static bool _segmentIntersectsPolygon(
    double lat1, double lng1, double lat2, double lng2,
    List<List<double>> polygonCoords,
  ) {
    if (_pointInPolygon(lat1, lng1, polygonCoords)) return true;
    if (_pointInPolygon(lat2, lng2, polygonCoords)) return true;
    final segment = turf.LineString(coordinates: [
      turf.Position(lng1, lat1),
      turf.Position(lng2, lat2),
    ]);
    final ring = polygonCoords.map((c) => turf.Position(c[1], c[0])).toList();
    if (ring.first.lng != ring.last.lng || ring.first.lat != ring.last.lat) {
      ring.add(ring.first);
    }
    final poly = turf.Polygon(coordinates: [ring]);
    return turf.lineIntersect(segment, poly).features.isNotEmpty;
  }

  /// בניית מטריצת הפרות מחושבת מראש — O(P²×E) פעם אחת, O(1) lookup
  static Map<String, Map<String, _SegmentViolation>> _buildSegmentViolationMatrix(
    List<_SimpleCheckpoint> allPoints,
    List<List<double>>? boundaryCoords,
    List<List<List<double>>>? safetyPolygons,
  ) {
    final matrix = <String, Map<String, _SegmentViolation>>{};
    for (final p in allPoints) {
      matrix[p.id] = {};
    }

    // בניית אובייקט turf Polygon פעם אחת לפני הלולאה O(P²)
    turf.Polygon? boundaryPolygon;
    if (boundaryCoords != null && boundaryCoords.length >= 3) {
      final ring = boundaryCoords.map((c) => turf.Position(c[1], c[0])).toList();
      if (ring.first.lng != ring.last.lng || ring.first.lat != ring.last.lat) {
        ring.add(ring.first);
      }
      boundaryPolygon = turf.Polygon(coordinates: [ring]);
    }

    // Bounding-box של הפוליגון — לסינון מהיר O(1) לפני turf
    double? bMinLat, bMaxLat, bMinLng, bMaxLng;
    if (boundaryCoords != null && boundaryCoords.isNotEmpty) {
      bMinLat = bMaxLat = boundaryCoords.first[0];
      bMinLng = bMaxLng = boundaryCoords.first[1];
      for (final c in boundaryCoords) {
        if (c[0] < bMinLat!) bMinLat = c[0];
        if (c[0] > bMaxLat!) bMaxLat = c[0];
        if (c[1] < bMinLng!) bMinLng = c[1];
        if (c[1] > bMaxLng!) bMaxLng = c[1];
      }
    }

    int boundaryViolationPairs = 0;
    int safetyViolationPairs = 0;

    for (int i = 0; i < allPoints.length; i++) {
      final a = allPoints[i];
      matrix[a.id]![a.id] = _SegmentViolation.none;

      for (int j = i + 1; j < allPoints.length; j++) {
        final b = allPoints[j];

        // בדיקת יציאה מגבול — bbox reject + turf lineIntersect
        int crossings = 0;
        if (boundaryCoords != null && boundaryPolygon != null) {
          // bbox reject: אם segment bbox לא חופף ל-polygon bbox → endpoint check יתפוס
          final segMinLat = a.lat < b.lat ? a.lat : b.lat;
          final segMaxLat = a.lat > b.lat ? a.lat : b.lat;
          final segMinLng = a.lng < b.lng ? a.lng : b.lng;
          final segMaxLng = a.lng > b.lng ? a.lng : b.lng;
          final bboxOverlaps = segMaxLat >= bMinLat! && segMinLat <= bMaxLat! &&
                               segMaxLng >= bMinLng! && segMinLng <= bMaxLng!;
          if (bboxOverlaps) {
            final result = _segmentExitsBoundary(
              a.lat, a.lng, b.lat, b.lng, boundaryCoords, boundaryPolygon);
            crossings = result.crossingCount;
          } else {
            // מחוץ ל-bbox — endpoint check
            if (!_pointInPolygon(a.lat, a.lng, boundaryCoords) ||
                !_pointInPolygon(b.lat, b.lng, boundaryCoords)) {
              crossings = 1;
            }
          }
        }

        // בדיקת חיתוך נת"בים
        int safetyCrossed = 0;
        if (safetyPolygons != null) {
          for (final poly in safetyPolygons) {
            if (_segmentIntersectsPolygon(a.lat, a.lng, b.lat, b.lng, poly)) {
              safetyCrossed++;
            }
          }
        }

        if (crossings > 0) boundaryViolationPairs++;
        if (safetyCrossed > 0) safetyViolationPairs++;

        final violation = (crossings > 0 || safetyCrossed > 0)
            ? _SegmentViolation(crossings, safetyCrossed)
            : _SegmentViolation.none;
        matrix[a.id]![b.id] = violation;
        matrix[b.id]![a.id] = violation;
      }
    }

    final totalPairs = allPoints.length * (allPoints.length - 1) ~/ 2;
    print('[ViolationMatrix] $totalPairs pairs checked: '
        '$boundaryViolationPairs boundary violations, '
        '$safetyViolationPairs safety violations');

    return matrix;
  }

  /// O(1) lookup של הפרת קטע
  static int _lookupViolationCount(
    String id1, String id2,
    Map<String, Map<String, _SegmentViolation>> violationMatrix,
  ) {
    final v = violationMatrix[id1]?[id2];
    if (v == null || !v.hasViolation) return 0;
    return v.boundaryCrossings + v.safetyPolygonsCrossed;
  }

  /// ספירת הפרות קטעים לרצף נתון (כולל start/end)
  static ({int boundaryExits, int safetyIntersections}) _countSequenceViolations(
    List<String> sequenceIds,
    String? startId,
    String? endId,
    Map<String, Map<String, _SegmentViolation>>? violationMatrix,
  ) {
    if (violationMatrix == null) return (boundaryExits: 0, safetyIntersections: 0);

    final fullSeq = <String>[
      if (startId != null) startId,
      ...sequenceIds,
      if (endId != null) endId,
    ];

    int be = 0, si = 0;
    for (int i = 0; i < fullSeq.length - 1; i++) {
      final v = violationMatrix[fullSeq[i]]?[fullSeq[i + 1]];
      if (v != null && v.hasViolation) {
        be += v.boundaryCrossings;
        si += v.safetyPolygonsCrossed;
      }
    }
    return (boundaryExits: be, safetyIntersections: si);
  }

  /// שיוך מנווטים לנקודות הצנחה
  static Map<String, String> _assignDropPoints({
    required List<String> navigators,
    required ParachuteSettings settings,
    Map<String, List<String>>? subFrameworkNavigators, // sfId -> [navigatorIds]
  }) {
    final dropPointIds = settings.dropPointIds;
    if (dropPointIds.isEmpty) return {};

    switch (settings.assignmentMethod) {
      case 'manual':
        // Use existing assignments
        return Map<String, String>.from(settings.navigatorDropPoints);

      case 'by_sub_framework':
        final result = <String, String>{};
        final sfNavigators = subFrameworkNavigators ?? {};
        final sfDropPoints = settings.subFrameworkDropPoints;

        for (final entry in sfNavigators.entries) {
          final sfId = entry.key;
          final sfNavs = entry.value;
          final sfPoints = sfDropPoints[sfId] ?? dropPointIds;
          if (sfPoints.isEmpty || sfNavs.isEmpty) continue;

          if (settings.samePointPerSubFramework) {
            // All navigators in SF get the same random drop point
            final point = sfPoints[Random().nextInt(sfPoints.length)];
            for (final nav in sfNavs) {
              result[nav] = point;
            }
          } else {
            // Round-robin across SF's drop points
            for (var i = 0; i < sfNavs.length; i++) {
              result[sfNavs[i]] = sfPoints[i % sfPoints.length];
            }
          }
        }
        return result;

      case 'random':
      default:
        // Round-robin shuffle across drop points
        final shuffled = List<String>.from(navigators)..shuffle();
        final result = <String, String>{};
        for (var i = 0; i < shuffled.length; i++) {
          result[shuffled[i]] = dropPointIds[i % dropPointIds.length];
        }
        return result;
    }
  }

  /// מיפוי מנווטים לפי תת-מסגרת (sfId -> navigatorIds)
  Future<Map<String, List<String>>> _getSubFrameworkNavigators(
    domain.Navigation navigation,
    NavigationTree tree,
  ) async {
    final result = <String, List<String>>{};
    for (final sf in tree.subFrameworks) {
      if (!navigation.selectedSubFrameworkIds.contains(sf.id)) continue;
      if (sf.isFixed) continue;
      final navIds = <String>[];
      for (final uid in sf.userIds) {
        final user = await _userRepository.getUser(uid);
        if (user != null && user.role == 'navigator') {
          navIds.add(uid);
        }
      }
      if (navIds.isNotEmpty) {
        result[sf.id] = navIds;
      }
    }
    return result;
  }

  /// חלוקת ניווט צנחנים — כל מנווט מתחיל מנקודת הצנחה שונה
  /// משתמש באלגוריתם ה-Isolate הרגיל ואז מחליף את נקודת ההתחלה per-navigator
  Future<domain.DistributionResult> _distributeParachuteNavigation({
    required domain.Navigation navigation,
    required NavigationTree tree,
    required List<String> navigators,
    required List<String> virtualNavigators,
    required Map<String, List<String>> groups,
    required List<Map<String, dynamic>> checkpointMaps,
    required List<Map<String, dynamic>> waypointMaps,
    required List<Checkpoint> availableCheckpoints,
    Boundary? boundary,
    String? startPointId,
    String? endPointId,
    required String executionOrder,
    required int checkpointsPerNavigator,
    required double minRouteLength,
    required double maxRouteLength,
    String scoringCriterion = 'fairness',
    required ForceComposition composition,
    List<SafetyPoint> safetyPoints = const [],
    void Function(int current, int total)? onProgress,
  }) async {
    final parachuteSettings = navigation.parachuteSettings;
    if (parachuteSettings == null || parachuteSettings.dropPointIds.isEmpty) {
      throw Exception('לא נבחרו נקודות הצנחה');
    }

    // 1. שיוך מנווטים לנקודות הצנחה
    Map<String, String> dropPointAssignments;
    if (parachuteSettings.assignmentMethod == 'manual' &&
        parachuteSettings.navigatorDropPoints.isNotEmpty) {
      dropPointAssignments = Map<String, String>.from(parachuteSettings.navigatorDropPoints);
    } else {
      Map<String, List<String>>? sfNavigators;
      if (parachuteSettings.assignmentMethod == 'by_sub_framework') {
        sfNavigators = await _getSubFrameworkNavigators(navigation, tree);
      }
      dropPointAssignments = _assignDropPoints(
        navigators: navigators,
        settings: parachuteSettings,
        subFrameworkNavigators: sfNavigators,
      );
    }

    // 2. הסרת נקודות הצנחה מפול הנקודות (הן משמשות כנקודות התחלה)
    final dropPointIdSet = parachuteSettings.dropPointIds.toSet();
    final filteredCheckpointMaps = checkpointMaps
        .where((m) => !dropPointIdSet.contains(m['id']))
        .toList();

    // סריאליזציית גיאומטריה ל-Isolate
    final List<List<double>>? serializedBoundary = (boundary != null && boundary.coordinates.length >= 3)
        ? boundary.coordinates.map((c) => [c.lat, c.lng]).toList()
        : null;
    final List<List<List<double>>>? serializedSafetyPolygons = safetyPoints
        .where((sp) => sp.type == 'polygon' && sp.polygonCoordinates != null && sp.polygonCoordinates!.length >= 3)
        .map((sp) => sp.polygonCoordinates!.map((c) => [c.lat, c.lng]).toList())
        .toList();
    final effectiveSafetyPolygons = (serializedSafetyPolygons != null && serializedSafetyPolygons.isNotEmpty)
        ? serializedSafetyPolygons : null;

    // 3. הרצת האלגוריתם הרגיל ב-Isolate (ללא נקודת התחלה — תוחלף per-navigator)
    final isolateResult = await _runInIsolate(
      navigators: virtualNavigators,
      checkpointMaps: filteredCheckpointMaps,
      startPointId: null, // אין נקודת התחלה גלובלית — כל מנווט מתחיל מנקודה אחרת
      endPointId: endPointId,
      waypointMaps: waypointMaps,
      executionOrder: executionOrder,
      checkpointsPerNavigator: checkpointsPerNavigator,
      minRouteLength: minRouteLength,
      maxRouteLength: maxRouteLength,
      scoringCriterion: scoringCriterion,
      onProgress: onProgress,
      boundaryCoords: serializedBoundary,
      safetyPolygons: effectiveSafetyPolygons,
    );

    // 4. החלפת נקודת התחלה per-navigator לפי שיוך נקודות הצנחה
    final updatedRoutes = <String, domain.AssignedRoute>{};

    if (composition.isGroupedPairOrSquad && groups.isNotEmpty) {
      // הרחבת קבוצות + שיוך drop point per-member
      for (final entry in isolateResult.routes.entries) {
        final groupId = entry.key;
        final route = entry.value;
        final members = groups[groupId];
        if (members == null) continue;

        for (final memberId in members) {
          final dropPointId = dropPointAssignments[memberId];
          // עדכון רצף: drop point בהתחלה
          final updatedSequence = <String>[
            if (dropPointId != null) dropPointId,
            ...route.sequence,
          ];
          updatedRoutes[memberId] = route.copyWith(
            startPointId: dropPointId,
            groupId: groupId,
            sequence: updatedSequence,
          );
        }
      }
    } else {
      // solo — כל מנווט מקבל את ה-drop point שלו כנקודת התחלה
      for (final entry in isolateResult.routes.entries) {
        final navId = entry.key;
        final route = entry.value;
        final dropPointId = dropPointAssignments[navId];
        // עדכון רצף: drop point בהתחלה
        final updatedSequence = <String>[
          if (dropPointId != null) dropPointId,
          ...route.sequence,
        ];
        updatedRoutes[navId] = route.copyWith(
          startPointId: dropPointId,
          sequence: updatedSequence,
        );
      }
    }

    return domain.DistributionResult(
      status: isolateResult.status,
      routes: updatedRoutes,
      approvalOptions: isolateResult.approvalOptions,
      hasSharedCheckpoints: isolateResult.hasSharedCheckpoints,
      sharedCheckpointCount: isolateResult.sharedCheckpointCount,
      forceComposition: composition.isGrouped
          ? composition.copyWith(manualGroups: groups)
          : null,
    );
  }

  /// המרת תוצאת Isolate ל-DistributionResult
  domain.DistributionResult _parseIsolateResult(
    Map<String, dynamic> data,
    List<String> navigators,
    String? startPointId,
    String? endPointId,
    double minRouteLength,
    double maxRouteLength,
    int checkpointsPerNavigator,
  ) {
    final routesData = data['routes'] as Map<String, Map<String, dynamic>>;
    final allInRange = data['allInRange'] as bool;
    final hasSharing = data['hasSharedCheckpoints'] as bool;
    final sharedCount = data['sharedCount'] as int;

    final routes = <String, domain.AssignedRoute>{};
    int outOfRangeCount = 0;

    for (final entry in routesData.entries) {
      final r = entry.value;
      final routeLength = (r['routeLengthKm'] as num).toDouble();

      String status;
      if (routeLength < minRouteLength) {
        status = 'too_short';
        outOfRangeCount++;
      } else if (routeLength > maxRouteLength) {
        status = 'too_long';
        outOfRangeCount++;
      } else {
        status = 'optimal';
      }

      routes[entry.key] = domain.AssignedRoute(
        checkpointIds: List<String>.from(r['checkpointIds'] as List),
        routeLengthKm: routeLength,
        sequence: List<String>.from(r['sequence'] as List),
        startPointId: startPointId,
        endPointId: endPointId,
        waypointIds: List<String>.from(r['waypointIds'] as List),
        status: status,
        isVerified: false,
      );
    }

    // ולידציית K-invariant: כל מנווט חייב לקבל בדיוק checkpointsPerNavigator נקודות
    for (final entry in routes.entries) {
      if (entry.value.checkpointIds.length != checkpointsPerNavigator) {
        throw StateError(
          'Navigator ${entry.key} has ${entry.value.checkpointIds.length} checkpoints, expected $checkpointsPerNavigator'
        );
      }
    }

    if (allInRange) {
      return domain.DistributionResult(
        status: 'success',
        routes: routes,
        hasSharedCheckpoints: hasSharing,
        sharedCheckpointCount: sharedCount,
      );
    }

    // --- שלב 3: צריך אישור ---
    final approvalOptions = <domain.ApprovalOption>[
      domain.ApprovalOption(
        type: 'expand_range',
        label: 'הרחב טווח ל-${(minRouteLength * 0.8).toStringAsFixed(1)} — ${(maxRouteLength * 1.2).toStringAsFixed(1)} ק"מ',
        expandedMin: minRouteLength * 0.8,
        expandedMax: maxRouteLength * 1.2,
      ),
      if (checkpointsPerNavigator > 1)
        domain.ApprovalOption(
          type: 'reduce_checkpoints',
          label: 'הורד ל-${checkpointsPerNavigator - 1} נקודות למנווט',
          reducedCheckpoints: checkpointsPerNavigator - 1,
        ),
      domain.ApprovalOption(
        type: 'accept_best',
        label: 'אשר חלוקה ($outOfRangeCount צירים חורגים)',
        outOfRangeCount: outOfRangeCount,
      ),
    ];

    return domain.DistributionResult(
      status: 'needs_approval',
      routes: routes,
      approvalOptions: approvalOptions,
      hasSharedCheckpoints: hasSharing,
      sharedCheckpointCount: sharedCount,
    );
  }
}
