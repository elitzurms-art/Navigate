import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/navigation_tree.dart' as domain;
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// מאגר נתוני עצי ניווט
class NavigationTreeRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל עצי הניווט
  Future<List<domain.NavigationTree>> getAll() async {
    try {
      print('DEBUG: Loading navigation trees from local database');
      final trees = await _db.select(_db.navigationTrees).get();
      print('DEBUG: Found ${trees.length} navigation trees');
      return trees.map((t) => _toDomain(t)).toList();
    } catch (e) {
      print('DEBUG: Error loading navigation trees: $e');
      rethrow;
    }
  }

  /// קבלת עץ ניווט לפי ID
  Future<domain.NavigationTree?> getById(String id) async {
    try {
      final tree = await (_db.select(_db.navigationTrees)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      return tree != null ? _toDomain(tree) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// יצירת עץ ניווט חדש
  Future<domain.NavigationTree> create(domain.NavigationTree tree) async {
    try {
      print('DEBUG: Creating navigation tree: ${tree.name}');

      // שמירה מקומית
      await _db.into(_db.navigationTrees).insert(
            NavigationTreesCompanion.insert(
              id: tree.id,
              name: tree.name,
              frameworksJson: _subFrameworksToJson(tree.subFrameworks),
              createdBy: tree.createdBy,
              createdAt: tree.createdAt,
              updatedAt: tree.updatedAt,
              treeType: Value(tree.treeType),
              sourceTreeId: Value(tree.sourceTreeId),
              unitId: Value(tree.unitId),
            ),
          );

      print('DEBUG: Navigation tree saved locally');

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.navigatorTreesCollection,
        documentId: tree.id,
        operation: 'create',
        data: tree.toMap(),
        priority: SyncPriority.high,
      );

      print('DEBUG: Navigation tree queued for sync');

      return tree;
    } catch (e) {
      print('DEBUG: Error creating navigation tree: $e');
      rethrow;
    }
  }

  /// עדכון עץ ניווט
  Future<domain.NavigationTree> update(domain.NavigationTree tree) async {
    try {
      print('DEBUG: Updating navigation tree: ${tree.name}');

      // עדכון מקומי
      await (_db.update(_db.navigationTrees)..where((t) => t.id.equals(tree.id)))
          .write(
        NavigationTreesCompanion(
          name: Value(tree.name),
          frameworksJson: Value(_subFrameworksToJson(tree.subFrameworks)),
          updatedAt: Value(tree.updatedAt),
          treeType: Value(tree.treeType),
          sourceTreeId: Value(tree.sourceTreeId),
          unitId: Value(tree.unitId),
        ),
      );

      print('DEBUG: Navigation tree updated locally');

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.navigatorTreesCollection,
        documentId: tree.id,
        operation: 'update',
        data: tree.toMap(),
        priority: SyncPriority.high,
      );

      return tree;
    } catch (e) {
      print('DEBUG: Error updating navigation tree: $e');
      rethrow;
    }
  }

  /// מחיקת עץ ניווט
  Future<void> delete(String id) async {
    try {
      print('DEBUG: Deleting navigation tree: $id');

      // מחיקה מקומית
      await (_db.delete(_db.navigationTrees)..where((t) => t.id.equals(id))).go();

      print('DEBUG: Navigation tree deleted locally');

      // הוספה לתור סנכרון — עדיפות גבוהה למחיקות
      await _syncManager.queueOperation(
        collection: AppConstants.navigatorTreesCollection,
        documentId: id,
        operation: 'delete',
        data: {'id': id},
        priority: SyncPriority.high,
      );
    } catch (e) {
      print('DEBUG: Error deleting navigation tree: $e');
      rethrow;
    }
  }

  /// המרה מטבלת DB לישות דומיין
  domain.NavigationTree _toDomain(NavigationTree data) {
    return domain.NavigationTree(
      id: data.id,
      name: data.name,
      subFrameworks: _subFrameworksFromJson(data.frameworksJson),
      createdBy: data.createdBy,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
      treeType: data.treeType,
      sourceTreeId: data.sourceTreeId,
      unitId: data.unitId,
    );
  }

  /// קבלת עצי ניווט לפי unitId
  Future<List<domain.NavigationTree>> getByUnitId(String unitId) async {
    try {
      final trees = await (_db.select(_db.navigationTrees)
            ..where((t) => t.unitId.equals(unitId)))
          .get();
      return trees.map((t) => _toDomain(t)).toList();
    } catch (e) {
      print('DEBUG: Error loading trees by unitId: $e');
      return [];
    }
  }

  /// שכפול עץ ניווט
  Future<domain.NavigationTree> clone(
    domain.NavigationTree source, {
    required String targetUnitId,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final clonedTree = domain.NavigationTree(
      id: now.millisecondsSinceEpoch.toString(),
      name: '${source.name} (עותק)',
      subFrameworks: source.subFrameworks,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
      treeType: source.treeType,
      sourceTreeId: source.id,
      unitId: targetUnitId,
    );

    return await create(clonedTree);
  }

  /// המרת subFrameworks ל-JSON
  String _subFrameworksToJson(List<domain.SubFramework> subFrameworks) {
    final list = subFrameworks.map((sf) => sf.toMap()).toList();
    return jsonEncode(list);
  }

  /// המרת JSON ל-subFrameworks (תומך גם בפורמט ישן של frameworks)
  List<domain.SubFramework> _subFrameworksFromJson(String json) {
    try {
      final List<dynamic> list = jsonDecode(json);
      if (list.isEmpty) return [];

      // בדיקה אם זה פורמט ישן (Framework) או חדש (SubFramework)
      final first = list.first as Map<String, dynamic>;
      if (first.containsKey('subFrameworks')) {
        // פורמט ישן — שטח את כל ה-SubFrameworks מכל ה-Frameworks
        final result = <domain.SubFramework>[];
        for (final item in list) {
          final fMap = item as Map<String, dynamic>;
          final fUnitId = fMap['unitId'] as String?;
          if (fMap['subFrameworks'] != null) {
            for (final sfMap in (fMap['subFrameworks'] as List)) {
              final sf = domain.SubFramework.fromMap(sfMap as Map<String, dynamic>);
              result.add(sf.unitId == null ? sf.copyWith(unitId: fUnitId) : sf);
            }
          }
        }
        return result;
      } else {
        // פורמט חדש
        return list.map((item) => domain.SubFramework.fromMap(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('DEBUG: Error parsing subFrameworks JSON: $e');
      return [];
    }
  }
}
