import 'dart:math';
import 'dart:isolate';
import '../domain/entities/navigation.dart' as domain;
import '../domain/entities/checkpoint.dart';
import '../domain/entities/navigation_tree.dart';
import '../domain/entities/navigation_settings.dart';
import '../domain/entities/boundary.dart';
import '../core/utils/geometry_utils.dart';
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
  final double? afterDistanceKm;
  final int? afterCheckpointIndex;
  final int? beforeCheckpointIndex;

  _SimpleWaypoint({
    required this.checkpointId,
    required this.placementType,
    this.afterDistanceKm,
    this.afterCheckpointIndex,
    this.beforeCheckpointIndex,
  });

  factory _SimpleWaypoint.fromMap(Map<String, dynamic> map) {
    return _SimpleWaypoint(
      checkpointId: map['checkpointId'] as String,
      placementType: map['placementType'] as String,
      afterDistanceKm: (map['afterDistanceKm'] as num?)?.toDouble(),
      afterCheckpointIndex: map['afterCheckpointIndex'] as int?,
      beforeCheckpointIndex: map['beforeCheckpointIndex'] as int?,
    );
  }
}

/// תוצאת ציר פנימית
class _RouteResult {
  final List<String> checkpointIds;
  final List<String> sequence;
  final List<String> waypointIds;
  final double routeLengthKm;
  final bool inRange;

  _RouteResult({
    required this.checkpointIds,
    required this.sequence,
    required this.waypointIds,
    required this.routeLengthKm,
    required this.inRange,
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
    void Function(int current, int total)? onProgress,
  }) async {
    // --- שלב 1: הכנה ---
    // מציאת משתתפים
    List<String> navigators = await _findNavigators(navigation, tree);

    if (navigators.isEmpty) {
      throw Exception('לא נמצאו משתתפים - יש לבחור תתי-מסגרות עם משתמשים');
    }

    if (checkpoints.isEmpty) {
      throw Exception('לא נמצאו נקודות ציון');
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

    final waypointMaps = waypoints.map((w) => w.toMap()).toList();

    // --- שלב 2: הרצת אלגוריתם ב-Isolate ---
    final result = await _runInIsolate(
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
      onProgress: onProgress,
    );

    return result;
  }

  final UserRepository _userRepository = UserRepository();

  /// מציאת משתתפים — מנווטים בלבד (ללא מפקדים/מנהלים)
  Future<List<String>> _findNavigators(domain.Navigation navigation, NavigationTree tree) async {
    // 1. אם נבחרו משתתפים ספציפיים — סינון לפי תפקיד (backward compat)
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
      final navigators = <String>[];
      for (final sf in tree.subFrameworks) {
        if (!navigation.selectedSubFrameworkIds.contains(sf.id)) continue;
        // דילוג על תת-מסגרות מפקדים — מפקדים לא מקבלים צירים
        if (sf.name.contains('מפקדים') || sf.name.contains('מפקד')) continue;
        final users = await _userRepository.getNavigatorsForUnit(unitId);
        navigators.addAll(users.map((u) => u.uid));
      }
      return navigators;
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
    );

    // הרצה ב-Isolate
    final isolate = await Isolate.spawn(_isolateWorker, params);

    Map<String, dynamic>? resultData;
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
        }
      }
    }

    receivePort.close();
    isolate.kill(priority: Isolate.immediate);

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
    final random = Random();

    // המרת נתונים
    final checkpoints = params.checkpointMaps.map((m) => _SimpleCheckpoint.fromMap(m)).toList();
    final waypoints = params.waypointMaps.map((m) => _SimpleWaypoint.fromMap(m)).toList();
    final navigators = params.navigators;
    final K = params.checkpointsPerNavigator;
    final N = navigators.length;

    // סינון נקודות התחלה/סיום מהפול
    final pool = checkpoints
        .where((cp) => cp.id != params.startPointId && cp.id != params.endPointId)
        .toList();

    // מציאת נקודות התחלה/סיום
    final startCp = params.startPointId != null
        ? checkpoints.where((cp) => cp.id == params.startPointId).firstOrNull
        : null;
    final endCp = params.endPointId != null
        ? checkpoints.where((cp) => cp.id == params.endPointId).firstOrNull
        : null;

    // מציאת waypoint checkpoints
    final waypointCps = <_SimpleCheckpoint>[];
    for (final wp in waypoints) {
      final cp = checkpoints.where((c) => c.id == wp.checkpointId).firstOrNull;
      if (cp != null) waypointCps.add(cp);
    }

    // Phase 1: בניית מטריצת מרחקים פעם אחת — כל הנקודות הייחודיות
    final allPoints = <_SimpleCheckpoint>[];
    final seenIds = <String>{};
    for (final cp in checkpoints) {
      if (seenIds.add(cp.id)) allPoints.add(cp);
    }
    final distMatrix = _buildDistanceMatrix(allPoints);

    final bool needsSharing = pool.length < N * K ||
        params.scoringCriterion == 'doubleCheck'; // doubleCheck דורש חפיפה מכוונת

    // --- שלב 2: חיפוש Monte Carlo (ייחודי) ---
    _InternalDistribution? bestDistribution;

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
      );
    }

    // --- שלב 2.5: Fallback — שיתוף נקודות ---
    if (bestDistribution == null || !bestDistribution.allInRange) {
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
      );

      // העדפת תוצאה טובה יותר
      if (bestDistribution == null ||
          sharedResult.score > bestDistribution.score) {
        bestDistribution = sharedResult;
      }
    }

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
  }) {
    _InternalDistribution? best;
    final targetLength = (minRoute + maxRoute) / 2;

    // 100 בניות התחלתיות × SA על כל אחת
    final constructionRounds = min(100, maxIterations);
    final saStepsPerRound = 200;

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
      );

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
      if (allInRange && !hasSharing) {
        final routeLengths = optimized.values.map((r) => r.routeLengthKm).toList();
        final meanLen = routeLengths.reduce((a, b) => a + b) / routeLengths.length;
        final varianceLen = routeLengths.map((l) => (l - meanLen) * (l - meanLen)).reduce((a, b) => a + b) / routeLengths.length;
        if (varianceLen < 0.01) break;
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
      );

      if (chunk.length < K) return null;

      if (!allowSharing) {
        for (final cp in chunk) {
          usedGlobally.add(cp.id);
        }
      }

      // אופטימיזציית רצף
      final sequence = _optimizeSequence(chunk, startCp, endCp, executionOrder, distMatrix);

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

      distribution[navigators[navIdx]] = _RouteResult(
        checkpointIds: chunk.map((cp) => cp.id).toList(),
        sequence: sequence.map((cp) => cp.id).toList(),
        waypointIds: waypointIds,
        routeLengthKm: routeLength,
        inRange: inRange,
      );
    }

    return distribution;
  }

  /// חלוקה גיאוגרפית — מיון לפי קו רוחב + חלוקת round-robin
  static List<List<_SimpleCheckpoint>> _geographicPartition(
    List<_SimpleCheckpoint> pool,
    int N,
    Random random,
  ) {
    if (N <= 0 || pool.isEmpty) return [];

    // מיון לפי קו רוחב
    final sorted = List<_SimpleCheckpoint>.from(pool)
      ..sort((a, b) => a.lat.compareTo(b.lat));

    // חלוקת round-robin ל-N דליים
    final buckets = List.generate(N, (_) => <_SimpleCheckpoint>[]);
    for (int i = 0; i < sorted.length; i++) {
      buckets[i % N].add(sorted[i]);
    }

    // ערבוב הקצאת דליים
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

      // ניקוד כל מועמד לפי קרבה למרחק היעד
      final scored = <MapEntry<_SimpleCheckpoint, double>>[];
      for (final cp in remaining) {
        final dist = currentId != null
            ? _dist(currentId, cp.id, distMatrix)
            : 0.0;
        final diff = (dist - idealSegment).abs();
        scored.add(MapEntry(cp, diff));
      }

      // מיון לפי קרבה למרחק אידיאלי
      scored.sort((a, b) => a.value.compareTo(b.value));

      // Phase 6: Boltzmann selection מתוך 10 מועמדים (במקום top-3 אקראי)
      final topN = min(10, scored.length);
      final candidates = scored.sublist(0, topN);
      final bestDiff = candidates.first.value;
      final weights = candidates.map((e) => exp(-(e.value - bestDiff) / 0.5)).toList();
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

    return route;
  }

  /// Simulated Annealing — 3 סוגי מהלכים + reheat על סטגנציה
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
    var currentScore = _calculateFullScore(currentRoutes, criterion, minRoute, maxRoute);

    // בניית free pool — נקודות שלא בשום ציר
    final freePool = <String>{};
    if (!allowSharing) {
      final usedIds = routeChunks.values.expand((r) => r.map((c) => c.id)).toSet();
      for (final cp in pool) {
        if (!usedIds.contains(cp.id)) freePool.add(cp.id);
      }
    }

    // טמפרטורה יורדת מ-1.0 ל-0.01 לאורך כל הצעדים
    double temperature = 1.0;
    final coolingRate = steps > 1 ? pow(0.01, 1.0 / steps).toDouble() : 0.01;

    // Reheat tracking
    double bestSAScore = currentScore;
    int noImprovementCount = 0;

    for (int step = 0; step < steps; step++) {
      temperature *= coolingRate;

      // בחירת סוג מהלך: 50% swap, 25% move, 25% 2-opt intra
      final moveRoll = random.nextDouble();

      if (moveRoll < 0.50) {
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
        if (!allowSharing) {
          if (route1.any((c) => c.id == cp2.id) || route2.any((c) => c.id == cp1.id)) continue;
        }

        route1[idx1] = cp2;
        route2[idx2] = cp1;

        final newResult1 = _rebuildRoute(route1, startCp, endCp, waypoints, allCheckpoints, executionOrder, minRoute, maxRoute, distMatrix);
        final newResult2 = _rebuildRoute(route2, startCp, endCp, waypoints, allCheckpoints, executionOrder, minRoute, maxRoute, distMatrix);

        final testRoutes = Map<String, _RouteResult>.from(currentRoutes);
        testRoutes[nav1] = newResult1;
        testRoutes[nav2] = newResult2;
        final newScore = _calculateFullScore(testRoutes, criterion, minRoute, maxRoute);

        final delta = newScore - currentScore;
        if (delta > 0 || random.nextDouble() < exp(delta / (temperature * 1000))) {
          currentRoutes = testRoutes;
          currentScore = newScore;
        } else {
          route1[idx1] = cp1;
          route2[idx2] = cp2;
        }

      } else if (moveRoll < 0.75 && (freePool.isNotEmpty || allowSharing)) {
        // === MOVE: החלפת נקודה בציר עם נקודה מהפול החופשי ===
        final navIdx = random.nextInt(navigators.length);
        final nav = navigators[navIdx];
        final route = routeChunks[nav];
        if (route == null || route.isEmpty) continue;

        final removeIdx = random.nextInt(route.length);
        final oldCp = route[removeIdx];

        _SimpleCheckpoint? newCp;
        if (allowSharing) {
          final candidate = pool[random.nextInt(pool.length)];
          if (candidate.id == oldCp.id) continue;
          newCp = candidate;
        } else {
          if (freePool.isEmpty) continue;
          final freeList = freePool.toList();
          final newId = freeList[random.nextInt(freeList.length)];
          newCp = cpMap[newId];
          if (newCp == null) continue;
        }

        if (!allowSharing && route.any((c) => c.id == newCp!.id)) continue;

        route[removeIdx] = newCp;
        if (!allowSharing) {
          freePool.remove(newCp.id);
          freePool.add(oldCp.id);
        }

        final newResult = _rebuildRoute(route, startCp, endCp, waypoints, allCheckpoints, executionOrder, minRoute, maxRoute, distMatrix);
        final testRoutes = Map<String, _RouteResult>.from(currentRoutes);
        testRoutes[nav] = newResult;
        final newScore = _calculateFullScore(testRoutes, criterion, minRoute, maxRoute);

        final delta = newScore - currentScore;
        if (delta > 0 || random.nextDouble() < exp(delta / (temperature * 1000))) {
          currentRoutes = testRoutes;
          currentScore = newScore;
        } else {
          route[removeIdx] = oldCp;
          if (!allowSharing) {
            freePool.add(newCp.id);
            freePool.remove(oldCp.id);
          }
        }

      } else {
        // === 2-OPT INTRA: היפוך תת-רצף בתוך ציר בודד ===
        final navIdx = random.nextInt(navigators.length);
        final nav = navigators[navIdx];
        final route = routeChunks[nav];
        if (route == null || route.length < 3) continue;

        var i = random.nextInt(route.length);
        var j = random.nextInt(route.length);
        if (i == j) continue;
        if (i > j) { final tmp = i; i = j; j = tmp; }

        // היפוך הסגמנט i..j
        int left = i, right = j;
        while (left < right) {
          final temp = route[left];
          route[left] = route[right];
          route[right] = temp;
          left++;
          right--;
        }

        final newResult = _rebuildRoute(route, startCp, endCp, waypoints, allCheckpoints, executionOrder, minRoute, maxRoute, distMatrix);
        final testRoutes = Map<String, _RouteResult>.from(currentRoutes);
        testRoutes[nav] = newResult;
        final newScore = _calculateFullScore(testRoutes, criterion, minRoute, maxRoute);

        final delta = newScore - currentScore;
        if (delta > 0 || random.nextDouble() < exp(delta / (temperature * 1000))) {
          currentRoutes = testRoutes;
          currentScore = newScore;
        } else {
          // undo: היפוך חזרה
          left = i;
          right = j;
          while (left < right) {
            final temp = route[left];
            route[left] = route[right];
            route[right] = temp;
            left++;
            right--;
          }
        }
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

    return currentRoutes;
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
    Map<String, Map<String, double>> distMatrix,
  ) {
    final sequence = _optimizeSequence(chunk, startCp, endCp, executionOrder, distMatrix);
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
    return _RouteResult(
      checkpointIds: chunk.map((c) => c.id).toList(),
      sequence: sequence.map((c) => c.id).toList(),
      waypointIds: waypointIds,
      routeLengthKm: length,
      inRange: length >= minRoute && length <= maxRoute,
    );
  }

  /// חישוב ניקוד כולל לחלוקה
  static double _calculateFullScore(
    Map<String, _RouteResult> distribution,
    String criterion,
    double minRoute,
    double maxRoute,
  ) {
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
    );
  }

  /// אופטימיזציית רצף: nearest-neighbor TSP + 2-opt improvement
  static List<_SimpleCheckpoint> _optimizeSequence(
    List<_SimpleCheckpoint> chunk,
    _SimpleCheckpoint? startCp,
    _SimpleCheckpoint? endCp,
    String executionOrder,
    Map<String, Map<String, double>> distMatrix,
  ) {
    if (chunk.length <= 1 || executionOrder != 'sequential') {
      return List.from(chunk);
    }

    // שלב 1: Nearest-neighbor מנקודת ההתחלה
    final remaining = List<_SimpleCheckpoint>.from(chunk);
    final result = <_SimpleCheckpoint>[];

    _SimpleCheckpoint current;
    if (startCp != null) {
      remaining.sort((a, b) =>
          _dist(startCp.id, a.id, distMatrix)
          .compareTo(_dist(startCp.id, b.id, distMatrix)));
      current = remaining.removeAt(0);
    } else {
      current = remaining.removeAt(0);
    }
    result.add(current);

    while (remaining.isNotEmpty) {
      remaining.sort((a, b) =>
          _dist(current.id, a.id, distMatrix)
          .compareTo(_dist(current.id, b.id, distMatrix)));
      current = remaining.removeAt(0);
      result.add(current);
    }

    // שלב 2: 2-opt improvement — שיפור הרצף ע"י היפוך סגמנטים
    if (result.length >= 3) {
      bool improved = true;
      int passes = 0;
      while (improved && passes < 10) {
        improved = false;
        passes++;
        for (int i = 0; i < result.length - 1; i++) {
          for (int j = i + 1; j < result.length; j++) {
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

    return result;
  }

  /// בניית ציר מלא עם waypoints
  static Map<String, dynamic> _buildRouteWithWaypoints({
    required List<_SimpleCheckpoint> chunk,
    required List<_SimpleCheckpoint> sequence,
    required _SimpleCheckpoint? startCp,
    required _SimpleCheckpoint? endCp,
    required List<_SimpleWaypoint> waypoints,
    required List<_SimpleCheckpoint> allCheckpoints,
    required Map<String, Map<String, double>> distMatrix,
  }) {
    // בניית רצף בסיסי: start → sequence → end
    final fullSequence = <_SimpleCheckpoint>[];
    if (startCp != null) fullSequence.add(startCp);
    fullSequence.addAll(sequence);
    if (endCp != null) fullSequence.add(endCp);

    // הכנסת waypoints
    final waypointIds = <String>[];
    if (waypoints.isNotEmpty) {
      for (final wp in waypoints) {
        final wpCp = allCheckpoints.where((c) => c.id == wp.checkpointId).firstOrNull;
        if (wpCp == null) continue;

        waypointIds.add(wp.checkpointId);

        if (wp.placementType == 'distance' && wp.afterDistanceKm != null) {
          // הכנסה לפי מרחק
          double cumDistance = 0;
          int insertIndex = -1;
          for (int i = 0; i < fullSequence.length - 1; i++) {
            cumDistance += _dist(fullSequence[i].id, fullSequence[i + 1].id, distMatrix);
            if (cumDistance >= wp.afterDistanceKm!) {
              insertIndex = i + 1;
              break;
            }
          }
          if (insertIndex > 0 && insertIndex <= fullSequence.length) {
            fullSequence.insert(insertIndex, wpCp);
          } else {
            // אם לא הגענו למרחק, הכנס לפני הסוף
            final endIndex = endCp != null ? fullSequence.length - 1 : fullSequence.length;
            fullSequence.insert(endIndex, wpCp);
          }
        } else if (wp.placementType == 'between_checkpoints') {
          // הכנסה בין נקודות ספציפיות
          final afterIdx = wp.afterCheckpointIndex ?? 0;
          final startOffset = startCp != null ? 1 : 0;
          final insertAt = startOffset + afterIdx + 1;
          if (insertAt <= fullSequence.length) {
            fullSequence.insert(insertAt.clamp(0, fullSequence.length), wpCp);
          }
        }
      }
    }

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
  }) {
    final lengths = distribution.values.map((r) => r.routeLengthKm).toList();
    if (lengths.isEmpty) return -999999;

    // Soft range penalty — ריבועי: SA "מרגיש" כמה רחוק מהטווח
    double rangePenalty = 0;
    for (final r in distribution.values) {
      if (r.routeLengthKm < minRoute) {
        final diff = minRoute - r.routeLengthKm;
        rangePenalty += diff * diff * 500;
      } else if (r.routeLengthKm > maxRoute) {
        final diff = r.routeLengthKm - maxRoute;
        rangePenalty += diff * diff * 500;
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
        return -cv * 5000 - rangePenalty + allInRangeBonus + uniqueBonus;

      case 'midpoint':
        // קרבה לאמצע הטווח
        final midpoint = (minRoute + maxRoute) / 2;
        final deviation = lengths.map((l) => (l - midpoint).abs()).reduce((a, b) => a + b);
        final maxDeviation = lengths.map((l) => (l - midpoint).abs()).reduce(max);
        return -deviation * 200 - maxDeviation * 300 - rangePenalty + allInRangeBonus + uniqueBonus;

      case 'uniqueness':
        // מקסימום ייחודיות
        return totalUniqueCheckpoints * 1000.0 - rangePenalty + allInRangeBonus - variance * 10;

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
            - rangePenalty + allInRangeBonus - variance * 50;

      default:
        return -cv * 5000 - rangePenalty + allInRangeBonus + uniqueBonus;
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
  }) {
    final distribution = <String, _RouteResult>{};
    bool allInRange = true;
    int usedIdx = 0;

    for (int i = 0; i < navigators.length; i++) {
      final chunk = <_SimpleCheckpoint>[];
      for (int j = 0; j < K && usedIdx < pool.length; j++, usedIdx++) {
        chunk.add(pool[usedIdx % pool.length]);
      }

      // אם אין מספיק, מחזור
      while (chunk.length < K) {
        chunk.add(pool[chunk.length % pool.length]);
      }

      final sequence = _optimizeSequence(chunk, startCp, endCp, executionOrder, distMatrix);
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

      distribution[navigators[i]] = _RouteResult(
        checkpointIds: chunk.map((c) => c.id).toList(),
        sequence: sequence.map((c) => c.id).toList(),
        waypointIds: waypointIds,
        routeLengthKm: length,
        inRange: inRange,
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
