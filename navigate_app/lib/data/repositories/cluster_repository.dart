import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/cluster.dart' as domain;
import '../../domain/entities/coordinate.dart';
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// מאגר נתוני ביצי איזור (BA)
class ClusterRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל הביצים
  Future<List<domain.Cluster>> getAll() async {
    try {
      final clusters = await _db.select(_db.clusters).get();
      return clusters.map((c) => _toDomain(c)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת ביצים לפי אזור
  Future<List<domain.Cluster>> getByArea(String areaId) async {
    try {
      final query = _db.select(_db.clusters)
        ..where((tbl) => tbl.areaId.equals(areaId));
      final clusters = await query.get();
      return clusters.map((c) => _toDomain(c)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת ביצה לפי ID
  Future<domain.Cluster?> getById(String id) async {
    try {
      final query = _db.select(_db.clusters)..where((tbl) => tbl.id.equals(id));
      final cluster = await query.getSingleOrNull();
      return cluster != null ? _toDomain(cluster) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת ביצה
  Future<void> add(domain.Cluster cluster) async {
    try {
      final coordinatesJson = jsonEncode(
        cluster.coordinates.map((c) => c.toMap()).toList(),
      );

      await _db.into(_db.clusters).insert(
            ClustersCompanion.insert(
              id: cluster.id,
              areaId: cluster.areaId,
              name: cluster.name,
              description: cluster.description,
              coordinatesJson: coordinatesJson,
              color: cluster.color,
              strokeWidth: cluster.strokeWidth,
              fillOpacity: cluster.fillOpacity,
              createdBy: '', // TODO: get from auth
              createdAt: cluster.createdAt,
              updatedAt: cluster.updatedAt,
            ),
          );
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${cluster.areaId}/${AppConstants.areaLayersBaSubcollection}',
        operation: 'create',
        documentId: cluster.id,
        data: cluster.toMap(),
        priority: SyncPriority.high,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון ביצה
  Future<void> update(domain.Cluster cluster) async {
    try {
      final coordinatesJson = jsonEncode(
        cluster.coordinates.map((c) => c.toMap()).toList(),
      );

      await (_db.update(_db.clusters)..where((tbl) => tbl.id.equals(cluster.id))).write(
        ClustersCompanion(
          areaId: Value(cluster.areaId),
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
        collection: '${AppConstants.areasCollection}/${cluster.areaId}/${AppConstants.areaLayersBaSubcollection}',
        operation: 'update',
        documentId: cluster.id,
        data: cluster.toMap(),
        priority: SyncPriority.high,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת ביצה (מקומי + סנכרון)
  Future<void> delete(String id, {required String areaId}) async {
    await (_db.delete(_db.clusters)..where((t) => t.id.equals(id))).go();
    await _syncManager.queueOperation(
      collection: '${AppConstants.areasCollection}/$areaId/${AppConstants.areaLayersBaSubcollection}',
      documentId: id,
      operation: 'delete',
      data: {'id': id},
      priority: SyncPriority.high,
    );
  }

  /// מחיקת מספר ביצות
  Future<void> deleteMany(List<String> ids, {required String areaId}) async {
    for (final id in ids) {
      await delete(id, areaId: areaId);
    }
  }

  /// המרה מ-Drift ל-Domain
  domain.Cluster _toDomain(Cluster row) {
    final coordinatesList = (jsonDecode(row.coordinatesJson) as List)
        .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
        .toList();

    return domain.Cluster(
      id: row.id,
      areaId: row.areaId,
      name: row.name,
      description: row.description,
      coordinates: coordinatesList,
      color: row.color,
      strokeWidth: row.strokeWidth,
      fillOpacity: row.fillOpacity,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
