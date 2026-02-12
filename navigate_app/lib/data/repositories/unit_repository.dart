import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/unit.dart' as domain;
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// Repository for managing units (Drift + Firestore sync)
///
/// Firestore structure:
///   /units/{unitId}                          -- unit document
///   /units/{unitId}/members/{userId}         -- membership subcollection
class UnitRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  // ===========================================================================
  // Unit CRUD (local DB + sync queue)
  // ===========================================================================

  /// Create a new unit
  Future<domain.Unit> create(domain.Unit unit) async {
    print('DEBUG: Creating unit: ${unit.name}');
    try {
      // Local save
      await _db.into(_db.units).insert(
            UnitsCompanion.insert(
              id: unit.id,
              name: unit.name,
              description: unit.description,
              type: unit.type,
              parentUnitId: Value(unit.parentUnitId),
              managerIdsJson: jsonEncode(unit.managerIds),
              createdBy: unit.createdBy,
              createdAt: unit.createdAt,
              updatedAt: unit.updatedAt,
              isClassified: Value(unit.isClassified),
              level: Value(unit.level),
              isNavigators: Value(unit.isNavigators),
              isGeneral: Value(unit.isGeneral),
            ),
          );

      print('DEBUG: Unit saved locally');

      // Queue for sync
      await _syncManager.queueOperation(
        collection: AppConstants.unitsCollection,
        documentId: unit.id,
        operation: 'create',
        data: unit.toMap(),
        priority: SyncPriority.high,
      );

      print('DEBUG: Unit queued for sync');
      return unit;
    } catch (e) {
      print('DEBUG: Error creating unit: $e');
      rethrow;
    }
  }

  /// Update a unit
  Future<domain.Unit> update(domain.Unit unit) async {
    print('DEBUG: Updating unit: ${unit.name}');
    try {
      // Local update
      await (_db.update(_db.units)..where((t) => t.id.equals(unit.id))).write(
        UnitsCompanion(
          name: Value(unit.name),
          description: Value(unit.description),
          type: Value(unit.type),
          parentUnitId: Value(unit.parentUnitId),
          managerIdsJson: Value(jsonEncode(unit.managerIds)),
          updatedAt: Value(unit.updatedAt),
          isClassified: Value(unit.isClassified),
          level: Value(unit.level),
          isNavigators: Value(unit.isNavigators),
          isGeneral: Value(unit.isGeneral),
        ),
      );

      print('DEBUG: Unit updated locally');

      // Queue for sync
      await _syncManager.queueOperation(
        collection: AppConstants.unitsCollection,
        documentId: unit.id,
        operation: 'update',
        data: unit.toMap(),
        priority: SyncPriority.high,
      );

      return unit;
    } catch (e) {
      print('DEBUG: Error updating unit: $e');
      rethrow;
    }
  }

  /// Delete a unit
  Future<void> delete(String id) async {
    print('DEBUG: Deleting unit: $id');
    try {
      // Local delete
      await (_db.delete(_db.units)..where((t) => t.id.equals(id))).go();

      print('DEBUG: Unit deleted locally');

      // Queue for sync — high priority to ensure delete reaches Firestore before potential reinstall
      await _syncManager.queueOperation(
        collection: AppConstants.unitsCollection,
        documentId: id,
        operation: 'delete',
        data: {'id': id},
        priority: SyncPriority.high,
      );
    } catch (e) {
      print('DEBUG: Error deleting unit: $e');
      rethrow;
    }
  }

  /// Delete a unit and all its children (cascade), their trees, and navigations
  Future<void> deleteWithCascade(String id) async {
    print('DEBUG: Cascade deleting unit: $id');
    try {
      // Find all child units recursively
      final allDescendantIds = await getDescendantIds(id);
      final allIdsToDelete = [id, ...allDescendantIds];

      print('DEBUG: Will cascade delete ${allIdsToDelete.length} units: $allIdsToDelete');

      // Delete navigations that reference these units (via trees that belong to these units)
      final treesToDelete = <String>[];
      for (final unitId in allIdsToDelete) {
        final trees = await (_db.select(_db.navigationTrees)
              ..where((t) => t.unitId.equals(unitId)))
            .get();
        for (final tree in trees) {
          treesToDelete.add(tree.id);
          // Delete navigations that use this tree
          final navs = await (_db.select(_db.navigations)
                ..where((t) => t.treeId.equals(tree.id)))
              .get();
          for (final nav in navs) {
            await (_db.delete(_db.navigations)..where((t) => t.id.equals(nav.id))).go();
            await _syncManager.queueOperation(
              collection: AppConstants.navigationsCollection,
              documentId: nav.id,
              operation: 'delete',
              data: {'id': nav.id},
              priority: SyncPriority.high,
            );
          }
        }
      }

      // Delete trees
      for (final treeId in treesToDelete) {
        await (_db.delete(_db.navigationTrees)..where((t) => t.id.equals(treeId))).go();
        await _syncManager.queueOperation(
          collection: AppConstants.navigatorTreesCollection,
          documentId: treeId,
          operation: 'delete',
          data: {'id': treeId},
          priority: SyncPriority.high,
        );
      }

      // Delete all units (children first, then parent)
      for (final unitId in allIdsToDelete.reversed) {
        await (_db.delete(_db.units)..where((t) => t.id.equals(unitId))).go();
        await _syncManager.queueOperation(
          collection: AppConstants.unitsCollection,
          documentId: unitId,
          operation: 'delete',
          data: {'id': unitId},
          priority: SyncPriority.high,
        );
      }

      print('DEBUG: Cascade delete complete for unit $id');
    } catch (e) {
      print('DEBUG: Error in cascade delete: $e');
      rethrow;
    }
  }

  /// Recursively get all descendant unit IDs
  Future<List<String>> getDescendantIds(String parentId) async {
    final children = await (_db.select(_db.units)
          ..where((t) => t.parentUnitId.equals(parentId)))
        .get();

    final result = <String>[];
    for (final child in children) {
      result.add(child.id);
      result.addAll(await getDescendantIds(child.id));
    }
    return result;
  }

  /// Get all units
  Future<List<domain.Unit>> getAll() async {
    try {
      print('DEBUG: Loading units from local database');
      final rows = await _db.select(_db.units).get();
      print('DEBUG: Found ${rows.length} units');
      return rows.map((row) => _toDomain(row)).toList();
    } catch (e) {
      print('DEBUG: Error loading units: $e');
      return [];
    }
  }

  /// Get unit by ID
  Future<domain.Unit?> getById(String id) async {
    try {
      final row = await (_db.select(_db.units)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      return row != null ? _toDomain(row) : null;
    } catch (e) {
      print('DEBUG: Error loading unit: $e');
      return null;
    }
  }

  /// Get sub-units
  Future<List<domain.Unit>> getSubUnits(String parentId) async {
    try {
      final rows = await (_db.select(_db.units)
            ..where((t) => t.parentUnitId.equals(parentId)))
          .get();
      return rows.map((row) => _toDomain(row)).toList();
    } catch (e) {
      print('DEBUG: Error loading sub-units: $e');
      return [];
    }
  }

  /// Get units where user is a manager
  Future<List<domain.Unit>> getByAdmin(String userId) async {
    try {
      final allUnits = await getAll();
      return allUnits
          .where((unit) => unit.managerIds.contains(userId))
          .toList();
    } catch (e) {
      print('DEBUG: Error loading units by admin: $e');
      return [];
    }
  }

  // ===========================================================================
  // Members subcollection -- /units/{unitId}/members/{userId}
  // ===========================================================================

  /// Add a member to a unit's Firestore subcollection
  ///
  /// Writes to /units/{unitId}/members/{userId}
  /// [memberData] should contain at minimum: { userId, role, joinedAt }
  Future<void> addMember({
    required String unitId,
    required String userId,
    required Map<String, dynamic> memberData,
  }) async {
    print('DEBUG: Adding member $userId to unit $unitId');
    try {
      final path = AppConstants.unitMembersPath(unitId);

      // Queue for Firestore sync (subcollection path)
      await _syncManager.queueOperation(
        collection: path,
        documentId: userId,
        operation: 'create',
        data: {
          'userId': userId,
          ...memberData,
          'joinedAt': memberData['joinedAt'] ?? DateTime.now().toIso8601String(),
        },
      );

      print('DEBUG: Member add queued for sync');
    } catch (e) {
      print('DEBUG: Error adding member: $e');
      rethrow;
    }
  }

  /// Remove a member from a unit's Firestore subcollection
  Future<void> removeMember({
    required String unitId,
    required String userId,
  }) async {
    print('DEBUG: Removing member $userId from unit $unitId');
    try {
      final path = AppConstants.unitMembersPath(unitId);

      await _syncManager.queueOperation(
        collection: path,
        documentId: userId,
        operation: 'delete',
        data: {'userId': userId},
        priority: SyncPriority.high,
      );

      print('DEBUG: Member removal queued for sync');
    } catch (e) {
      print('DEBUG: Error removing member: $e');
      rethrow;
    }
  }

  /// Update a member's role in the unit
  Future<void> updateMemberRole({
    required String unitId,
    required String userId,
    required String newRole,
  }) async {
    print('DEBUG: Updating role of member $userId in unit $unitId to $newRole');
    try {
      final path = AppConstants.unitMembersPath(unitId);

      await _syncManager.queueOperation(
        collection: path,
        documentId: userId,
        operation: 'update',
        data: {
          'userId': userId,
          'role': newRole,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      print('DEBUG: Error updating member role: $e');
      rethrow;
    }
  }

  /// Get all members of a unit directly from Firestore
  ///
  /// Returns a list of member data maps from /units/{unitId}/members
  Future<List<Map<String, dynamic>>> getMembers(String unitId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.unitsCollection)
          .doc(unitId)
          .collection(AppConstants.unitMembersSubcollection)
          .get()
          .timeout(const Duration(seconds: 10));

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['userId'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('DEBUG: Error fetching members from Firestore: $e');
      return [];
    }
  }

  /// Check if a user is a member of a specific unit
  Future<bool> isMember({
    required String unitId,
    required String userId,
  }) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.unitsCollection)
          .doc(unitId)
          .collection(AppConstants.unitMembersSubcollection)
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 10));

      return doc.exists;
    } catch (e) {
      print('DEBUG: Error checking membership: $e');
      return false;
    }
  }

  // ===========================================================================
  // Firestore sync (pull from server)
  // ===========================================================================

  /// Pull units from Firestore and upsert into local DB
  Future<void> syncFromFirestore() async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.unitsCollection)
          .get()
          .timeout(const Duration(seconds: 15));

      print('DEBUG: Pulled ${snapshot.docs.length} units from Firestore');

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;

        final unit = domain.Unit.fromMap(data);
        final existing = await getById(unit.id);

        if (existing == null) {
          await _db.into(_db.units).insert(
                UnitsCompanion.insert(
                  id: unit.id,
                  name: unit.name,
                  description: unit.description,
                  type: unit.type,
                  parentUnitId: Value(unit.parentUnitId),
                  managerIdsJson: jsonEncode(unit.managerIds),
                  createdBy: unit.createdBy,
                  createdAt: unit.createdAt,
                  updatedAt: unit.updatedAt,
                  isClassified: Value(unit.isClassified),
                  level: Value(unit.level),
                  isNavigators: Value(unit.isNavigators),
                  isGeneral: Value(unit.isGeneral),
                ),
              );
        } else {
          await (_db.update(_db.units)..where((t) => t.id.equals(unit.id)))
              .write(
            UnitsCompanion(
              name: Value(unit.name),
              description: Value(unit.description),
              type: Value(unit.type),
              parentUnitId: Value(unit.parentUnitId),
              managerIdsJson: Value(jsonEncode(unit.managerIds)),
              updatedAt: Value(unit.updatedAt),
              isClassified: Value(unit.isClassified),
              level: Value(unit.level),
              isNavigators: Value(unit.isNavigators),
              isGeneral: Value(unit.isGeneral),
            ),
          );
        }
      }
    } catch (e) {
      print('DEBUG: Error syncing units from Firestore: $e');
    }
  }

  // ===========================================================================
  // Domain conversion helpers
  // ===========================================================================

  /// Convert DB row to domain entity
  domain.Unit _toDomain(Unit row) {
    return domain.Unit(
      id: row.id,
      name: row.name,
      description: row.description,
      type: row.type,
      parentUnitId: row.parentUnitId,
      managerIds: _parseManagerIds(row.managerIdsJson),
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isClassified: row.isClassified,
      level: row.level,
      isNavigators: row.isNavigators,
      isGeneral: row.isGeneral,
    );
  }

  /// Parse manager IDs JSON string to list
  List<String> _parseManagerIds(String json) {
    try {
      final List<dynamic> list = jsonDecode(json);
      return list.cast<String>();
    } catch (e) {
      print('DEBUG: Error parsing managerIds JSON: $e');
      return [];
    }
  }

  /// Watch all units (live stream from local DB)
  Stream<List<domain.Unit>> watchAll() {
    return _db.select(_db.units).watch().map(
          (rows) => rows.map((row) => _toDomain(row)).toList(),
        );
  }
}
