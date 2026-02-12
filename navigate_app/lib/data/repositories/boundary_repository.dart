import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/boundary.dart' as domain;
import '../../domain/entities/coordinate.dart';
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// מאגר נתוני גבולות גדוד (GG)
class BoundaryRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל הגבולות
  Future<List<domain.Boundary>> getAll() async {
    try {
      final boundaries = await _db.select(_db.boundaries).get();
      return boundaries.map((b) => _toDomain(b)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת גבולות לפי אזור
  Future<List<domain.Boundary>> getByArea(String areaId) async {
    try {
      final query = _db.select(_db.boundaries)
        ..where((tbl) => tbl.areaId.equals(areaId));
      final boundaries = await query.get();
      return boundaries.map((b) => _toDomain(b)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת גבול לפי ID
  Future<domain.Boundary?> getById(String id) async {
    try {
      final query = _db.select(_db.boundaries)..where((tbl) => tbl.id.equals(id));
      final boundary = await query.getSingleOrNull();
      return boundary != null ? _toDomain(boundary) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת גבול
  Future<void> add(domain.Boundary boundary) async {
    try {
      final coordinatesJson = jsonEncode(
        boundary.coordinates.map((c) => c.toMap()).toList(),
      );

      await _db.into(_db.boundaries).insert(
            BoundariesCompanion.insert(
              id: boundary.id,
              areaId: boundary.areaId,
              name: boundary.name,
              description: boundary.description,
              coordinatesJson: coordinatesJson,
              color: boundary.color,
              strokeWidth: boundary.strokeWidth,
              createdBy: '', // TODO: get from auth
              createdAt: boundary.createdAt,
              updatedAt: boundary.updatedAt,
            ),
          );
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${boundary.areaId}/${AppConstants.areaLayersGgSubcollection}',
        operation: 'insert',
        documentId: boundary.id,
        data: boundary.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון גבול
  Future<void> update(domain.Boundary boundary) async {
    try {
      final coordinatesJson = jsonEncode(
        boundary.coordinates.map((c) => c.toMap()).toList(),
      );

      await (_db.update(_db.boundaries)..where((tbl) => tbl.id.equals(boundary.id))).write(
        BoundariesCompanion(
          areaId: Value(boundary.areaId),
          name: Value(boundary.name),
          description: Value(boundary.description),
          coordinatesJson: Value(coordinatesJson),
          color: Value(boundary.color),
          strokeWidth: Value(boundary.strokeWidth),
          updatedAt: Value(boundary.updatedAt),
        ),
      );
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${boundary.areaId}/${AppConstants.areaLayersGgSubcollection}',
        operation: 'update',
        documentId: boundary.id,
        data: boundary.toMap(),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת גבול — disabled (add-only sync)
  Future<void> delete(String id) async {
    print('BoundaryRepository: delete() is disabled — areas/layers are add-only.');
  }

  /// המרה מ-Drift ל-Domain
  domain.Boundary _toDomain(Boundary row) {
    final coordinatesList = (jsonDecode(row.coordinatesJson) as List)
        .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
        .toList();

    return domain.Boundary(
      id: row.id,
      areaId: row.areaId,
      name: row.name,
      description: row.description,
      coordinates: coordinatesList,
      color: row.color,
      strokeWidth: row.strokeWidth,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
