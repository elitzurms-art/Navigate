import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/safety_point.dart' as domain;
import '../../domain/entities/coordinate.dart';
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// מאגר נתוני נקודות תורפה בטיחותיות (נת"ב)
class SafetyPointRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל נקודות הבטיחות
  Future<List<domain.SafetyPoint>> getAll() async {
    try {
      final points = await _db.select(_db.safetyPoints).get();
      return points.map((p) => _toDomain(p)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת נקודות בטיחות לפי אזור
  Future<List<domain.SafetyPoint>> getByArea(String areaId) async {
    try {
      final query = _db.select(_db.safetyPoints)
        ..where((tbl) => tbl.areaId.equals(areaId))
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.sequenceNumber)]);
      final points = await query.get();
      return points.map((p) => _toDomain(p)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת נקודת בטיחות לפי ID
  Future<domain.SafetyPoint?> getById(String id) async {
    try {
      final query = _db.select(_db.safetyPoints)..where((tbl) => tbl.id.equals(id));
      final point = await query.getSingleOrNull();
      return point != null ? _toDomain(point) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// הוספת נקודת תורפה בטיחותית
  Future<void> add(domain.SafetyPoint point) async {
    try {
      await _db.into(_db.safetyPoints).insert(
            SafetyPointsCompanion.insert(
              id: point.id,
              areaId: point.areaId,
              name: point.name,
              description: point.description,
              type: Value(point.type),
              lat: Value(point.coordinates?.lat),
              lng: Value(point.coordinates?.lng),
              utm: Value(point.coordinates?.utm),
              coordinatesJson: Value(
                point.polygonCoordinates != null
                    ? jsonEncode(point.polygonCoordinates!.map((c) => c.toMap()).toList())
                    : null,
              ),
              sequenceNumber: point.sequenceNumber,
              severity: point.severity,
              createdBy: '', // TODO: get from auth
              createdAt: point.createdAt,
              updatedAt: point.updatedAt,
            ),
          );
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${point.areaId}/${AppConstants.areaLayersNbSubcollection}',
        operation: 'insert',
        documentId: point.id,
        data: point.toMap(),
        priority: SyncPriority.high,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון נקודת תורפה בטיחותית
  Future<void> update(domain.SafetyPoint point) async {
    try {
      await (_db.update(_db.safetyPoints)..where((tbl) => tbl.id.equals(point.id))).write(
        SafetyPointsCompanion(
          areaId: Value(point.areaId),
          name: Value(point.name),
          description: Value(point.description),
          type: Value(point.type),
          lat: Value(point.coordinates?.lat),
          lng: Value(point.coordinates?.lng),
          utm: Value(point.coordinates?.utm),
          coordinatesJson: Value(
            point.polygonCoordinates != null
                ? jsonEncode(point.polygonCoordinates!.map((c) => c.toMap()).toList())
                : null,
          ),
          sequenceNumber: Value(point.sequenceNumber),
          severity: Value(point.severity),
          updatedAt: Value(point.updatedAt),
        ),
      );
      await _syncManager.queueOperation(
        collection: '${AppConstants.areasCollection}/${point.areaId}/${AppConstants.areaLayersNbSubcollection}',
        operation: 'update',
        documentId: point.id,
        data: point.toMap(),
        priority: SyncPriority.high,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת נקודת בטיחות — disabled (add-only sync)
  Future<void> delete(String id) async {
    print('SafetyPointRepository: delete() is disabled — areas/layers are add-only.');
  }

  /// המרה מ-Drift ל-Domain
  domain.SafetyPoint _toDomain(SafetyPoint row) {
    return domain.SafetyPoint(
      id: row.id,
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
      polygonCoordinates: row.type == 'polygon' && row.coordinatesJson != null
          ? (jsonDecode(row.coordinatesJson!) as List)
              .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
              .toList()
          : null,
      sequenceNumber: row.sequenceNumber,
      severity: row.severity,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
