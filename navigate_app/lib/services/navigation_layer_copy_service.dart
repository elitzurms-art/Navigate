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

  /// העתקת כל השכבות בתוך גבול GG נבחר לניווט ספציפי
  ///
  /// [navigationId] - מזהה הניווט
  /// [boundaryId] - מזהה הגבול הנבחר (GG)
  /// [areaId] - מזהה האזור
  /// [createdBy] - מזהה המשתמש שיוצר
  Future<LayerCopyResult> copyLayersForNavigation({
    required String navigationId,
    required String boundaryId,
    required String areaId,
    required String createdBy,
  }) async {
    try {
      print('DEBUG: Starting layer copy for navigation $navigationId, '
          'boundary $boundaryId, area $areaId');

      // בדיקה אם כבר הועתקו שכבות
      final alreadyHasLayers =
          await _navLayerRepo.hasLayersForNavigation(navigationId);
      if (alreadyHasLayers) {
        print('DEBUG: Navigation $navigationId already has copied layers, skipping');
        return const LayerCopyResult(error: 'שכבות כבר הועתקו לניווט זה');
      }

      // 1. טעינת הגבול הנבחר
      final boundary = await _boundaryRepo.getById(boundaryId);
      if (boundary == null) {
        return const LayerCopyResult(error: 'גבול גזרה לא נמצא');
      }

      final boundaryPolygon = boundary.coordinates;
      if (boundaryPolygon.length < 3) {
        return const LayerCopyResult(error: 'גבול גזרה חייב להכיל לפחות 3 נקודות');
      }

      final now = DateTime.now();

      // 2. העתקת הגבול עצמו
      final navBoundary = _copyBoundary(
        boundary: boundary,
        navigationId: navigationId,
        now: now,
        createdBy: createdBy,
      );
      await _navLayerRepo.addBoundary(navBoundary);
      print('DEBUG: Copied GG boundary: ${boundary.name}');

      // 3. העתקת נקודות ציון (NZ) בתוך הגבול
      final allCheckpoints = await _checkpointRepo.getByArea(areaId);
      final filteredCheckpoints = GeometryUtils.filterPointsInPolygon(
        points: allCheckpoints,
        getCoordinate: (cp) => cp.coordinates,
        polygon: boundaryPolygon,
      );

      final navCheckpoints = filteredCheckpoints
          .map((cp) => _copyCheckpoint(
                checkpoint: cp,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              ))
          .toList();

      if (navCheckpoints.isNotEmpty) {
        await _navLayerRepo.addCheckpointsBatch(navCheckpoints);
      }
      print('DEBUG: Copied ${navCheckpoints.length}/${allCheckpoints.length} '
          'NZ checkpoints inside boundary');

      // 4. העתקת נקודות תורפה בטיחותיות (NB) בתוך הגבול
      final allSafetyPoints = await _safetyPointRepo.getByArea(areaId);
      final filteredSafetyPoints = _filterSafetyPointsInBoundary(
        safetyPoints: allSafetyPoints,
        boundaryPolygon: boundaryPolygon,
      );

      final navSafetyPoints = filteredSafetyPoints
          .map((sp) => _copySafetyPoint(
                safetyPoint: sp,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              ))
          .toList();

      if (navSafetyPoints.isNotEmpty) {
        await _navLayerRepo.addSafetyPointsBatch(navSafetyPoints);
      }
      print('DEBUG: Copied ${navSafetyPoints.length}/${allSafetyPoints.length} '
          'NB safety points inside boundary');

      // 5. העתקת ביצי איזור (BA) שחותכות את הגבול
      final allClusters = await _clusterRepo.getByArea(areaId);
      final filteredClusters = GeometryUtils.filterPolygonsIntersecting(
        polygons: allClusters,
        getCoordinates: (cluster) => cluster.coordinates,
        boundary: boundaryPolygon,
      );

      final navClusters = filteredClusters
          .map((cl) => _copyCluster(
                cluster: cl,
                navigationId: navigationId,
                now: now,
                createdBy: createdBy,
              ))
          .toList();

      if (navClusters.isNotEmpty) {
        await _navLayerRepo.addClustersBatch(navClusters);
      }
      print('DEBUG: Copied ${navClusters.length}/${allClusters.length} '
          'BA clusters intersecting boundary');

      final result = LayerCopyResult(
        checkpointsCopied: navCheckpoints.length,
        safetyPointsCopied: navSafetyPoints.length,
        boundariesCopied: 1, // הגבול עצמו
        clustersCopied: navClusters.length,
      );

      print('DEBUG: Layer copy complete: $result');
      return result;
    } catch (e) {
      print('DEBUG: Error copying layers: $e');
      return LayerCopyResult(error: 'שגיאה בהעתקת שכבות: $e');
    }
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
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// העתקת נקודת ציון לניווט
  NavCheckpoint _copyCheckpoint({
    required Checkpoint checkpoint,
    required String navigationId,
    required DateTime now,
    required String createdBy,
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
      coordinates: checkpoint.coordinates,
      sequenceNumber: checkpoint.sequenceNumber,
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
