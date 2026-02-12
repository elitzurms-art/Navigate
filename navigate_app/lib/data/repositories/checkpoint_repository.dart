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

  /// יצירת נקודת ציון חדשה
  Future<domain.Checkpoint> create(domain.Checkpoint checkpoint) async {
    try {
      // שמירה מקומית
      await _db.into(_db.checkpoints).insert(
            CheckpointsCompanion.insert(
              id: checkpoint.id,
              areaId: checkpoint.areaId,
              name: checkpoint.name,
              description: checkpoint.description,
              type: checkpoint.type,
              color: checkpoint.color,
              lat: checkpoint.coordinates.lat,
              lng: checkpoint.coordinates.lng,
              utm: '',
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
          lat: Value(checkpoint.coordinates.lat),
          lng: Value(checkpoint.coordinates.lng),
          sequenceNumber: Value(checkpoint.sequenceNumber),
        ),
      );

      // הוספה לתור סנכרון (area subcollection path)
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${checkpoint.areaId}/${AppConstants.areaLayersNzSubcollection}',
        documentId: checkpoint.id,
        operation: 'update',
        data: checkpoint.toMap(),
      );

      return checkpoint;
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת נקודת ציון — disabled (add-only sync)
  Future<void> delete(String id) async {
    print('CheckpointRepository: delete() is disabled — areas/layers are add-only.');
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
      coordinates: Coordinate(
        lat: dbCheckpoint.lat,
        lng: dbCheckpoint.lng,
        utm: dbCheckpoint.utm,
      ),
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
