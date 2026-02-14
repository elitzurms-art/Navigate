import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/checkpoint.dart' as domain;
import '../../domain/entities/coordinate.dart';
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// מאגר נתוני נקודות ציון
class CheckpointRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל נקודות הציון
  Future<List<domain.Checkpoint>> getAll() async {
    try {
      final checkpoints = await _db.select(_db.checkpoints).get();
      return checkpoints.map((c) => _toDomain(c)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת נקודות לפי אזור
  Future<List<domain.Checkpoint>> getByArea(String areaId) async {
    try {
      final checkpoints = await (_db.select(_db.checkpoints)
            ..where((c) => c.areaId.equals(areaId))
            ..orderBy([(c) => OrderingTerm(expression: c.sequenceNumber)]))
          .get();
      return checkpoints.map((c) => _toDomain(c)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת נקודה לפי ID
  Future<domain.Checkpoint?> getById(String id) async {
    try {
      final checkpoint = await (_db.select(_db.checkpoints)
            ..where((c) => c.id.equals(id)))
          .getSingleOrNull();
      return checkpoint != null ? _toDomain(checkpoint) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// יצירת נקודת ציון חדשה (נקודה או פוליגון)
  Future<domain.Checkpoint> create(domain.Checkpoint checkpoint) async {
    try {
      // שמירה מקומית — point שומר lat/lng, polygon שומר 0.0 ב-lat/lng + coordinatesJson
      await _db.into(_db.checkpoints).insert(
            CheckpointsCompanion.insert(
              id: checkpoint.id,
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
              createdBy: checkpoint.createdBy,
              createdAt: checkpoint.createdAt,
            ),
          );

      // הוספה לתור סנכרון (area subcollection path)
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${checkpoint.areaId}/${AppConstants.areaLayersNzSubcollection}',
        documentId: checkpoint.id,
        operation: 'create',
        data: checkpoint.toMap(),
        priority: SyncPriority.high,
      );

      return checkpoint;
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון נקודת ציון
  Future<domain.Checkpoint> update(domain.Checkpoint checkpoint) async {
    try {
      // עדכון מקומי
      await (_db.update(_db.checkpoints)
            ..where((c) => c.id.equals(checkpoint.id)))
          .write(
        CheckpointsCompanion(
          name: Value(checkpoint.name),
          description: Value(checkpoint.description),
          type: Value(checkpoint.type),
          color: Value(checkpoint.color),
          geometryType: Value(checkpoint.geometryType),
          lat: Value(checkpoint.coordinates?.lat ?? 0.0),
          lng: Value(checkpoint.coordinates?.lng ?? 0.0),
          coordinatesJson: Value(
            checkpoint.polygonCoordinates != null
                ? jsonEncode(checkpoint.polygonCoordinates!.map((c) => c.toMap()).toList())
                : null,
          ),
          sequenceNumber: Value(checkpoint.sequenceNumber),
        ),
      );

      // הוספה לתור סנכרון (area subcollection path)
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${checkpoint.areaId}/${AppConstants.areaLayersNzSubcollection}',
        documentId: checkpoint.id,
        operation: 'update',
        data: checkpoint.toMap(),
        priority: SyncPriority.high,
      );

      return checkpoint;
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת נקודת ציון (מקומי + סנכרון)
  Future<void> delete(String id, {required String areaId}) async {
    await (_db.delete(_db.checkpoints)..where((t) => t.id.equals(id))).go();
    await _syncManager.queueOperation(
      collection: '${AppConstants.areasCollection}/$areaId/${AppConstants.areaLayersNzSubcollection}',
      documentId: id,
      operation: 'delete',
      data: {'id': id},
      priority: SyncPriority.high,
    );
  }

  /// מחיקת מספר נקודות ציון
  Future<void> deleteMany(List<String> ids, {required String areaId}) async {
    for (final id in ids) {
      await delete(id, areaId: areaId);
    }
  }

  /// מחיקת כל נקודות הציון של שטח מסוים (מקומי בלבד — לא מוחק מ-Firestore)
  Future<int> deleteByArea(String areaId) async {
    return await (_db.delete(_db.checkpoints)..where((t) => t.areaId.equals(areaId))).go();
  }

  /// המרה מטבלה לישות דומיין
  domain.Checkpoint _toDomain(Checkpoint dbCheckpoint) {
    return domain.Checkpoint(
      id: dbCheckpoint.id,
      areaId: dbCheckpoint.areaId,
      name: dbCheckpoint.name,
      description: dbCheckpoint.description,
      type: dbCheckpoint.type,
      color: dbCheckpoint.color,
      geometryType: dbCheckpoint.geometryType,
      coordinates: dbCheckpoint.geometryType == 'point'
          ? Coordinate(
              lat: dbCheckpoint.lat,
              lng: dbCheckpoint.lng,
              utm: dbCheckpoint.utm,
            )
          : null,
      polygonCoordinates: dbCheckpoint.geometryType == 'polygon' && dbCheckpoint.coordinatesJson != null
          ? (jsonDecode(dbCheckpoint.coordinatesJson!) as List)
              .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
              .toList()
          : null,
      sequenceNumber: dbCheckpoint.sequenceNumber,
      createdBy: dbCheckpoint.createdBy,
      createdAt: dbCheckpoint.createdAt,
    );
  }

  /// Stream של נקודות לפי אזור
  Stream<List<domain.Checkpoint>> watchByArea(String areaId) {
    return (_db.select(_db.checkpoints)
          ..where((c) => c.areaId.equals(areaId))
          ..orderBy([(c) => OrderingTerm(expression: c.sequenceNumber)]))
        .watch()
        .map((checkpoints) => checkpoints.map((c) => _toDomain(c)).toList());
  }
}
