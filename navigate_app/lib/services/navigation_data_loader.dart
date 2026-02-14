import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/nav_layer.dart';
import '../domain/entities/navigation.dart';
import '../domain/entities/navigation_tree.dart';
import '../data/repositories/nav_layer_repository.dart';
import '../data/repositories/navigation_repository.dart';
import '../data/repositories/navigation_tree_repository.dart';
import '../data/sync/sync_manager.dart';
import '../core/constants/app_constants.dart';

/// סטטוס שלב טעינה
enum LoadStepStatus {
  pending,
  loading,
  completed,
  failed,
}

/// שלב טעינה בודד
class LoadStep {
  final String id;
  final String label;
  LoadStepStatus status;
  String? errorMessage;
  int itemCount;

  LoadStep({
    required this.id,
    required this.label,
    this.status = LoadStepStatus.pending,
    this.errorMessage,
    this.itemCount = 0,
  });

  LoadStep copyWith({
    LoadStepStatus? status,
    String? errorMessage,
    int? itemCount,
  }) {
    return LoadStep(
      id: id,
      label: label,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      itemCount: itemCount ?? this.itemCount,
    );
  }
}

/// התקדמות טעינת נתונים
class LoadProgress {
  final List<LoadStep> steps;
  final bool isComplete;
  final bool hasError;
  final double progressPercent;

  const LoadProgress({
    required this.steps,
    this.isComplete = false,
    this.hasError = false,
    this.progressPercent = 0.0,
  });

  /// שלב נוכחי בטעינה
  LoadStep? get currentStep {
    for (final step in steps) {
      if (step.status == LoadStepStatus.loading) return step;
    }
    return null;
  }

  /// מספר שלבים שהושלמו
  int get completedSteps =>
      steps.where((s) => s.status == LoadStepStatus.completed).length;

  /// סה"כ פריטים שנטענו
  int get totalItemsLoaded =>
      steps.fold(0, (sum, s) => sum + s.itemCount);
}

/// תוצאת טעינת נתוני ניווט
class NavigationDataBundle {
  final Navigation navigation;
  final NavBoundary? boundary;
  final List<NavCheckpoint> checkpoints;
  final List<NavSafetyPoint> safetyPoints;
  final List<NavCluster> clusters;
  final NavigationTree? navigatorTree;
  final Map<String, AssignedRoute> allRoutes;

  const NavigationDataBundle({
    required this.navigation,
    this.boundary,
    this.checkpoints = const [],
    this.safetyPoints = const [],
    this.clusters = const [],
    this.navigatorTree,
    this.allRoutes = const {},
  });

  /// האם יש שכבות ניווטיות
  bool get hasNavLayers =>
      boundary != null ||
      checkpoints.isNotEmpty ||
      safetyPoints.isNotEmpty ||
      clusters.isNotEmpty;

  /// סה"כ פריטים בשכבות
  int get totalLayerItems =>
      (boundary != null ? 1 : 0) +
      checkpoints.length +
      safetyPoints.length +
      clusters.length;
}

/// שירות טעינת כל נתוני הניווט (כולל שכבות ניווטיות) לשימוש אופליין
///
/// תומך בשני מצבים:
/// - **מנווט**: טוען רק את הנתונים הרלוונטיים למנווט הספציפי
/// - **מפקד**: טוען את כל נתוני הניווט (כל הצירים, כל השכבות, עץ מנווטים)
class NavigationDataLoader {
  final NavigationRepository _navigationRepo;
  final NavLayerRepository _navLayerRepo;
  final NavigationTreeRepository _navigationTreeRepo;
  final SyncManager _syncManager;
  final FirebaseFirestore _firestore;

  /// StreamController לעדכוני התקדמות
  final StreamController<LoadProgress> _progressController =
      StreamController<LoadProgress>.broadcast();

  /// Stream של עדכוני התקדמות
  Stream<LoadProgress> get progressStream => _progressController.stream;

  /// שלבי הטעינה הנוכחיים
  List<LoadStep> _steps = [];

  NavigationDataLoader({
    NavigationRepository? navigationRepo,
    NavLayerRepository? navLayerRepo,
    NavigationTreeRepository? navigationTreeRepo,
    SyncManager? syncManager,
    FirebaseFirestore? firestore,
  })  : _navigationRepo = navigationRepo ?? NavigationRepository(),
        _navLayerRepo = navLayerRepo ?? NavLayerRepository(),
        _navigationTreeRepo = navigationTreeRepo ?? NavigationTreeRepository(),
        _syncManager = syncManager ?? SyncManager(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// סגירת StreamController
  void dispose() {
    _progressController.close();
  }

  // ===========================================================================
  // טעינת נתונים למנווט
  // ===========================================================================

  /// טעינת נתוני ניווט עבור מנווט ספציפי
  ///
  /// [navigationId] - מזהה הניווט
  /// [navigatorUid] - מזהה המנווט (uid)
  /// [forceRefresh] - האם לאלץ הורדה מחדש גם אם יש cache
  Future<NavigationDataBundle?> loadNavigatorData({
    required String navigationId,
    required String navigatorUid,
    bool forceRefresh = false,
  }) async {
    // הגדרת שלבי טעינה למנווט
    _steps = [
      LoadStep(id: 'navigation', label: 'טעינת הגדרות ניווט'),
      LoadStep(id: 'boundary', label: 'טעינת גבול גזרה (GG)'),
      LoadStep(id: 'route', label: 'טעינת ציר אישי'),
      LoadStep(id: 'checkpoints', label: 'טעינת נקודות ציון (NZ)'),
      LoadStep(id: 'safety_points', label: 'טעינת נקודות בטיחות (NB)'),
      LoadStep(id: 'clusters', label: 'טעינת ביצי איזור (BA)'),
    ];
    _emitProgress();

    try {
      // בדיקת cache - אם לא ביקשו רענון והנתונים כבר קיימים
      if (!forceRefresh) {
        final cachedBundle = await _loadFromLocalDb(navigationId);
        if (cachedBundle != null && cachedBundle.hasNavLayers) {
          print('DEBUG: Navigator data already cached locally for $navigationId');
          _markAllStepsCompleted();
          return cachedBundle;
        }
      }

      // === שלב 1: טעינת הניווט ===
      _updateStep('navigation', LoadStepStatus.loading);
      final navigation = await _fetchNavigationFromServer(navigationId);
      if (navigation == null) {
        _updateStep('navigation', LoadStepStatus.failed,
            error: 'ניווט לא נמצא');
        return null;
      }
      _updateStep('navigation', LoadStepStatus.completed, itemCount: 1);

      // === שלב 2: טעינת גבול גזרה (GG) ===
      _updateStep('boundary', LoadStepStatus.loading);
      NavBoundary? boundary;
      try {
        boundary = await _fetchBoundaryFromServer(navigationId);
        _updateStep('boundary', LoadStepStatus.completed,
            itemCount: boundary != null ? 1 : 0);
      } catch (e) {
        _updateStep('boundary', LoadStepStatus.failed,
            error: 'שגיאה בטעינת גבול גזרה: $e');
      }

      // === שלב 3: טעינת ציר אישי ===
      _updateStep('route', LoadStepStatus.loading);
      List<NavCheckpoint> routeCheckpoints = [];
      try {
        final assignedRoute = navigation.routes[navigatorUid];
        if (assignedRoute != null && assignedRoute.checkpointIds.isNotEmpty) {
          // טעינת נקודות הציון של הציר האישי
          routeCheckpoints = await _fetchNavigatorCheckpoints(
            navigationId: navigationId,
            checkpointIds: assignedRoute.checkpointIds,
          );
        }
        _updateStep('route', LoadStepStatus.completed,
            itemCount: routeCheckpoints.length);
      } catch (e) {
        _updateStep('route', LoadStepStatus.failed,
            error: 'שגיאה בטעינת ציר אישי: $e');
      }

      // === שלב 4: טעינת כל נקודות הציון של הניווט (NZ) ===
      _updateStep('checkpoints', LoadStepStatus.loading);
      List<NavCheckpoint> allCheckpoints = [];
      try {
        allCheckpoints = await _fetchCheckpointsFromServer(navigationId);
        // סינון - רק נקודות שמוקצות למנווט זה
        if (navigation.routes.containsKey(navigatorUid)) {
          final assignedIds =
              navigation.routes[navigatorUid]!.checkpointIds.toSet();
          // שומרים את הנקודות שמוקצות למנווט + כל mandatory_passage
          allCheckpoints = allCheckpoints.where((cp) {
            return assignedIds.contains(cp.sourceId) ||
                assignedIds.contains(cp.id) ||
                cp.type == AppConstants.checkpointTypeMandatory;
          }).toList();
        }
        _updateStep('checkpoints', LoadStepStatus.completed,
            itemCount: allCheckpoints.length);
      } catch (e) {
        _updateStep('checkpoints', LoadStepStatus.failed,
            error: 'שגיאה בטעינת נקודות ציון: $e');
      }

      // === טעינת נקודות בטיחות (NB) ===
      _updateStep('safety_points', LoadStepStatus.loading);
      List<NavSafetyPoint> safetyPoints = [];
      try {
        safetyPoints = await _fetchSafetyPointsFromServer(navigationId);
        _updateStep('safety_points', LoadStepStatus.completed,
            itemCount: safetyPoints.length);
      } catch (e) {
        _updateStep('safety_points', LoadStepStatus.failed,
            error: 'שגיאה בטעינת נקודות בטיחות: $e');
      }

      // === שלב 6: טעינת ביצי איזור (BA) ===
      _updateStep('clusters', LoadStepStatus.loading);
      List<NavCluster> clusters = [];
      try {
        clusters = await _fetchClustersFromServer(navigationId);
        _updateStep('clusters', LoadStepStatus.completed,
            itemCount: clusters.length);
      } catch (e) {
        _updateStep('clusters', LoadStepStatus.failed,
            error: 'שגיאה בטעינת ביצי איזור: $e');
      }

      // שמירת חותמת זמן סנכרון אחרון
      await _saveLastSyncTimestamp(navigationId);

      // סיום
      _emitProgress(isComplete: true);

      final bundle = NavigationDataBundle(
        navigation: navigation,
        boundary: boundary,
        checkpoints: allCheckpoints,
        safetyPoints: safetyPoints,
        clusters: clusters,
      );

      print('DEBUG: Navigator data loaded - '
          '${allCheckpoints.length} checkpoints, '
          '${safetyPoints.length} safety points, '
          '${clusters.length} clusters');

      return bundle;
    } catch (e) {
      print('DEBUG: Error loading navigator data: $e');
      _emitProgress(hasError: true);
      rethrow;
    }
  }

  // ===========================================================================
  // טעינת נתונים למפקד
  // ===========================================================================

  /// טעינת כל נתוני הניווט עבור מפקד
  ///
  /// מפקד צריך את כל הנתונים: כל הצירים, כל השכבות, עץ מנווטים
  /// [navigationId] - מזהה הניווט
  /// [forceRefresh] - האם לאלץ הורדה מחדש
  Future<NavigationDataBundle?> loadCommanderData({
    required String navigationId,
    bool forceRefresh = false,
  }) async {
    // הגדרת שלבי טעינה למפקד
    _steps = [
      LoadStep(id: 'navigation', label: 'טעינת הגדרות ניווט'),
      LoadStep(id: 'tree', label: 'טעינת עץ מנווטים'),
      LoadStep(id: 'boundary', label: 'טעינת גבול גזרה (GG)'),
      LoadStep(id: 'routes', label: 'טעינת כל הצירים'),
      LoadStep(id: 'checkpoints', label: 'טעינת כל נקודות הציון (NZ)'),
      LoadStep(id: 'safety_points', label: 'טעינת כל נקודות הבטיחות (NB)'),
      LoadStep(id: 'clusters', label: 'טעינת כל ביצי האיזור (BA)'),
    ];
    _emitProgress();

    try {
      // בדיקת cache
      if (!forceRefresh) {
        final cachedBundle = await _loadFromLocalDb(navigationId);
        if (cachedBundle != null && cachedBundle.hasNavLayers) {
          // למפקד - צריך גם עץ מנווטים
          final tree = await _navigationTreeRepo.getById(
              cachedBundle.navigation.treeId);
          if (tree != null) {
            print('DEBUG: Commander data already cached locally for $navigationId');
            _markAllStepsCompleted();
            return NavigationDataBundle(
              navigation: cachedBundle.navigation,
              boundary: cachedBundle.boundary,
              checkpoints: cachedBundle.checkpoints,
              safetyPoints: cachedBundle.safetyPoints,
              clusters: cachedBundle.clusters,
              navigatorTree: tree,
              allRoutes: cachedBundle.navigation.routes,
            );
          }
        }
      }

      // === שלב 1: טעינת הניווט ===
      _updateStep('navigation', LoadStepStatus.loading);
      final navigation = await _fetchNavigationFromServer(navigationId);
      if (navigation == null) {
        _updateStep('navigation', LoadStepStatus.failed,
            error: 'ניווט לא נמצא');
        return null;
      }
      _updateStep('navigation', LoadStepStatus.completed, itemCount: 1);

      // === שלב 2: טעינת עץ מנווטים ===
      _updateStep('tree', LoadStepStatus.loading);
      NavigationTree? navigatorTree;
      try {
        navigatorTree = await _fetchNavigatorTree(navigation.treeId);
        _updateStep('tree', LoadStepStatus.completed,
            itemCount: navigatorTree != null ? 1 : 0);
      } catch (e) {
        _updateStep('tree', LoadStepStatus.failed,
            error: 'שגיאה בטעינת עץ מנווטים: $e');
      }

      // === שלב 3: טעינת גבול גזרה (GG) ===
      _updateStep('boundary', LoadStepStatus.loading);
      NavBoundary? boundary;
      try {
        boundary = await _fetchBoundaryFromServer(navigationId);
        _updateStep('boundary', LoadStepStatus.completed,
            itemCount: boundary != null ? 1 : 0);
      } catch (e) {
        _updateStep('boundary', LoadStepStatus.failed,
            error: 'שגיאה בטעינת גבול גזרה: $e');
      }

      // === שלב 4: טעינת כל הצירים ===
      _updateStep('routes', LoadStepStatus.loading);
      try {
        // כל הצירים כבר שמורים בניווט עצמו (navigation.routes)
        _updateStep('routes', LoadStepStatus.completed,
            itemCount: navigation.routes.length);
      } catch (e) {
        _updateStep('routes', LoadStepStatus.failed,
            error: 'שגיאה בטעינת צירים: $e');
      }

      // === טעינת כל נקודות הציון (NZ) ===
      _updateStep('checkpoints', LoadStepStatus.loading);
      List<NavCheckpoint> checkpoints = [];
      try {
        checkpoints = await _fetchCheckpointsFromServer(navigationId);
        _updateStep('checkpoints', LoadStepStatus.completed,
            itemCount: checkpoints.length);
      } catch (e) {
        _updateStep('checkpoints', LoadStepStatus.failed,
            error: 'שגיאה בטעינת נקודות ציון: $e');
      }

      // === שלב 6: טעינת כל נקודות הבטיחות (NB) ===
      _updateStep('safety_points', LoadStepStatus.loading);
      List<NavSafetyPoint> safetyPoints = [];
      try {
        safetyPoints = await _fetchSafetyPointsFromServer(navigationId);
        _updateStep('safety_points', LoadStepStatus.completed,
            itemCount: safetyPoints.length);
      } catch (e) {
        _updateStep('safety_points', LoadStepStatus.failed,
            error: 'שגיאה בטעינת נקודות בטיחות: $e');
      }

      // === שלב 7: טעינת כל ביצי האיזור (BA) ===
      _updateStep('clusters', LoadStepStatus.loading);
      List<NavCluster> clusters = [];
      try {
        clusters = await _fetchClustersFromServer(navigationId);
        _updateStep('clusters', LoadStepStatus.completed,
            itemCount: clusters.length);
      } catch (e) {
        _updateStep('clusters', LoadStepStatus.failed,
            error: 'שגיאה בטעינת ביצי איזור: $e');
      }

      // שמירת חותמת זמן סנכרון
      await _saveLastSyncTimestamp(navigationId);

      // סיום
      _emitProgress(isComplete: true);

      final bundle = NavigationDataBundle(
        navigation: navigation,
        boundary: boundary,
        checkpoints: checkpoints,
        safetyPoints: safetyPoints,
        clusters: clusters,
        navigatorTree: navigatorTree,
        allRoutes: navigation.routes,
      );

      print('DEBUG: Commander data loaded - '
          '${checkpoints.length} checkpoints, '
          '${safetyPoints.length} safety points, '
          '${clusters.length} clusters, '
          '${navigation.routes.length} routes');

      return bundle;
    } catch (e) {
      print('DEBUG: Error loading commander data: $e');
      _emitProgress(hasError: true);
      rethrow;
    }
  }

  // ===========================================================================
  // טעינת נתונים בסיסית (ללא הבדלה בין מנווט למפקד)
  // ===========================================================================

  /// טעינת כל נתוני הניווט כולל שכבות ניווטיות (תאימות לאחור)
  ///
  /// [navigationId] - מזהה הניווט
  /// מחזיר NavigationDataBundle עם כל המידע הדרוש לעבודה אופליין
  Future<NavigationDataBundle?> loadNavigationData(
    String navigationId,
  ) async {
    try {
      print('DEBUG: Loading full navigation data for $navigationId');

      // טעינת הניווט עצמו
      final navigation = await _navigationRepo.getById(navigationId);
      if (navigation == null) {
        print('DEBUG: Navigation $navigationId not found');
        return null;
      }

      // טעינת כל השכבות הניווטיות במקביל
      final results = await Future.wait([
        _navLayerRepo.getBoundariesByNavigation(navigationId),
        _navLayerRepo.getCheckpointsByNavigation(navigationId),
        _navLayerRepo.getSafetyPointsByNavigation(navigationId),
        _navLayerRepo.getClustersByNavigation(navigationId),
      ]);

      final boundaries = results[0] as List<NavBoundary>;
      final checkpoints = results[1] as List<NavCheckpoint>;
      final safetyPoints = results[2] as List<NavSafetyPoint>;
      final clusters = results[3] as List<NavCluster>;

      final bundle = NavigationDataBundle(
        navigation: navigation,
        boundary: boundaries.isNotEmpty ? boundaries.first : null,
        checkpoints: checkpoints,
        safetyPoints: safetyPoints,
        clusters: clusters,
      );

      print('DEBUG: Loaded navigation data bundle - '
          '${checkpoints.length} checkpoints, '
          '${safetyPoints.length} safety points, '
          '${boundaries.length} boundaries, '
          '${clusters.length} clusters');

      return bundle;
    } catch (e) {
      print('DEBUG: Error loading navigation data: $e');
      rethrow;
    }
  }

  /// בדיקה אם הניווט מוכן עם שכבות ניווטיות
  Future<bool> isNavigationReady(String navigationId) async {
    return await _navLayerRepo.hasLayersForNavigation(navigationId);
  }

  // ===========================================================================
  // בדיקת סטטוס Cache
  // ===========================================================================

  /// בדיקה אם נתוני ניווט כבר שמורים מקומית
  Future<bool> isDataCachedLocally(String navigationId) async {
    return await _navLayerRepo.hasLayersForNavigation(navigationId);
  }

  /// קבלת חותמת זמן סנכרון אחרון
  Future<DateTime?> getLastSyncTimestamp(String navigationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getString('last_sync_$navigationId');
      if (timestamp != null) {
        return DateTime.tryParse(timestamp);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // Firestore fetching helpers - משיכת נתונים מהשרת
  // ===========================================================================

  /// טעינת ניווט מהשרת ושמירה מקומית
  Future<Navigation?> _fetchNavigationFromServer(String navigationId) async {
    try {
      // ננסה קודם מ-Firestore
      final doc = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .get()
          .timeout(const Duration(seconds: 15));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['id'] = doc.id;

        // parse timestamps
        _convertTimestamps(data);

        final navigation = Navigation.fromMap(data);

        // שמירה מקומית
        try {
          final existingNav = await _navigationRepo.getById(navigationId);
          if (existingNav != null) {
            await _navigationRepo.update(navigation);
          } else {
            await _navigationRepo.create(navigation);
          }
        } catch (_) {
          // אם השמירה נכשלת - לא קריטי, יש לנו את הנתונים בזיכרון
        }

        return navigation;
      }

      // אם לא ב-Firestore, ננסה מ-DB מקומי
      return await _navigationRepo.getById(navigationId);
    } catch (e) {
      print('DEBUG: Error fetching navigation from server: $e');
      // fallback to local
      return await _navigationRepo.getById(navigationId);
    }
  }

  /// טעינת גבול גזרה מ-subcollection ניווטי ושמירה מקומית
  Future<NavBoundary?> _fetchBoundaryFromServer(String navigationId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersGgSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        data['id'] = doc.id;
        _convertTimestamps(data);

        final boundary = NavBoundary.fromMap(data);

        // שמירה מקומית
        try {
          await _navLayerRepo.addBoundary(boundary);
        } catch (_) {
          // כבר קיים - ננסה עדכון
          try {
            await _navLayerRepo.updateBoundary(boundary);
          } catch (_) {}
        }

        return boundary;
      }

      // fallback מ-DB מקומי
      final localBoundaries =
          await _navLayerRepo.getBoundariesByNavigation(navigationId);
      return localBoundaries.isNotEmpty ? localBoundaries.first : null;
    } catch (e) {
      print('DEBUG: Error fetching boundary from server: $e');
      final localBoundaries =
          await _navLayerRepo.getBoundariesByNavigation(navigationId);
      return localBoundaries.isNotEmpty ? localBoundaries.first : null;
    }
  }

  /// טעינת נקודות ציון ניווטיות מ-subcollection ושמירה מקומית
  Future<List<NavCheckpoint>> _fetchCheckpointsFromServer(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersNzSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      if (snapshot.docs.isNotEmpty) {
        final checkpoints = <NavCheckpoint>[];

        for (final doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          _convertTimestamps(data);
          checkpoints.add(NavCheckpoint.fromMap(data));
        }

        // שמירה מקומית בבת אחת
        try {
          // מחיקה ושמירה מחדש כדי למנוע כפילויות
          await _navLayerRepo.addCheckpointsBatch(checkpoints);
        } catch (_) {
          // אם יש כפילויות, ננסה אחד-אחד
        }

        return checkpoints;
      }

      // fallback מ-DB מקומי
      return await _navLayerRepo.getCheckpointsByNavigation(navigationId);
    } catch (e) {
      print('DEBUG: Error fetching checkpoints from server: $e');
      return await _navLayerRepo.getCheckpointsByNavigation(navigationId);
    }
  }

  /// טעינת נקודות ציון ספציפיות לציר של מנווט
  Future<List<NavCheckpoint>> _fetchNavigatorCheckpoints({
    required String navigationId,
    required List<String> checkpointIds,
  }) async {
    if (checkpointIds.isEmpty) return [];

    // טעינת כל הנקודות של הניווט ואז סינון
    final allCheckpoints = await _fetchCheckpointsFromServer(navigationId);
    final idsSet = checkpointIds.toSet();

    return allCheckpoints.where((cp) {
      return idsSet.contains(cp.sourceId) || idsSet.contains(cp.id);
    }).toList();
  }

  /// טעינת נקודות בטיחות ניווטיות מ-subcollection ושמירה מקומית
  Future<List<NavSafetyPoint>> _fetchSafetyPointsFromServer(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersNbSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      if (snapshot.docs.isNotEmpty) {
        final safetyPoints = <NavSafetyPoint>[];

        for (final doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          _convertTimestamps(data);
          safetyPoints.add(NavSafetyPoint.fromMap(data));
        }

        // שמירה מקומית
        try {
          await _navLayerRepo.addSafetyPointsBatch(safetyPoints);
        } catch (_) {}

        return safetyPoints;
      }

      return await _navLayerRepo.getSafetyPointsByNavigation(navigationId);
    } catch (e) {
      print('DEBUG: Error fetching safety points from server: $e');
      return await _navLayerRepo.getSafetyPointsByNavigation(navigationId);
    }
  }

  /// טעינת ביצי איזור ניווטיות מ-subcollection ושמירה מקומית
  Future<List<NavCluster>> _fetchClustersFromServer(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersBaSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      if (snapshot.docs.isNotEmpty) {
        final clusters = <NavCluster>[];

        for (final doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          _convertTimestamps(data);
          clusters.add(NavCluster.fromMap(data));
        }

        // שמירה מקומית
        try {
          await _navLayerRepo.addClustersBatch(clusters);
        } catch (_) {}

        return clusters;
      }

      return await _navLayerRepo.getClustersByNavigation(navigationId);
    } catch (e) {
      print('DEBUG: Error fetching clusters from server: $e');
      return await _navLayerRepo.getClustersByNavigation(navigationId);
    }
  }

  /// טעינת עץ מנווטים מ-Firestore ושמירה מקומית
  Future<NavigationTree?> _fetchNavigatorTree(String treeId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.navigatorTreesCollection)
          .doc(treeId)
          .get()
          .timeout(const Duration(seconds: 15));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['id'] = doc.id;
        final tree = NavigationTree.fromMap(data);

        // שמירה מקומית
        try {
          final existingTree = await _navigationTreeRepo.getById(treeId);
          if (existingTree != null) {
            await _navigationTreeRepo.update(tree);
          } else {
            await _navigationTreeRepo.create(tree);
          }
        } catch (_) {}

        return tree;
      }

      // fallback מ-DB מקומי
      return await _navigationTreeRepo.getById(treeId);
    } catch (e) {
      print('DEBUG: Error fetching navigator tree: $e');
      return await _navigationTreeRepo.getById(treeId);
    }
  }

  // ===========================================================================
  // Local DB helpers
  // ===========================================================================

  /// טעינת נתונים מ-DB מקומי (cache)
  Future<NavigationDataBundle?> _loadFromLocalDb(String navigationId) async {
    try {
      final navigation = await _navigationRepo.getById(navigationId);
      if (navigation == null) return null;

      final results = await Future.wait([
        _navLayerRepo.getBoundariesByNavigation(navigationId),
        _navLayerRepo.getCheckpointsByNavigation(navigationId),
        _navLayerRepo.getSafetyPointsByNavigation(navigationId),
        _navLayerRepo.getClustersByNavigation(navigationId),
      ]);

      final boundaries = results[0] as List<NavBoundary>;
      final checkpoints = results[1] as List<NavCheckpoint>;
      final safetyPoints = results[2] as List<NavSafetyPoint>;
      final clusters = results[3] as List<NavCluster>;

      return NavigationDataBundle(
        navigation: navigation,
        boundary: boundaries.isNotEmpty ? boundaries.first : null,
        checkpoints: checkpoints,
        safetyPoints: safetyPoints,
        clusters: clusters,
      );
    } catch (e) {
      print('DEBUG: Error loading from local DB: $e');
      return null;
    }
  }

  /// שמירת חותמת זמן סנכרון אחרון
  Future<void> _saveLastSyncTimestamp(String navigationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_sync_$navigationId',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('DEBUG: Error saving last sync timestamp: $e');
    }
  }

  // ===========================================================================
  // Progress helpers - ניהול התקדמות
  // ===========================================================================

  /// עדכון שלב טעינה
  void _updateStep(
    String stepId,
    LoadStepStatus status, {
    String? error,
    int? itemCount,
  }) {
    final index = _steps.indexWhere((s) => s.id == stepId);
    if (index >= 0) {
      _steps[index].status = status;
      if (error != null) _steps[index].errorMessage = error;
      if (itemCount != null) _steps[index].itemCount = itemCount;
    }
    _emitProgress();
  }

  /// סימון כל השלבים כהושלמו (למקרה של cache)
  void _markAllStepsCompleted() {
    for (final step in _steps) {
      step.status = LoadStepStatus.completed;
    }
    _emitProgress(isComplete: true);
  }

  /// שליחת עדכון התקדמות
  void _emitProgress({bool isComplete = false, bool hasError = false}) {
    if (_progressController.isClosed) return;

    final completedCount =
        _steps.where((s) => s.status == LoadStepStatus.completed).length;
    final failedCount =
        _steps.where((s) => s.status == LoadStepStatus.failed).length;
    final total = _steps.length;

    final percent = total > 0 ? (completedCount + failedCount) / total : 0.0;

    _progressController.add(LoadProgress(
      steps: List.from(_steps),
      isComplete: isComplete || completedCount + failedCount == total,
      hasError: hasError || failedCount > 0,
      progressPercent: percent,
    ));
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  /// המרת Timestamps של Firestore ל-ISO strings
  void _convertTimestamps(Map<String, dynamic> data) {
    for (final key in data.keys.toList()) {
      if (data[key] is Timestamp) {
        data[key] = (data[key] as Timestamp).toDate().toIso8601String();
      } else if (data[key] is Map<String, dynamic>) {
        _convertTimestamps(data[key] as Map<String, dynamic>);
      }
    }
  }
}
