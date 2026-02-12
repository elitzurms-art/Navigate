import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/navigator_tree.dart' as domain;
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';

/// מאגר נתוני עצי מנווטים
class NavigatorTreeRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncManager _syncManager = SyncManager();

  /// קבלת כל העצים
  Future<List<domain.NavigatorTree>> getAll() async {
    try {
      final trees = await _db.select(_db.navigationTrees).get();
      return trees.map((t) => _toDomain(t)).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// קבלת עץ לפי ID
  Future<domain.NavigatorTree?> getById(String id) async {
    try {
      final tree = await (_db.select(_db.navigationTrees)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      return tree != null ? _toDomain(tree) : null;
    } catch (e) {
      rethrow;
    }
  }

  /// יצירת עץ חדש
  Future<domain.NavigatorTree> create(domain.NavigatorTree tree) async {
    try {
      // שמירה מקומית - stub: mapping old NavigatorTree fields to new NavigationTrees table
      final now = DateTime.now();
      await _db.into(_db.navigationTrees).insert(
            NavigationTreesCompanion.insert(
              id: tree.id,
              name: tree.name,
              frameworksJson: '[]', // stub - old entity has no frameworks
              createdBy: tree.createdBy,
              createdAt: now,
              updatedAt: now,
            ),
          );

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.navigatorTreesCollection,
        documentId: tree.id,
        operation: 'create',
        data: tree.toMap(),
      );

      return tree;
    } catch (e) {
      rethrow;
    }
  }

  /// עדכון עץ
  Future<domain.NavigatorTree> update(domain.NavigatorTree tree) async {
    try {
      // עדכון מקומי - stub: mapping old NavigatorTree fields to new NavigationTrees table
      await (_db.update(_db.navigationTrees)
            ..where((t) => t.id.equals(tree.id)))
          .write(
        NavigationTreesCompanion(
          name: Value(tree.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // הוספה לתור סנכרון
      await _syncManager.queueOperation(
        collection: AppConstants.navigatorTreesCollection,
        documentId: tree.id,
        operation: 'update',
        data: tree.toMap(),
      );

      return tree;
    } catch (e) {
      rethrow;
    }
  }

  /// מחיקת עץ
  Future<void> delete(String id) async {
    try {
      // מחיקה מקומית
      await (_db.delete(_db.navigationTrees)..where((t) => t.id.equals(id))).go();

      // הוספה לתור סנכרון — עדיפות גבוהה למחיקות
      await _syncManager.queueOperation(
        collection: AppConstants.navigatorTreesCollection,
        documentId: id,
        operation: 'delete',
        data: {'id': id},
        priority: SyncPriority.high,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// המרה מטבלה לישות דומיין (stub - new table has different columns)
  domain.NavigatorTree _toDomain(NavigationTree dbTree) {
    return domain.NavigatorTree(
      id: dbTree.id,
      name: dbTree.name,
      type: 'single', // stub - new table has no type column
      members: [], // stub - new table has no members
      createdBy: dbTree.createdBy,
      permissions: const domain.TreePermissions(
        editors: [],
        viewers: [],
      ),
    );
  }

  /// Stream של עצים
  Stream<List<domain.NavigatorTree>> watchAll() {
    return _db.select(_db.navigationTrees).watch().map(
          (trees) => trees.map((t) => _toDomain(t)).toList(),
        );
  }
}
