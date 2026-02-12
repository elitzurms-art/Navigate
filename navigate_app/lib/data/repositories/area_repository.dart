import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/area.dart' as domain;
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// Area repository -- local DB CRUD + Firestore layer subcollection sync
///
/// Firestore structure:
///   /areas/{areaId}                        -- area document
///   /areas/{areaId}/layers_nz/{id}         -- NZ checkpoints (global)
///   /areas/{areaId}/layers_nb/{id}         -- NB safety points (global)
///   /areas/{areaId}/layers_gg/{id}         -- GG boundaries (global)
///   /areas/{areaId}/layers_ba/{id}         -- BA clusters (global)
class AreaRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל האזורים
  Future<List<domain.Area>> getAll() async {
    try {
      final areas = await _db.select(_db.areas).get();
      return areas.map((a) => _toDomain(a)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת אזור לפי ID
  Future<domain.Area?> getById(String id) async {
    try {
      final area = await (_db.select(_db.areas)
            ..where((a) => a.id.equals(id)))
          .getSingleOrNull();
      return area != null ? _toDomain(area) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// יצירת אזור חדש
  Future<domain.Area> create(domain.Area area) async {
    try {
      // שמירה מקומית
      await _db.into(_db.areas).insert(
            AreasCompanion.insert(
              id: area.id,
              name: area.name,
              description: area.description,
              createdBy: area.createdBy,
              createdAt: area.createdAt,
            ),
          );

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.areasCollection,
        documentId: area.id,
        operation: 'create',
        data: area.toMap(),
        priority: SyncPriority.high,
      );

      return area;
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון אזור
  Future<domain.Area> update(domain.Area area) async {
    try {
      // עדכון מקומי
      await (_db.update(_db.areas)..where((a) => a.id.equals(area.id)))
          .write(
        AreasCompanion(
          name: Value(area.name),
          description: Value(area.description),
        ),
      );

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.areasCollection,
        documentId: area.id,
        operation: 'update',
        data: area.toMap(),
        priority: SyncPriority.high,
      );

      return area;
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת אזור — disabled (add-only sync)
  Future<void> delete(String id) async {
    print('AreaRepository: delete() is disabled — areas are add-only.');
  }

  /// סנכרון מ-Firestore (משיכת נתונים)
  Future<void> syncFromFirestore() async {
    try {
      final snapshot = await _firestore.collection(AppConstants.areasCollection).get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final area = domain.Area.fromMap(data);

        // בדיקה אם האזור קיים
        final existing = await getById(area.id);

        if (existing == null) {
          // יצירה חדשה (ללא סנכרון חזרה)
          await _db.into(_db.areas).insert(
                AreasCompanion.insert(
                  id: area.id,
                  name: area.name,
                  description: area.description,
                  createdBy: area.createdBy,
                  createdAt: area.createdAt,
                ),
              );
        } else {
          // עדכון (ללא סנכרון חזרה)
          await (_db.update(_db.areas)..where((a) => a.id.equals(area.id)))
              .write(
            AreasCompanion(
              name: Value(area.name),
              description: Value(area.description),
            ),
          );
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// המרה מטבלה לישות דומיין
  domain.Area _toDomain(Area dbArea) {
    return domain.Area(
      id: dbArea.id,
      name: dbArea.name,
      description: dbArea.description,
      createdBy: dbArea.createdBy,
      createdAt: dbArea.createdAt,
    );
  }

  /// Stream של אזורים (לעדכונים בזמן אמת)
  Stream<List<domain.Area>> watchAll() {
    return _db.select(_db.areas).watch().map(
          (areas) => areas.map((a) => _toDomain(a)).toList(),
        );
  }

  /// Stream of a single area
  Stream<domain.Area?> watchById(String id) {
    return (_db.select(_db.areas)..where((a) => a.id.equals(id)))
        .watchSingleOrNull()
        .map((area) => area != null ? _toDomain(area) : null);
  }

  // ===========================================================================
  // Layer subcollection sync helpers
  // ===========================================================================
  //
  // The plan moves global layers from flat top-level collections into
  // area-scoped subcollections:
  //   /areas/{areaId}/layers_nz/{checkpointId}
  //   /areas/{areaId}/layers_nb/{safetyPointId}
  //   /areas/{areaId}/layers_gg/{boundaryId}
  //   /areas/{areaId}/layers_ba/{clusterId}
  //
  // Existing flat collections (layers_nz, layers_nb etc.) are kept for backward
  // compatibility.  The methods below allow reading/writing through the new
  // subcollection structure.

  /// Sync NZ checkpoints from area subcollection into local DB
  Future<void> syncLayersNzFromArea(String areaId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.areasCollection)
          .doc(areaId)
          .collection(AppConstants.areaLayersNzSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      print('DEBUG: Pulled ${snapshot.docs.length} NZ layers for area $areaId');

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['areaId'] = areaId;

        await _db.into(_db.checkpoints).insertOnConflictUpdate(
          CheckpointsCompanion.insert(
            id: doc.id,
            areaId: areaId,
            name: data['name'] as String? ?? '',
            description: data['description'] as String? ?? '',
            type: data['type'] as String? ?? 'checkpoint',
            color: data['color'] as String? ?? 'blue',
            lat: (data['lat'] as num?)?.toDouble() ?? 0.0,
            lng: (data['lng'] as num?)?.toDouble() ?? 0.0,
            utm: data['utm'] as String? ?? '',
            sequenceNumber: (data['sequenceNumber'] as num?)?.toInt() ?? 0,
            createdBy: data['createdBy'] as String? ?? '',
            createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error syncing NZ layers for area $areaId: $e');
    }
  }

  /// Sync NB safety points from area subcollection into local DB
  Future<void> syncLayersNbFromArea(String areaId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.areasCollection)
          .doc(areaId)
          .collection(AppConstants.areaLayersNbSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      print('DEBUG: Pulled ${snapshot.docs.length} NB layers for area $areaId');

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['areaId'] = areaId;

        await _db.into(_db.safetyPoints).insertOnConflictUpdate(
          SafetyPointsCompanion.insert(
            id: doc.id,
            areaId: areaId,
            name: data['name'] as String? ?? '',
            description: data['description'] as String? ?? '',
            sequenceNumber: (data['sequenceNumber'] as num?)?.toInt() ?? 0,
            severity: data['severity'] as String? ?? 'low',
            createdBy: data['createdBy'] as String? ?? '',
            createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
            updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
            type: Value(data['type'] as String? ?? 'point'),
            lat: Value((data['lat'] as num?)?.toDouble()),
            lng: Value((data['lng'] as num?)?.toDouble()),
            utm: Value(data['utm'] as String?),
            coordinatesJson: Value(data['coordinatesJson'] as String?),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error syncing NB layers for area $areaId: $e');
    }
  }

  /// Sync GG boundaries from area subcollection into local DB
  Future<void> syncLayersGgFromArea(String areaId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.areasCollection)
          .doc(areaId)
          .collection(AppConstants.areaLayersGgSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      print('DEBUG: Pulled ${snapshot.docs.length} GG layers for area $areaId');

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['areaId'] = areaId;

        await _db.into(_db.boundaries).insertOnConflictUpdate(
          BoundariesCompanion.insert(
            id: doc.id,
            areaId: areaId,
            name: data['name'] as String? ?? '',
            description: data['description'] as String? ?? '',
            coordinatesJson: data['coordinatesJson'] as String? ?? '[]',
            color: data['color'] as String? ?? 'black',
            strokeWidth: (data['strokeWidth'] as num?)?.toDouble() ?? 2.0,
            createdBy: data['createdBy'] as String? ?? '',
            createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
            updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error syncing GG layers for area $areaId: $e');
    }
  }

  /// Sync BA clusters from area subcollection into local DB
  Future<void> syncLayersBaFromArea(String areaId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.areasCollection)
          .doc(areaId)
          .collection(AppConstants.areaLayersBaSubcollection)
          .get()
          .timeout(const Duration(seconds: 15));

      print('DEBUG: Pulled ${snapshot.docs.length} BA layers for area $areaId');

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['areaId'] = areaId;

        await _db.into(_db.clusters).insertOnConflictUpdate(
          ClustersCompanion.insert(
            id: doc.id,
            areaId: areaId,
            name: data['name'] as String? ?? '',
            description: data['description'] as String? ?? '',
            coordinatesJson: data['coordinatesJson'] as String? ?? '[]',
            color: data['color'] as String? ?? 'green',
            strokeWidth: (data['strokeWidth'] as num?)?.toDouble() ?? 2.0,
            fillOpacity: (data['fillOpacity'] as num?)?.toDouble() ?? 0.3,
            createdBy: data['createdBy'] as String? ?? '',
            createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
            updatedAt: _parseDateTime(data['updatedAt']) ?? DateTime.now(),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error syncing BA layers for area $areaId: $e');
    }
  }

  /// Sync ALL layer subcollections for a given area
  Future<void> syncAllLayersFromArea(String areaId) async {
    await syncLayersNzFromArea(areaId);
    await syncLayersNbFromArea(areaId);
    await syncLayersGgFromArea(areaId);
    await syncLayersBaFromArea(areaId);
    print('DEBUG: All layers synced for area $areaId');
  }

  /// Push a layer to the area subcollection in Firestore (via sync queue)
  ///
  /// [layerType] must be one of: 'layers_nz', 'layers_nb', 'layers_gg', 'layers_ba'
  Future<void> pushLayerToAreaSubcollection({
    required String areaId,
    required String layerType,
    required String layerId,
    required String operation,
    required Map<String, dynamic> data,
  }) async {
    try {
      final path = '${AppConstants.areasCollection}/$areaId/$layerType';
      await _syncManager.queueOperation(
        collection: path,
        documentId: layerId,
        operation: operation,
        data: data,
        priority: SyncPriority.high,
      );
      print('DEBUG: Layer $layerId ($layerType) queued for area $areaId');
    } catch (e) {
      print('DEBUG: Error queuing layer to area subcollection: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // Utility
  // ===========================================================================

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
