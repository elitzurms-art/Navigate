import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/nav_layer.dart' as domain;
import '../../domain/entities/coordinate.dart';
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// המרת Firestore Timestamps ל-ISO strings (רקורסיבי)
Map<String, dynamic> _sanitizeFirestoreData(Map<String, dynamic> data) {
  return data.map((key, value) {
    if (value is Timestamp) {
      return MapEntry(key, value.toDate().toIso8601String());
    } else if (value is DateTime) {
      return MapEntry(key, value.toIso8601String());
    } else if (value is Map<String, dynamic>) {
      return MapEntry(key, _sanitizeFirestoreData(value));
    } else if (value is List) {
      return MapEntry(key, value.map((item) {
        if (item is Map<String, dynamic>) return _sanitizeFirestoreData(item);
        if (item is Timestamp) return item.toDate().toIso8601String();
        if (item is DateTime) return item.toIso8601String();
        return item;
      }).toList());
    }
    return MapEntry(key, value);
  });
}

/// Per-navigation layer repository (local DB + Firestore subcollection sync)
///
/// Firestore subcollections under /navigations/{navId}/:
///   nav_layers_nz/{checkpointId}    -- per-navigation NZ checkpoints
///   nav_layers_nb/{safetyPointId}   -- per-navigation NB safety points
///   nav_layers_gg/{boundaryId}      -- per-navigation GG boundaries
///   nav_layers_ba/{clusterId}       -- per-navigation BA clusters
class NavLayerRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  // ===================== NavCheckpoints (NZ) =====================

  /// קבלת כל נקודות הציון של ניווט ספציפי
  Future<List<domain.NavCheckpoint>> getCheckpointsByNavigation(
    String navigationId,
  ) async {
    try {
      final rows = await (_db.select(_db.navCheckpoints)
            ..where((t) => t.navigationId.equals(navigationId))
            ..orderBy([(t) => OrderingTerm(expression: t.sequenceNumber)]))
          .get();
      return rows.map((r) => _checkpointToDomain(r)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת נקודת ציון ניווטית לפי ID
  Future<domain.NavCheckpoint?> getCheckpointById(String id) async {
    try {
      final row = await (_db.select(_db.navCheckpoints)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      return row != null ? _checkpointToDomain(row) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת נקודת ציון ניווטית (נקודה או פוליגון)
  Future<void> addCheckpoint(domain.NavCheckpoint checkpoint) async {
    try {
      await _db.into(_db.navCheckpoints).insert(
            NavCheckpointsCompanion.insert(
              id: checkpoint.id,
              navigationId: checkpoint.navigationId,
              sourceId: checkpoint.sourceId,
              areaId: checkpoint.areaId,
              name: checkpoint.name,
              description: checkpoint.description,
              type: checkpoint.type,
              color: checkpoint.color,
              geometryType: Value(checkpoint.geometryType),
              lat: checkpoint.coordinates?.lat ?? 0.0,
              lng: checkpoint.coordinates?.lng ?? 0.0,
              utm: checkpoint.coordinates?.utm ?? '',
              coordinatesJson: Value(
                checkpoint.polygonCoordinates != null
                    ? jsonEncode(checkpoint.polygonCoordinates!.map((c) => c.toMap()).toList())
                    : null,
              ),
              sequenceNumber: checkpoint.sequenceNumber,
              labelsJson: Value(jsonEncode(checkpoint.labels)),
              createdBy: checkpoint.createdBy,
              createdAt: checkpoint.createdAt,
              updatedAt: checkpoint.updatedAt,
            ),
          );

      // Sync to Firestore subcollection
      await _syncManager.queueOperation(
        collection: AppConstants.navLayersNzPath(checkpoint.navigationId),
        documentId: checkpoint.id,
        operation: 'create',
        data: checkpoint.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון נקודת ציון ניווטית
  Future<void> updateCheckpoint(domain.NavCheckpoint checkpoint) async {
    try {
      await (_db.update(_db.navCheckpoints)
            ..where((t) => t.id.equals(checkpoint.id)))
          .write(
        NavCheckpointsCompanion(
          name: Value(checkpoint.name),
          description: Value(checkpoint.description),
          type: Value(checkpoint.type),
          color: Value(checkpoint.color),
          geometryType: Value(checkpoint.geometryType),
          lat: Value(checkpoint.coordinates?.lat ?? 0.0),
          lng: Value(checkpoint.coordinates?.lng ?? 0.0),
          utm: Value(checkpoint.coordinates?.utm ?? ''),
          coordinatesJson: Value(
            checkpoint.polygonCoordinates != null
                ? jsonEncode(checkpoint.polygonCoordinates!.map((c) => c.toMap()).toList())
                : null,
          ),
          sequenceNumber: Value(checkpoint.sequenceNumber),
          labelsJson: Value(jsonEncode(checkpoint.labels)),
          updatedAt: Value(checkpoint.updatedAt),
        ),
      );

      await _syncManager.queueOperation(
        collection: AppConstants.navLayersNzPath(checkpoint.navigationId),
        documentId: checkpoint.id,
        operation: 'update',
        data: checkpoint.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת נקודת ציון ניווטית
  Future<void> deleteCheckpoint(String id, String navigationId) async {
    try {
      await (_db.delete(_db.navCheckpoints)..where((t) => t.id.equals(id)))
          .go();

      await _syncManager.queueOperation(
        collection: AppConstants.navLayersNzPath(navigationId),
        documentId: id,
        operation: 'delete',
        data: {'id': id},
        priority: SyncPriority.high,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת רשימת נקודות ציון בבת אחת (bulk insert)
  Future<void> addCheckpointsBatch(
    List<domain.NavCheckpoint> checkpoints,
  ) async {
    try {
      await _db.batch((batch) {
        for (final checkpoint in checkpoints) {
          batch.insert(
            _db.navCheckpoints,
            NavCheckpointsCompanion.insert(
              id: checkpoint.id,
              navigationId: checkpoint.navigationId,
              sourceId: checkpoint.sourceId,
              areaId: checkpoint.areaId,
              name: checkpoint.name,
              description: checkpoint.description,
              type: checkpoint.type,
              color: checkpoint.color,
              geometryType: Value(checkpoint.geometryType),
              lat: checkpoint.coordinates?.lat ?? 0.0,
              lng: checkpoint.coordinates?.lng ?? 0.0,
              utm: checkpoint.coordinates?.utm ?? '',
              coordinatesJson: Value(
                checkpoint.polygonCoordinates != null
                    ? jsonEncode(checkpoint.polygonCoordinates!.map((c) => c.toMap()).toList())
                    : null,
              ),
              sequenceNumber: checkpoint.sequenceNumber,
              labelsJson: Value(jsonEncode(checkpoint.labels)),
              createdBy: checkpoint.createdBy,
              createdAt: checkpoint.createdAt,
              updatedAt: checkpoint.updatedAt,
            ),
          );
        }
      });

      // סנכרון ל-Firestore
      for (final checkpoint in checkpoints) {
        await _syncManager.queueOperation(
          collection: AppConstants.navLayersNzPath(checkpoint.navigationId),
          documentId: checkpoint.id,
          operation: 'create',
          data: checkpoint.toMap(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ===================== NavSafetyPoints (NB) =====================

  /// קבלת כל נקודות הבטיחות של ניווט ספציפי
  Future<List<domain.NavSafetyPoint>> getSafetyPointsByNavigation(
    String navigationId,
  ) async {
    try {
      final rows = await (_db.select(_db.navSafetyPoints)
            ..where((t) => t.navigationId.equals(navigationId))
            ..orderBy([(t) => OrderingTerm(expression: t.sequenceNumber)]))
          .get();
      return rows.map((r) => _safetyPointToDomain(r)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון נקודת בטיחות ניווטית
  Future<void> updateSafetyPoint(domain.NavSafetyPoint point) async {
    try {
      await (_db.update(_db.navSafetyPoints)
            ..where((t) => t.id.equals(point.id)))
          .write(
        NavSafetyPointsCompanion(
          name: Value(point.name),
          description: Value(point.description),
          type: Value(point.type),
          lat: Value(point.coordinates?.lat),
          lng: Value(point.coordinates?.lng),
          utm: Value(point.coordinates?.utm),
          coordinatesJson: Value(
            point.polygonCoordinates != null
                ? jsonEncode(
                    point.polygonCoordinates!.map((c) => c.toMap()).toList())
                : null,
          ),
          sequenceNumber: Value(point.sequenceNumber),
          severity: Value(point.severity),
          updatedAt: Value(point.updatedAt),
        ),
      );

      await _syncManager.queueOperation(
        collection: AppConstants.navLayersNbPath(point.navigationId),
        documentId: point.id,
        operation: 'update',
        data: point.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת רשימת נקודות בטיחות בבת אחת
  Future<void> addSafetyPointsBatch(
    List<domain.NavSafetyPoint> points,
  ) async {
    try {
      await _db.batch((batch) {
        for (final point in points) {
          batch.insert(
            _db.navSafetyPoints,
            NavSafetyPointsCompanion.insert(
              id: point.id,
              navigationId: point.navigationId,
              sourceId: point.sourceId,
              areaId: point.areaId,
              name: point.name,
              description: point.description,
              type: Value(point.type),
              lat: Value(point.coordinates?.lat),
              lng: Value(point.coordinates?.lng),
              utm: Value(point.coordinates?.utm),
              coordinatesJson: Value(
                point.polygonCoordinates != null
                    ? jsonEncode(
                        point.polygonCoordinates!.map((c) => c.toMap()).toList())
                    : null,
              ),
              sequenceNumber: point.sequenceNumber,
              severity: point.severity,
              createdBy: point.createdBy,
              createdAt: point.createdAt,
              updatedAt: point.updatedAt,
            ),
          );
        }
      });

      for (final point in points) {
        await _syncManager.queueOperation(
          collection: AppConstants.navLayersNbPath(point.navigationId),
          documentId: point.id,
          operation: 'create',
          data: point.toMap(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ===================== NavBoundaries (GG) =====================

  /// קבלת כל גבולות הגזרה של ניווט ספציפי
  Future<List<domain.NavBoundary>> getBoundariesByNavigation(
    String navigationId,
  ) async {
    try {
      final rows = await (_db.select(_db.navBoundaries)
            ..where((t) => t.navigationId.equals(navigationId)))
          .get();
      return rows.map((r) => _boundaryToDomain(r)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון גבול ניווטי
  Future<void> updateBoundary(domain.NavBoundary boundary) async {
    try {
      final coordinatesJson = jsonEncode(
        boundary.coordinates.map((c) => c.toMap()).toList(),
      );

      await (_db.update(_db.navBoundaries)
            ..where((t) => t.id.equals(boundary.id)))
          .write(
        NavBoundariesCompanion(
          name: Value(boundary.name),
          description: Value(boundary.description),
          coordinatesJson: Value(coordinatesJson),
          color: Value(boundary.color),
          strokeWidth: Value(boundary.strokeWidth),
          updatedAt: Value(boundary.updatedAt),
        ),
      );

      await _syncManager.queueOperation(
        collection: AppConstants.navLayersGgPath(boundary.navigationId),
        documentId: boundary.id,
        operation: 'update',
        data: boundary.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת גבול ניווטי
  Future<void> addBoundary(domain.NavBoundary boundary) async {
    try {
      final coordinatesJson = jsonEncode(
        boundary.coordinates.map((c) => c.toMap()).toList(),
      );

      await _db.into(_db.navBoundaries).insert(
            NavBoundariesCompanion.insert(
              id: boundary.id,
              navigationId: boundary.navigationId,
              sourceId: boundary.sourceId,
              areaId: boundary.areaId,
              name: boundary.name,
              description: boundary.description,
              coordinatesJson: coordinatesJson,
              color: boundary.color,
              strokeWidth: boundary.strokeWidth,
              createdBy: boundary.createdBy,
              createdAt: boundary.createdAt,
              updatedAt: boundary.updatedAt,
            ),
          );

      await _syncManager.queueOperation(
        collection: AppConstants.navLayersGgPath(boundary.navigationId),
        documentId: boundary.id,
        operation: 'create',
        data: boundary.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  // ===================== NavClusters (BA) =====================

  /// קבלת כל ביצי האיזור של ניווט ספציפי
  Future<List<domain.NavCluster>> getClustersByNavigation(
    String navigationId,
  ) async {
    try {
      final rows = await (_db.select(_db.navClusters)
            ..where((t) => t.navigationId.equals(navigationId)))
          .get();
      return rows.map((r) => _clusterToDomain(r)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון ביצת איזור ניווטית
  Future<void> updateCluster(domain.NavCluster cluster) async {
    try {
      final coordinatesJson = jsonEncode(
        cluster.coordinates.map((c) => c.toMap()).toList(),
      );

      await (_db.update(_db.navClusters)
            ..where((t) => t.id.equals(cluster.id)))
          .write(
        NavClustersCompanion(
          name: Value(cluster.name),
          description: Value(cluster.description),
          coordinatesJson: Value(coordinatesJson),
          color: Value(cluster.color),
          strokeWidth: Value(cluster.strokeWidth),
          fillOpacity: Value(cluster.fillOpacity),
          updatedAt: Value(cluster.updatedAt),
        ),
      );

      await _syncManager.queueOperation(
        collection: AppConstants.navLayersBaPath(cluster.navigationId),
        documentId: cluster.id,
        operation: 'update',
        data: cluster.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת רשימת ביצי איזור בבת אחת
  Future<void> addClustersBatch(List<domain.NavCluster> clusters) async {
    try {
      await _db.batch((batch) {
        for (final cluster in clusters) {
          final coordinatesJson = jsonEncode(
            cluster.coordinates.map((c) => c.toMap()).toList(),
          );

          batch.insert(
            _db.navClusters,
            NavClustersCompanion.insert(
              id: cluster.id,
              navigationId: cluster.navigationId,
              sourceId: cluster.sourceId,
              areaId: cluster.areaId,
              name: cluster.name,
              description: cluster.description,
              coordinatesJson: coordinatesJson,
              color: cluster.color,
              strokeWidth: cluster.strokeWidth,
              fillOpacity: cluster.fillOpacity,
              createdBy: cluster.createdBy,
              createdAt: cluster.createdAt,
              updatedAt: cluster.updatedAt,
            ),
          );
        }
      });

      for (final cluster in clusters) {
        await _syncManager.queueOperation(
          collection: AppConstants.navLayersBaPath(cluster.navigationId),
          documentId: cluster.id,
          operation: 'create',
          data: cluster.toMap(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ===================== Bulk Operations =====================

  /// מחיקת כל השכבות של ניווט ספציפי
  Future<void> deleteAllLayersForNavigation(String navigationId) async {
    try {
      await (_db.delete(_db.navCheckpoints)
            ..where((t) => t.navigationId.equals(navigationId)))
          .go();
      await (_db.delete(_db.navSafetyPoints)
            ..where((t) => t.navigationId.equals(navigationId)))
          .go();
      await (_db.delete(_db.navBoundaries)
            ..where((t) => t.navigationId.equals(navigationId)))
          .go();
      await (_db.delete(_db.navClusters)
            ..where((t) => t.navigationId.equals(navigationId)))
          .go();
    } catch (e) {
      rethrow;
    }
  }

  /// בדיקה אם כבר הועתקו שכבות לניווט
  Future<bool> hasLayersForNavigation(String navigationId) async {
    try {
      final count = await (_db.select(_db.navBoundaries)
            ..where((t) => t.navigationId.equals(navigationId)))
          .get();
      return count.isNotEmpty;
    } catch (e) {
      rethrow;
    }
  }

  // ===================== Domain Conversions =====================

  domain.NavCheckpoint _checkpointToDomain(NavCheckpoint row) {
    return domain.NavCheckpoint(
      id: row.id,
      navigationId: row.navigationId,
      sourceId: row.sourceId,
      areaId: row.areaId,
      name: row.name,
      description: row.description,
      type: row.type,
      color: row.color,
      geometryType: row.geometryType,
      coordinates: row.geometryType == 'point'
          ? Coordinate(
              lat: row.lat,
              lng: row.lng,
              utm: row.utm,
            )
          : null,
      polygonCoordinates: row.geometryType == 'polygon' && row.coordinatesJson != null
          ? (jsonDecode(row.coordinatesJson!) as List)
              .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
              .toList()
          : null,
      sequenceNumber: row.sequenceNumber,
      labels: row.labelsJson.isNotEmpty
          ? List<String>.from(jsonDecode(row.labelsJson) as List)
          : [],
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  domain.NavSafetyPoint _safetyPointToDomain(NavSafetyPoint row) {
    return domain.NavSafetyPoint(
      id: row.id,
      navigationId: row.navigationId,
      sourceId: row.sourceId,
      areaId: row.areaId,
      name: row.name,
      description: row.description,
      type: row.type,
      coordinates: row.type == 'point' && row.lat != null && row.lng != null
          ? Coordinate(
              lat: row.lat!,
              lng: row.lng!,
              utm: row.utm ?? '',
            )
          : null,
      polygonCoordinates:
          row.type == 'polygon' && row.coordinatesJson != null
              ? (jsonDecode(row.coordinatesJson!) as List)
                  .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
                  .toList()
              : null,
      sequenceNumber: row.sequenceNumber,
      severity: row.severity,
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  domain.NavBoundary _boundaryToDomain(NavBoundary row) {
    final coordinatesList = (jsonDecode(row.coordinatesJson) as List)
        .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
        .toList();

    return domain.NavBoundary(
      id: row.id,
      navigationId: row.navigationId,
      sourceId: row.sourceId,
      areaId: row.areaId,
      name: row.name,
      description: row.description,
      coordinates: coordinatesList,
      color: row.color,
      strokeWidth: row.strokeWidth,
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  domain.NavCluster _clusterToDomain(NavCluster row) {
    final coordinatesList = (jsonDecode(row.coordinatesJson) as List)
        .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
        .toList();

    return domain.NavCluster(
      id: row.id,
      navigationId: row.navigationId,
      sourceId: row.sourceId,
      areaId: row.areaId,
      name: row.name,
      description: row.description,
      coordinates: coordinatesList,
      color: row.color,
      strokeWidth: row.strokeWidth,
      fillOpacity: row.fillOpacity,
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  // ===========================================================================
  // Firestore pull helpers -- read per-navigation layers from server
  // ===========================================================================

  /// Fetch NZ checkpoints from Firestore subcollection
  /// /navigations/{navId}/nav_layers_nz
  Future<List<Map<String, dynamic>>> fetchCheckpointsFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersNzSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching nav NZ layers from Firestore: $e');
      return [];
    }
  }

  /// Fetch NB safety points from Firestore subcollection
  /// /navigations/{navId}/nav_layers_nb
  Future<List<Map<String, dynamic>>> fetchSafetyPointsFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersNbSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching nav NB layers from Firestore: $e');
      return [];
    }
  }

  /// Fetch GG boundaries from Firestore subcollection
  /// /navigations/{navId}/nav_layers_gg
  Future<List<Map<String, dynamic>>> fetchBoundariesFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersGgSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching nav GG layers from Firestore: $e');
      return [];
    }
  }

  /// Fetch BA clusters from Firestore subcollection
  /// /navigations/{navId}/nav_layers_ba
  Future<List<Map<String, dynamic>>> fetchClustersFromFirestore(
    String navigationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection(AppConstants.navLayersBaSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching nav BA layers from Firestore: $e');
      return [];
    }
  }

  /// Sync all per-navigation layers from Firestore into local DB
  Future<void> syncAllLayersFromFirestore(String navigationId) async {
    print('DEBUG: Syncing all nav layers for navigation $navigationId');

    // NZ — sanitize Timestamps, use insertOnConflictUpdate (לא addCheckpoint שמסנכרן חזרה)
    final nzDocs = await fetchCheckpointsFromFirestore(navigationId);
    for (final rawData in nzDocs) {
      try {
        final data = _sanitizeFirestoreData(rawData);
        final checkpoint = domain.NavCheckpoint.fromMap(data);
        await _db.into(_db.navCheckpoints).insertOnConflictUpdate(
          NavCheckpointsCompanion.insert(
            id: checkpoint.id,
            navigationId: checkpoint.navigationId,
            sourceId: checkpoint.sourceId,
            areaId: checkpoint.areaId,
            name: checkpoint.name,
            description: checkpoint.description,
            type: checkpoint.type,
            color: checkpoint.color,
            geometryType: Value(checkpoint.geometryType),
            lat: checkpoint.coordinates?.lat ?? 0.0,
            lng: checkpoint.coordinates?.lng ?? 0.0,
            utm: checkpoint.coordinates?.utm ?? '',
            coordinatesJson: Value(
              checkpoint.polygonCoordinates != null
                  ? jsonEncode(checkpoint.polygonCoordinates!.map((c) => c.toMap()).toList())
                  : null,
            ),
            sequenceNumber: checkpoint.sequenceNumber,
            labelsJson: Value(jsonEncode(checkpoint.labels)),
            createdBy: checkpoint.createdBy,
            createdAt: checkpoint.createdAt,
            updatedAt: checkpoint.updatedAt,
          ),
        );
      } catch (e) {
        print('DEBUG: Error upserting NZ layer from Firestore: $e');
      }
    }

    // NB — sanitize Timestamps
    final nbDocs = await fetchSafetyPointsFromFirestore(navigationId);
    for (final rawData in nbDocs) {
      try {
        final data = _sanitizeFirestoreData(rawData);
        final point = domain.NavSafetyPoint.fromMap(data);
        await _db.into(_db.navSafetyPoints).insertOnConflictUpdate(
          NavSafetyPointsCompanion.insert(
            id: point.id,
            navigationId: point.navigationId,
            sourceId: point.sourceId,
            areaId: point.areaId,
            name: point.name,
            description: point.description,
            type: Value(point.type),
            lat: Value(point.coordinates?.lat),
            lng: Value(point.coordinates?.lng),
            utm: Value(point.coordinates?.utm),
            coordinatesJson: Value(
              point.polygonCoordinates != null
                  ? jsonEncode(
                      point.polygonCoordinates!.map((c) => c.toMap()).toList())
                  : null,
            ),
            sequenceNumber: point.sequenceNumber,
            severity: point.severity,
            createdBy: point.createdBy,
            createdAt: point.createdAt,
            updatedAt: point.updatedAt,
          ),
        );
      } catch (e) {
        print('DEBUG: Error upserting NB layer from Firestore: $e');
      }
    }

    // GG — sanitize Timestamps, use insertOnConflictUpdate (לא addBoundary שמסנכרן חזרה)
    final ggDocs = await fetchBoundariesFromFirestore(navigationId);
    for (final rawData in ggDocs) {
      try {
        final data = _sanitizeFirestoreData(rawData);
        final boundary = domain.NavBoundary.fromMap(data);
        final coordinatesJson = jsonEncode(
          boundary.coordinates.map((c) => c.toMap()).toList(),
        );
        await _db.into(_db.navBoundaries).insertOnConflictUpdate(
          NavBoundariesCompanion.insert(
            id: boundary.id,
            navigationId: boundary.navigationId,
            sourceId: boundary.sourceId,
            areaId: boundary.areaId,
            name: boundary.name,
            description: boundary.description,
            coordinatesJson: coordinatesJson,
            color: boundary.color,
            strokeWidth: boundary.strokeWidth,
            createdBy: boundary.createdBy,
            createdAt: boundary.createdAt,
            updatedAt: boundary.updatedAt,
          ),
        );
      } catch (e) {
        print('DEBUG: Error upserting GG layer from Firestore: $e');
      }
    }

    // BA — sanitize Timestamps
    final baDocs = await fetchClustersFromFirestore(navigationId);
    for (final rawData in baDocs) {
      try {
        final data = _sanitizeFirestoreData(rawData);
        final cluster = domain.NavCluster.fromMap(data);
        final coordinatesJson = jsonEncode(
          cluster.coordinates.map((c) => c.toMap()).toList(),
        );
        await _db.into(_db.navClusters).insertOnConflictUpdate(
          NavClustersCompanion.insert(
            id: cluster.id,
            navigationId: cluster.navigationId,
            sourceId: cluster.sourceId,
            areaId: cluster.areaId,
            name: cluster.name,
            description: cluster.description,
            coordinatesJson: coordinatesJson,
            color: cluster.color,
            strokeWidth: cluster.strokeWidth,
            fillOpacity: cluster.fillOpacity,
            createdBy: cluster.createdBy,
            createdAt: cluster.createdAt,
            updatedAt: cluster.updatedAt,
          ),
        );
      } catch (e) {
        print('DEBUG: Error upserting BA layer from Firestore: $e');
      }
    }

    print('DEBUG: All nav layers synced for navigation $navigationId');
  }
}
