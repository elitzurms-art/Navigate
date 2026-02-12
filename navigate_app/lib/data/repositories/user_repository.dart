import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import '../../domain/entities/user.dart' as domain;
import '../datasources/remote/firebase_service.dart';
import '../datasources/local/app_database.dart';
import '../../core/constants/app_constants.dart';

/// Repository למשתמשים
class UserRepository {
  final FirebaseService? _firebaseService;
  final AppDatabase? _localDatabase;

  UserRepository([this._firebaseService, this._localDatabase]);

  /// קבלת כל המשתמשים (גרסה פשוטה)
  Future<List<domain.User>> getAll() async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final users = await db.select(db.users).get();
      return users.map((u) => _userFromRow(u)).toList();
    } catch (e) {
      return [];
    }
  }

  /// קבלת משתמש לפי UID
  Future<domain.User?> getUser(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final result = await (db.select(db.users)
        ..where((tbl) => tbl.uid.equals(uid)))
          .getSingleOrNull();
      if (result == null) return null;
      return _userFromRow(result);
    } catch (e) {
      return null;
    }
  }

  /// קבלת משתמש לפי מספר טלפון
  Future<domain.User?> getUserByPhoneNumber(String phoneNumber) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final result = await (db.select(db.users)
        ..where((tbl) => tbl.phoneNumber.equals(phoneNumber)))
          .getSingleOrNull();
      if (result == null) return null;
      return _userFromRow(result);
    } catch (e) {
      return null;
    }
  }

  /// קבלת משתמש לפי מספר אישי — חיפוש מקומי ב-Drift
  Future<domain.User?> getUserByPersonalNumber(String personalNumber) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      // חיפוש לפי uid (פורמט חדש — uid = personalNumber)
      var result = await (db.select(db.users)
        ..where((tbl) => tbl.uid.equals(personalNumber)))
          .getSingleOrNull();
      if (result != null) return _userFromRow(result);

      // fallback — חיפוש לפי personalNumber column (רשומות ישנות)
      result = await (db.select(db.users)
        ..where((tbl) => tbl.personalNumber.equals(personalNumber)))
          .getSingleOrNull();
      if (result != null) return _userFromRow(result);

      return null;
    } catch (e) {
      return null;
    }
  }

  /// בדיקה אם מספר אישי תפוס
  Future<bool> isPersonalNumberTaken(String personalNumber) async {
    final user = await getUserByPersonalNumber(personalNumber);
    return user != null;
  }

  /// קבלת כל המשתמשים
  Future<List<domain.User>> getAllUsers() async {
    return getAll();
  }

  /// שמירת משתמש (יצירה או עדכון) - מקומי
  Future<void> saveUserLocally(domain.User user) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      await db.into(db.users).insertOnConflictUpdate(
        UsersCompanion.insert(
          uid: user.uid,
          firstName: Value(user.firstName),
          lastName: Value(user.lastName),
          personalNumber: Value(user.uid), // personalNumber = uid
          fullName: user.fullName,
          username: '', // deprecated — kept for DB compat
          phoneNumber: user.phoneNumber,
          phoneVerified: user.phoneVerified,
          email: Value(user.email),
          emailVerified: Value(user.emailVerified),
          role: user.role,
          frameworkId: const Value(null), // deprecated
          unitId: Value(user.unitId),
          createdAt: user.createdAt,
          updatedAt: user.updatedAt,
        ),
      );
    } catch (e) {
      print('DEBUG: Error saving user locally: $e');
    }
  }

  /// המרת שורת DB לישות דומיין
  domain.User _userFromRow(User row) {
    return domain.User(
      uid: row.uid,
      firstName: row.firstName,
      lastName: row.lastName,
      phoneNumber: row.phoneNumber,
      phoneVerified: row.phoneVerified,
      email: row.email,
      emailVerified: row.emailVerified,
      role: row.role,
      unitId: row.unitId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// עדכון unitId ו-role של משתמש (מקומי + תור סנכרון)
  Future<void> updateUserUnitId(String uid, String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();

      // עדכון מקומי
      final updatedRows = await (db.update(db.users)
            ..where((tbl) => tbl.uid.equals(uid)))
          .write(
        UsersCompanion(
          unitId: Value(unitId),
          role: const Value('unit_admin'),
          updatedAt: Value(now),
        ),
      );

      print('DEBUG: Updated unitId=$unitId for user $uid ($updatedRows rows)');

      // הוספה לתור סנכרון
      if (updatedRows > 0) {
        await db.into(db.syncQueue).insert(
              SyncQueueCompanion.insert(
                collectionName: AppConstants.usersCollection,
                operation: 'update',
                recordId: uid,
                dataJson: '{"unitId":"$unitId","role":"unit_admin","updatedAt":"${now.toIso8601String()}"}',
                createdAt: now,
              ),
            );
      }
    } catch (e) {
      print('DEBUG: Error updating user unitId: $e');
    }
  }

  /// מחיקת משתמש מה-DB המקומי
  Future<void> deleteUser(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    await (db.delete(db.users)..where((tbl) => tbl.uid.equals(uid))).go();
  }
}
