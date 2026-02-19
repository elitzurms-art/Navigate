import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import '../../domain/entities/user.dart' as domain;
import '../datasources/remote/firebase_service.dart';
import '../datasources/local/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../services/auth_mapping_service.dart';
import '../sync/sync_manager.dart';

/// Repository למשתמשים
class UserRepository {
  final FirebaseService? _firebaseService;
  final AppDatabase? _localDatabase;
  final SyncManager _syncManager = SyncManager();

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

  /// שמירת משתמש (יצירה או עדכון) - מקומי + תור סנכרון
  ///
  /// [queueSync] - true (ברירת מחדל) מוסיף לתור סנכרון.
  /// השתמש ב-false כשמושכים מ-Firestore (למניעת לולאה אינסופית).
  Future<void> saveUserLocally(domain.User user, {bool queueSync = true}) async {
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
          fcmToken: Value(user.fcmToken),
          firebaseUid: Value(user.firebaseUid),
          isApproved: Value(user.isApproved),
          createdAt: user.createdAt,
          updatedAt: user.updatedAt,
        ),
      );

      if (queueSync) {
        await _syncManager.queueOperation(
          collection: AppConstants.usersCollection,
          documentId: user.uid,
          operation: 'create',
          data: user.toMap(),
          priority: SyncPriority.high,
        );
      }
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
      fcmToken: row.fcmToken,
      firebaseUid: row.firebaseUid,
      isApproved: row.isApproved,
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

  /// עדכון FCM token של משתמש (מקומי + תור סנכרון)
  Future<void> updateFcmToken(String uid, String? fcmToken) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        fcmToken: Value(fcmToken),
        updatedAt: Value(now),
      ));

      await _syncManager.queueOperation(
        collection: AppConstants.usersCollection,
        documentId: uid,
        operation: 'update',
        data: {'fcmToken': fcmToken, 'updatedAt': now.toIso8601String()},
        priority: SyncPriority.high,
      );
    } catch (e) {
      print('DEBUG: Error updating FCM token: $e');
    }
  }

  /// עדכון תפקיד משתמש (מקומי + תור סנכרון)
  Future<void> updateUserRole(String uid, String role) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        role: Value(role),
        updatedAt: Value(now),
      ));

      await _syncManager.queueOperation(
        collection: AppConstants.usersCollection,
        documentId: uid,
        operation: 'update',
        data: {'role': role, 'updatedAt': now.toIso8601String()},
        priority: SyncPriority.high,
      );

      // עדכון auth_mapping אם יש firebaseUid
      final updatedUser = await getUser(uid);
      if (updatedUser?.firebaseUid != null) {
        await AuthMappingService().updateMappingForUser(updatedUser!);
      }
    } catch (e) {
      print('DEBUG: Error in updateUserRole: $e');
    }
  }

  /// מחיקת משתמש מה-DB המקומי
  Future<void> deleteUser(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    await (db.delete(db.users)..where((tbl) => tbl.uid.equals(uid))).go();
  }

  // ---------------------------------------------------------------------------
  // Onboarding / Approval Workflow
  // ---------------------------------------------------------------------------

  /// מנווט בוחר יחידה — שמירה עם isApproved=false
  Future<void> setUserUnit(String uid, String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        unitId: Value(unitId),
        isApproved: const Value(false),
        updatedAt: Value(now),
      ));

      await _syncManager.queueOperation(
        collection: AppConstants.usersCollection,
        documentId: uid,
        operation: 'update',
        data: {
          'unitId': unitId,
          'isApproved': false,
          'updatedAt': now.toIso8601String(),
        },
        priority: SyncPriority.high,
      );

      // עדכון auth_mapping אם יש firebaseUid
      final updatedUser = await getUser(uid);
      if (updatedUser?.firebaseUid != null) {
        await AuthMappingService().updateMappingForUser(updatedUser!);
      }
    } catch (e) {
      print('DEBUG: Error in setUserUnit: $e');
    }
  }

  /// מפקד מאשר משתמש — isApproved=true + אופציונלי שינוי תפקיד
  Future<void> approveUser(String uid, {String? role}) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      final companion = UsersCompanion(
        isApproved: const Value(true),
        updatedAt: Value(now),
        role: role != null ? Value(role) : const Value.absent(),
      );

      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(companion);

      final data = <String, dynamic>{
        'isApproved': true,
        'updatedAt': now.toIso8601String(),
      };
      if (role != null) data['role'] = role;

      await _syncManager.queueOperation(
        collection: AppConstants.usersCollection,
        documentId: uid,
        operation: 'update',
        data: data,
        priority: SyncPriority.high,
      );

      // עדכון auth_mapping אם יש firebaseUid
      final updatedUser = await getUser(uid);
      if (updatedUser?.firebaseUid != null) {
        await AuthMappingService().updateMappingForUser(updatedUser!);
      }
    } catch (e) {
      print('DEBUG: Error in approveUser: $e');
    }
  }

  /// מפקד דוחה משתמש — ניקוי unitId + isApproved=false
  Future<void> rejectUser(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        unitId: const Value(null),
        isApproved: const Value(false),
        updatedAt: Value(now),
      ));

      await _syncManager.queueOperation(
        collection: AppConstants.usersCollection,
        documentId: uid,
        operation: 'update',
        data: {
          'unitId': null,
          'isApproved': false,
          'updatedAt': now.toIso8601String(),
        },
        priority: SyncPriority.high,
      );
    } catch (e) {
      print('DEBUG: Error in rejectUser: $e');
    }
  }

  /// הוספה ידנית של משתמש ליחידה — isApproved=true מיידית
  Future<void> addUserToUnit(String uid, String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        unitId: Value(unitId),
        isApproved: const Value(true),
        updatedAt: Value(now),
      ));

      await _syncManager.queueOperation(
        collection: AppConstants.usersCollection,
        documentId: uid,
        operation: 'update',
        data: {
          'unitId': unitId,
          'isApproved': true,
          'updatedAt': now.toIso8601String(),
        },
        priority: SyncPriority.high,
      );

      // עדכון auth_mapping אם יש firebaseUid
      final updatedUser = await getUser(uid);
      if (updatedUser?.firebaseUid != null) {
        await AuthMappingService().updateMappingForUser(updatedUser!);
      }
    } catch (e) {
      print('DEBUG: Error in addUserToUnit: $e');
    }
  }

  /// קבלת כל המשתמשים הממתינים לאישור (למפתח — כל היחידות)
  Future<List<domain.User>> getAllPendingApprovalUsers() async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final results = await (db.select(db.users)
        ..where((tbl) =>
            tbl.unitId.isNotNull() &
            tbl.unitId.length.isBiggerThanValue(0) &
            tbl.isApproved.equals(false)))
          .get();
      return results.map((r) => _userFromRow(r)).toList();
    } catch (e) {
      print('DEBUG: Error in getAllPendingApprovalUsers: $e');
      return [];
    }
  }

  /// קבלת משתמשים הממתינים לאישור ביחידה מסוימת (או רשימת יחידות)
  Future<List<domain.User>> getPendingApprovalUsers(List<String> unitIds) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final results = await (db.select(db.users)
        ..where((tbl) =>
            tbl.unitId.isIn(unitIds) &
            tbl.isApproved.equals(false)))
          .get();
      return results.map((r) => _userFromRow(r)).toList();
    } catch (e) {
      print('DEBUG: Error in getPendingApprovalUsers: $e');
      return [];
    }
  }

  /// קבלת משתמשים מאושרים ביחידה מסוימת
  Future<List<domain.User>> getApprovedUsersForUnit(String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final results = await (db.select(db.users)
        ..where((tbl) =>
            tbl.unitId.equals(unitId) &
            tbl.isApproved.equals(true)))
          .get();
      return results.map((r) => _userFromRow(r)).toList();
    } catch (e) {
      print('DEBUG: Error in getApprovedUsersForUnit: $e');
      return [];
    }
  }

  /// איפוס שיוך יחידה לכל המשתמשים ביחידה — unitId=null, isApproved=false
  /// משתמש שהיחידה שלו נמחקה חוזר למסך בחירת יחידה (onboarding)
  /// איפוס כל משתמשי יחידה — unitId=null, isApproved=false
  /// מפקד/מנהל יחידה חוזר לתפקיד מנווט
  Future<void> resetUsersForUnit(String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      final users = await (db.select(db.users)
        ..where((tbl) => tbl.unitId.equals(unitId)))
          .get();

      for (final user in users) {
        final shouldResetRole =
            user.role == 'commander' || user.role == 'unit_admin';

        await (db.update(db.users)..where((tbl) => tbl.uid.equals(user.uid)))
            .write(UsersCompanion(
          unitId: const Value(null),
          isApproved: const Value(false),
          role: shouldResetRole
              ? const Value('navigator')
              : const Value.absent(),
          updatedAt: Value(now),
        ));

        await _syncManager.queueOperation(
          collection: AppConstants.usersCollection,
          documentId: user.uid,
          operation: 'update',
          data: {
            'unitId': null,
            'isApproved': false,
            if (shouldResetRole) 'role': 'navigator',
            'updatedAt': now.toIso8601String(),
          },
          priority: SyncPriority.high,
        );
      }

      print('DEBUG: Reset ${users.length} users from unit $unitId');
    } catch (e) {
      print('DEBUG: Error in resetUsersForUnit: $e');
    }
  }

  /// הסרת משתמש ספציפי מיחידה — unitId=null, isApproved=false
  /// מפקד/מנהל יחידה חוזר לתפקיד מנווט
  Future<void> removeUserFromUnit(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      // בדיקת תפקיד — מפקד/מנהל יחידה חוזר למנווט
      final row = await (db.select(db.users)
            ..where((tbl) => tbl.uid.equals(uid)))
          .getSingleOrNull();
      final shouldResetRole = row != null &&
          (row.role == 'commander' || row.role == 'unit_admin');

      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        unitId: const Value(null),
        isApproved: const Value(false),
        role: shouldResetRole
            ? const Value('navigator')
            : const Value.absent(),
        updatedAt: Value(now),
      ));

      await _syncManager.queueOperation(
        collection: AppConstants.usersCollection,
        documentId: uid,
        operation: 'update',
        data: {
          'unitId': null,
          'isApproved': false,
          if (shouldResetRole) 'role': 'navigator',
          'updatedAt': now.toIso8601String(),
        },
        priority: SyncPriority.high,
      );

      // עדכון auth_mapping אם יש firebaseUid
      final updatedUser = await getUser(uid);
      if (updatedUser?.firebaseUid != null) {
        await AuthMappingService().updateMappingForUser(updatedUser!);
      }

      print('DEBUG: Removed user $uid from unit'
          '${shouldResetRole ? " (role → navigator)" : ""}');
    } catch (e) {
      print('DEBUG: Error in removeUserFromUnit: $e');
    }
  }

  /// קבלת מפקדים מאושרים ביחידה (commander, unit_admin, admin, developer)
  Future<List<domain.User>> getCommandersForUnit(String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final results = await (db.select(db.users)
        ..where((tbl) =>
            tbl.unitId.equals(unitId) &
            tbl.isApproved.equals(true) &
            tbl.role.isIn(['commander', 'unit_admin', 'admin', 'developer'])))
          .get();
      return results.map((r) => _userFromRow(r)).toList();
    } catch (e) {
      print('DEBUG: Error in getCommandersForUnit: $e');
      return [];
    }
  }

  /// קבלת מנווטים מאושרים ביחידה (role=navigator)
  Future<List<domain.User>> getNavigatorsForUnit(String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final results = await (db.select(db.users)
        ..where((tbl) =>
            tbl.unitId.equals(unitId) &
            tbl.isApproved.equals(true) &
            tbl.role.equals('navigator')))
          .get();
      return results.map((r) => _userFromRow(r)).toList();
    } catch (e) {
      print('DEBUG: Error in getNavigatorsForUnit: $e');
      return [];
    }
  }
}
