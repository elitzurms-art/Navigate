import '../domain/entities/boundary.dart';
import '../domain/entities/checkpoint.dart';
import '../domain/entities/cluster.dart';
import '../domain/entities/coordinate.dart';
import '../domain/entities/nav_layer.dart';
import '../domain/entities/safety_point.dart';
import '../data/repositories/boundary_repository.dart';
import '../data/repositories/checkpoint_repository.dart';
import '../data/repositories/cluster_repository.dart';
import '../data/repositories/safety_point_repository.dart';
import '../data/repositories/nav_layer_repository.dart';
import '../core/utils/geometry_utils.dart';

/// תוצאת העתקת שכבות לניווט
class LayerCopyResult {
  final int checkpointsCopied;
  final int safetyPointsCopied;
  final int boundariesCopied;
  final int clustersCopied;
  final String? error;

  const LayerCopyResult({
    this.checkpointsCopied = 0,
    this.safetyPointsCopied = 0,
    this.boundariesCopied = 0,
    this.clustersCopied = 0,
    this.error,
  });

  bool get hasError => error != null;

  int get totalCopied =>
      checkpointsCopied + safetyPointsCopied + boundariesCopied + clustersCopied;

  @override
  String toString() =>
      'LayerCopyResult(nz: $checkpointsCopied, nb: $safetyPointsCopied, '
      'gg: $boundariesCopied, ba: $clustersCopied'
      '${error != null ? ', error: $error' : ''})';
}

/// שירות העתקת שכבות גלובליות לניווט ספציפי
///
/// כאשר נוצר ניווט ונבחר גבול גזרה (GG), השירות:
/// 1. מעתיק את הגבול הנבחר כשכבת GG ניווטית
/// 2. מעתיק נקודות ציון (NZ) שבתוך הגבול
/// 3. מעתיק נקודות תורפה בטיחותיות (NB) שבתוך הגבול
/// 4. מעתיק ביצי איזור (BA) שחותכות את הגבול
///
/// השכבות המועתקות הן עותקים עצמאיים - עריכתן לא משפיעה על הגלובליות.
class NavigationLayerCopyService {
  final CheckpointRepository _checkpointRepo;
  final SafetyPointRepository _safetyPointRepo;
  final BoundaryRepository _boundaryRepo;
  final ClusterRepository _clusterRepo;
  final NavLayerRepository _navLayerRepo;

  NavigationLayerCopyService({
    CheckpointRepository? checkpointRepo,
    SafetyPointRepository? safetyPointRepo,
    BoundaryRepository? boundaryRepo,
    ClusterRepository? clusterRepo,
    NavLayerRepository? navLayerRepo,
  })  : _checkpointRepo = checkpointRepo ?? CheckpointRepository(),
        _safetyPointRepo = safetyPointRepo ?? SafetyPointRepository(),
        _boundaryRepo = boundaryRepo ?? BoundaryRepository(),
        _clusterRepo = clusterRepo ?? ClusterRepository(),
        _navLayerRepo = navLayerRepo ?? NavLayerRepository();

  /// העתקת כל השכבות בתוך גבולות GG נבחרים לניווט ספציפי (תמיכה בגבולות מרובים)
  ///
  /// [navigationId] - מזהה הניווט
  /// [boundaryIds] - מזהי הגבולות הנבחרים (GG)
  /// [areaId] - מזהה האזור
  /// [createdBy] - מזהה המשתמש שיוצר
  Future<LayerCopyResult> copyLayersForNavigation({
    required String navigationId,
    required List<String> boundaryIds,
    required String areaId,
    required String createdBy,
  }) async {
    try {
      print('DEBUG: Starting layer copy for navigation $navigationId, '
          'boundaries $boundaryIds, area $areaId');

      // בדיקה אם כבר הועתקו שכבות
      final alreadyHasLayers =
          await _navLayerRepo.hasLayersForNavigation(navigationId);
      if (alreadyHasLayers) {
        print('DEBUG: Navigation $navigationId already has copied layers, skipping');
        return const LayerCopyResult(error: 'שכבות כבר הועתקו לניווט זה');
      }

      final now = DateTime.now();
      int totalCheckpoints = 0;
      int totalSafetyPoints = 0;
      int totalBoundaries = 0;
      int totalClusters = 0;

      // טעינת כל הנקודות והשכבות של האזור פעם אחת
      final allCheckpoints = await _checkpointRepo.getByArea(areaId);
      final allSafetyPoints = await _safetyPointRepo.getByArea(areaId);
      final allClusters = await _clusterRepo.getByArea(areaId);

      // סט למעקב אחרי נקודות שכבר הועתקו (למניעת כפילויות בין גבולות חופפים)
      // שימוש ב-sourceId כמפתח — אם נקודה נמצאת בשני גבולות, מועתקת פעם אחת עם הגבול הראשון
      final copiedCheckpointSourceIds = <String>{};
      final copiedSafetyPointSourceIds = <String>{};
      final copiedClusterSourceIds = <String>{};

      for (final boundaryId in boundaryIds) {
        // 1. טעינת הגבול
        final boundary = await _boundaryRepo.getById(boundaryId);
        if (boundary == null) {
          print('DEBUG: Boundary $boundaryId not found, skipping');
          continue;
        }

        final boundaryPolygon = boundary.coordinates;
        if (boundaryPolygon.length < 3) {
          print('DEBUG: Boundary ${boundary.name} has < 3 points, skipping');
          continue;
        }

        // 2. העתקת הגבול עצמו
        final navBoundary = _copyBoundary(
          boundary: boundary,
          navigationId: navigationId,
          now: now,
          createdBy: createdBy,
          sourceBoundaryIds: [boundaryId],
        );
        await _navLayerRepo.addBoundary(navBoundary);
        totalBoundaries++;
        print('DEBUG: Copied GG boundary: ${boundary.name}');

        // 3. העתקת נקודות ציון (NZ) בתוך הגבול
        final filteredCheckpoints = _filterCheckpointsInBoundary(
          checkpoints: allCheckpoints,
          boundaryPolygon: boundaryPolygon,
        );

        final navCheckpoints = filteredCheckpoints
            .where((cp) => !copiedCheckpointSourceIds.contains(cp.id))
            .map((cp) {
              copiedCheckpointSourceIds.add(cp.id);
              return _copyCheckpoint(
                checkpoint: cp,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
                boundaryId: boundaryId,
              );
            })
            .toList();

        if (navCheckpoints.isNotEmpty) {
          await _navLayerRepo.addCheckpointsBatch(navCheckpoints);
        }
        totalCheckpoints += navCheckpoints.length;
        print('DEBUG: Copied ${navCheckpoints.length} NZ checkpoints inside boundary ${boundary.name}');

        // 4. העתקת נקודות תורפה בטיחותיות (NB) בתוך הגבול
        final filteredSafetyPoints = _filterSafetyPointsInBoundary(
          safetyPoints: allSafetyPoints,
          boundaryPolygon: boundaryPolygon,
        );

        final navSafetyPoints = filteredSafetyPoints
            .where((sp) => !copiedSafetyPointSourceIds.contains(sp.id))
            .map((sp) {
              copiedSafetyPointSourceIds.add(sp.id);
              return _copySafetyPoint(
                safetyPoint: sp,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              );
            })
            .toList();

        if (navSafetyPoints.isNotEmpty) {
          await _navLayerRepo.addSafetyPointsBatch(navSafetyPoints);
        }
        totalSafetyPoints += navSafetyPoints.length;

        // 5. העתקת ביצי איזור (BA) שחותכות את הגבול
        final filteredClusters = GeometryUtils.filterPolygonsIntersecting(
          polygons: allClusters,
          getCoordinates: (cluster) => cluster.coordinates,
          boundary: boundaryPolygon,
        );

        final navClusters = filteredClusters
            .where((cl) => !copiedClusterSourceIds.contains(cl.id))
            .map((cl) {
              copiedClusterSourceIds.add(cl.id);
              return _copyCluster(
                cluster: cl,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              );
            })
            .toList();

        if (navClusters.isNotEmpty) {
          await _navLayerRepo.addClustersBatch(navClusters);
        }
        totalClusters += navClusters.length;
      }

      final result = LayerCopyResult(
        checkpointsCopied: totalCheckpoints,
        safetyPointsCopied: totalSafetyPoints,
        boundariesCopied: totalBoundaries,
        clustersCopied: totalClusters,
      );

      print('DEBUG: Layer copy complete: $result');
      return result;
    } catch (e) {
      print('DEBUG: Error copying layers: $e');
      return LayerCopyResult(error: 'שגיאה בהעתקת שכבות: $e');
    }
  }

  /// העתקת שכבות עם גבול מותאם אישית (מצבים 1-3 של BoundarySetupScreen)
  ///
  /// [boundaryCoordinates] — הפוליגון הראשי (ממוזג/מצויר/משוכפל)
  /// [multiPolygonCoordinates] — רשימת פוליגונים (ל-MultiPolygon)
  /// [geometryType] — 'polygon' או 'multipolygon'
  /// [sourceBoundaryIds] — מזהי גבולות מקור (ריק אם ציור ידני)
  /// [creationMode] — מצב היצירה
  Future<LayerCopyResult> copyLayersWithCustomBoundary({
    required String navigationId,
    required List<Coordinate> boundaryCoordinates,
    List<List<Coordinate>>? multiPolygonCoordinates,
    required String geometryType,
    required List<String> sourceBoundaryIds,
    required NavBoundaryCreationMode creationMode,
    required String areaId,
    required String createdBy,
    String? boundaryName,
  }) async {
    try {
      print('DEBUG: Starting custom boundary layer copy for navigation $navigationId, '
          'mode: $creationMode, geometryType: $geometryType');

      // בדיקה אם כבר הועתקו שכבות
      final alreadyHasLayers =
          await _navLayerRepo.hasLayersForNavigation(navigationId);
      if (alreadyHasLayers) {
        print('DEBUG: Navigation $navigationId already has copied layers, skipping');
        return const LayerCopyResult(error: 'שכבות כבר הועתקו לניווט זה');
      }

      final now = DateTime.now();

      // 1. יצירת NavBoundary אחד עם הגבול המותאם
      final navBoundary = NavBoundary(
        id: 'nav_${navigationId}_boundary',
        navigationId: navigationId,
        sourceId: sourceBoundaryIds.isNotEmpty ? sourceBoundaryIds.first : 'custom',
        areaId: areaId,
        name: boundaryName ?? 'גבול ניווט',
        description: '',
        coordinates: boundaryCoordinates,
        sourceBoundaryIds: sourceBoundaryIds,
        creationMode: creationMode,
        geometryType: geometryType,
        multiPolygonCoordinates: multiPolygonCoordinates,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
      );
      await _navLayerRepo.addBoundary(navBoundary);
      print('DEBUG: Created custom NavBoundary (mode: $creationMode, type: $geometryType)');

      // 2. קביעת פוליגונים לסינון
      final filterPolygons = geometryType == 'multipolygon' && multiPolygonCoordinates != null
          ? multiPolygonCoordinates
          : [boundaryCoordinates];

      // 3. טעינת כל הנקודות והשכבות של האזור
      final allCheckpoints = await _checkpointRepo.getByArea(areaId);
      final allSafetyPoints = await _safetyPointRepo.getByArea(areaId);
      final allClusters = await _clusterRepo.getByArea(areaId);

      // 4. סינון והעתקה עם dedup
      final copiedCheckpointSourceIds = <String>{};
      final copiedSafetyPointSourceIds = <String>{};
      final copiedClusterSourceIds = <String>{};

      int totalCheckpoints = 0;
      int totalSafetyPoints = 0;
      int totalClusters = 0;

      for (final polygon in filterPolygons) {
        if (polygon.length < 3) continue;

        // נקודות ציון (NZ)
        final filteredCheckpoints = _filterCheckpointsInBoundary(
          checkpoints: allCheckpoints,
          boundaryPolygon: polygon,
        );

        final navCheckpoints = filteredCheckpoints
            .where((cp) => !copiedCheckpointSourceIds.contains(cp.id))
            .map((cp) {
              copiedCheckpointSourceIds.add(cp.id);
              return _copyCheckpoint(
                checkpoint: cp,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              );
            })
            .toList();

        if (navCheckpoints.isNotEmpty) {
          await _navLayerRepo.addCheckpointsBatch(navCheckpoints);
        }
        totalCheckpoints += navCheckpoints.length;

        // נקודות בטיחות (NB)
        final filteredSafetyPoints = _filterSafetyPointsInBoundary(
          safetyPoints: allSafetyPoints,
          boundaryPolygon: polygon,
        );

        final navSafetyPoints = filteredSafetyPoints
            .where((sp) => !copiedSafetyPointSourceIds.contains(sp.id))
            .map((sp) {
              copiedSafetyPointSourceIds.add(sp.id);
              return _copySafetyPoint(
                safetyPoint: sp,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              );
            })
            .toList();

        if (navSafetyPoints.isNotEmpty) {
          await _navLayerRepo.addSafetyPointsBatch(navSafetyPoints);
        }
        totalSafetyPoints += navSafetyPoints.length;

        // ביצי איזור (BA)
        final filteredClusters = GeometryUtils.filterPolygonsIntersecting(
          polygons: allClusters,
          getCoordinates: (cluster) => cluster.coordinates,
          boundary: polygon,
        );

        final navClusters = filteredClusters
            .where((cl) => !copiedClusterSourceIds.contains(cl.id))
            .map((cl) {
              copiedClusterSourceIds.add(cl.id);
              return _copyCluster(
                cluster: cl,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              );
            })
            .toList();

        if (navClusters.isNotEmpty) {
          await _navLayerRepo.addClustersBatch(navClusters);
        }
        totalClusters += navClusters.length;
      }

      final result = LayerCopyResult(
        checkpointsCopied: totalCheckpoints,
        safetyPointsCopied: totalSafetyPoints,
        boundariesCopied: 1,
        clustersCopied: totalClusters,
      );

      print('DEBUG: Custom boundary layer copy complete: $result');
      return result;
    } catch (e) {
      print('DEBUG: Error copying layers with custom boundary: $e');
      return LayerCopyResult(error: 'שגיאה בהעתקת שכבות: $e');
    }
  }

  /// תאימות אחורה — העתקת שכבות עם גבול יחיד
  Future<LayerCopyResult> copyLayersForNavigationSingle({
    required String navigationId,
    required String boundaryId,
    required String areaId,
    required String createdBy,
  }) {
    return copyLayersForNavigation(
      navigationId: navigationId,
      boundaryIds: [boundaryId],
      areaId: areaId,
      createdBy: createdBy,
    );
  }

  /// סינון נקודות ציון שבתוך הגבול
  /// לנקודת 'point' - בדיקה רגילה של נקודה בתוך פוליגון
  /// לנקודת 'polygon' - בדיקה של חפיפת פוליגונים
  List<Checkpoint> _filterCheckpointsInBoundary({
    required List<Checkpoint> checkpoints,
    required List<Coordinate> boundaryPolygon,
  }) {
    return checkpoints.where((cp) {
      if (cp.geometryType == 'polygon' && cp.polygonCoordinates != null) {
        return GeometryUtils.doPolygonsIntersect(
          cp.polygonCoordinates!,
          boundaryPolygon,
        );
      } else if (cp.coordinates != null) {
        return GeometryUtils.isPointInPolygon(
          cp.coordinates!,
          boundaryPolygon,
        );
      }
      return false;
    }).toList();
  }

  /// סינון נקודות בטיחות שבתוך הגבול
  /// לנקודת 'point' - בדיקה רגילה של נקודה בתוך פוליגון
  /// לנקודת 'polygon' - בדיקה של חפיפת פוליגונים
  List<SafetyPoint> _filterSafetyPointsInBoundary({
    required List<SafetyPoint> safetyPoints,
    required List<Coordinate> boundaryPolygon,
  }) {
    return safetyPoints.where((sp) {
      if (sp.type == 'point' && sp.coordinates != null) {
        return GeometryUtils.isPointInPolygon(
          sp.coordinates!,
          boundaryPolygon,
        );
      } else if (sp.type == 'polygon' && sp.polygonCoordinates != null) {
        return GeometryUtils.doPolygonsIntersect(
          sp.polygonCoordinates!,
          boundaryPolygon,
        );
      }
      return false;
    }).toList();
  }

  /// יצירת ID ייחודי לשכבה ניווטית
  String _generateNavLayerId(String navigationId, String sourceId) {
    return 'nav_${navigationId}_$sourceId';
  }

  /// העתקת גבול לניווט
  NavBoundary _copyBoundary({
    required Boundary boundary,
    required String navigationId,
    required DateTime now,
    required String createdBy,
    List<String> sourceBoundaryIds = const [],
  }) {
    return NavBoundary(
      id: _generateNavLayerId(navigationId, boundary.id),
      navigationId: navigationId,
      sourceId: boundary.id,
      areaId: boundary.areaId,
      name: boundary.name,
      description: boundary.description,
      coordinates: List.from(boundary.coordinates),
      color: boundary.color,
      strokeWidth: boundary.strokeWidth,
      sourceBoundaryIds: sourceBoundaryIds.isNotEmpty ? sourceBoundaryIds : [boundary.id],
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// העתקת נקודת ציון לניווט (נקודה או פוליגון)
  NavCheckpoint _copyCheckpoint({
    required Checkpoint checkpoint,
    required String navigationId,
    required DateTime now,
    required String createdBy,
    String? boundaryId,
  }) {
    return NavCheckpoint(
      id: _generateNavLayerId(navigationId, checkpoint.id),
      navigationId: navigationId,
      sourceId: checkpoint.id,
      areaId: checkpoint.areaId,
      name: checkpoint.name,
      description: checkpoint.description,
      type: checkpoint.type,
      color: checkpoint.color,
      geometryType: checkpoint.geometryType,
      coordinates: checkpoint.coordinates,
      polygonCoordinates: checkpoint.polygonCoordinates != null
          ? List.from(checkpoint.polygonCoordinates!)
          : null,
      sequenceNumber: checkpoint.sequenceNumber,
      boundaryId: boundaryId,
      labels: List.from(checkpoint.labels),
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// העתקת נקודת בטיחות לניווט
  NavSafetyPoint _copySafetyPoint({
    required SafetyPoint safetyPoint,
    required String navigationId,
    required DateTime now,
    required String createdBy,
  }) {
    return NavSafetyPoint(
      id: _generateNavLayerId(navigationId, safetyPoint.id),
      navigationId: navigationId,
      sourceId: safetyPoint.id,
      areaId: safetyPoint.areaId,
      name: safetyPoint.name,
      description: safetyPoint.description,
      type: safetyPoint.type,
      coordinates: safetyPoint.coordinates,
      polygonCoordinates: safetyPoint.polygonCoordinates != null
          ? List.from(safetyPoint.polygonCoordinates!)
          : null,
      sequenceNumber: safetyPoint.sequenceNumber,
      severity: safetyPoint.severity,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// העתקת ביצת איזור לניווט
  NavCluster _copyCluster({
    required Cluster cluster,
    required String navigationId,
    required DateTime now,
    required String createdBy,
  }) {
    return NavCluster(
      id: _generateNavLayerId(navigationId, cluster.id),
      navigationId: navigationId,
      sourceId: cluster.id,
      areaId: cluster.areaId,
      name: cluster.name,
      description: cluster.description,
      coordinates: List.from(cluster.coordinates),
      color: cluster.color,
      strokeWidth: cluster.strokeWidth,
      fillOpacity: cluster.fillOpacity,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// מחיקת כל השכבות הניווטיות של ניווט (למקרה של שחזור/מחיקה)
  Future<void> deleteLayersForNavigation(String navigationId) async {
    await _navLayerRepo.deleteAllLayersForNavigation(navigationId);
    print('DEBUG: Deleted all nav layers for navigation $navigationId');
  }
}
