import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import '../../domain/entities/user.dart' as domain;
import '../datasources/remote/firebase_service.dart';
import '../datasources/local/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../sync/sync_manager.dart';
import 'navigation_repository.dart';

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
  /// תומך בפורמטים: 05XXXXXXXX, +9725XXXXXXXX
  /// אם יש כמה משתמשים עם אותו טלפון — מחזיר את זה שאימת (phoneVerified)
  Future<domain.User?> getUserByPhoneNumber(String phoneNumber) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      // 1. חיפוש לפי הערך שהתקבל
      var results = await (db.select(db.users)
        ..where((tbl) => tbl.phoneNumber.equals(phoneNumber)))
          .get();

      // 2. ניסיון בפורמט אלטרנטיבי (05↔+972)
      if (results.isEmpty) {
        String? altFormat;
        if (phoneNumber.startsWith('05') && phoneNumber.length == 10) {
          altFormat = '+972${phoneNumber.substring(1)}';
        } else if (phoneNumber.startsWith('+9725')) {
          altFormat = '0${phoneNumber.substring(4)}';
        }

        if (altFormat != null) {
          results = await (db.select(db.users)
            ..where((tbl) => tbl.phoneNumber.equals(altFormat!)))
              .get();
        }
      }

      if (results.isEmpty) return null;

      // אם יש כמה תוצאות — העדפה למשתמש שאימת טלפון
      if (results.length > 1) {
        final verified = results.where((u) => u.phoneVerified).toList();
        if (verified.isNotEmpty) {
          // מהמאומתים — העדפה לאחרון שנעדכן
          verified.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return _userFromRow(verified.first);
        }
      }
      return _userFromRow(results.first);
    } catch (e) {
      return null;
    }
  }

  /// קבלת משתמש לפי כתובת מייל — חיפוש מקומי ב-Drift (case-insensitive)
  Future<domain.User?> getUserByEmail(String email) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final results = await (db.select(db.users)
        ..where((tbl) => tbl.email.lower().equals(normalizedEmail)))
          .get();

      if (results.isEmpty) return null;
      return _userFromRow(results.first);
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
          isApproved: Value(user.isApproved), // bool for Drift compat
          approvalStatus: Value(user.approvalStatus),
          soloQuizPassedAt: Value(user.soloQuizPassedAt),
          soloQuizScore: Value(user.soloQuizScore),
          createdAt: user.createdAt,
          updatedAt: user.updatedAt,
        ),
      );

      if (queueSync) {
        final syncData = user.toMap();
        // unitId, isApproved, role are admin-controlled — only commander
        // operations (approveUser, removeUserFromUnit, etc.) push these.
        syncData.remove('unitId');
        syncData.remove('isApproved');
        syncData.remove('role');

        await _syncManager.queueOperation(
          collection: AppConstants.usersCollection,
          documentId: user.uid,
          operation: 'update',
          data: syncData,
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
      approvalStatus: row.approvalStatus ?? (row.isApproved ? 'approved' : null),
      soloQuizPassedAt: row.soloQuizPassedAt,
      soloQuizScore: row.soloQuizScore,
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

  /// עדכון תפקיד משתמש (מקומי + Firestore ישיר)
  Future<void> updateUserRole(String uid, String role) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      // Drift מקומי — UI מיידי
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        role: Value(role),
        updatedAt: Value(now),
      ));

      // כתיבה ישירה ל-Firestore (עוקף את sync queue שמסיר role)
      try {
        await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .update({'role': role, 'updatedAt': FieldValue.serverTimestamp()});
      } catch (e) {
        print('DEBUG: Direct Firestore failed for updateUserRole, queueing: $e');
        await _syncManager.queueOperation(
          collection: AppConstants.usersCollection,
          documentId: uid,
          operation: 'update',
          data: {'role': role, 'updatedAt': now.toIso8601String()},
          priority: SyncPriority.high,
        );
      }
      // Custom claims updated automatically by onUserWrite Cloud Function trigger
    } catch (e) {
      print('DEBUG: Error in updateUserRole: $e');
    }
  }

  /// מחיקת משתמש מה-DB המקומי
  Future<void> deleteUser(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    await (db.delete(db.users)..where((tbl) => tbl.uid.equals(uid))).go();
  }

  /// מחיקת משתמש לצמיתות (hard-delete) — developer בלבד
  Future<void> deleteUserPermanently(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      // Cascade: הסרת המשתמש מכל הניווטים
      final navigationRepo = NavigationRepository();
      await navigationRepo.removeParticipantFromAll(uid);

      // מחיקה מקומית
      await (db.delete(db.users)..where((tbl) => tbl.uid.equals(uid))).go();

      // Hard-delete מ-Firestore — מחיקת המסמך לחלוטין
      try {
        await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .delete()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        // Fallback: אם Firestore לא זמין, שומרים בתור סנכרון כ-hard_delete
        print('DEBUG: Firestore hard-delete failed, queueing: $e');
        await _syncManager.queueOperation(
          collection: AppConstants.usersCollection,
          documentId: uid,
          operation: 'hard_delete',
          data: {'uid': uid},
          priority: SyncPriority.high,
        );
      }

      print('DEBUG: User $uid deleted permanently');
    } catch (e) {
      print('DEBUG: Error in deleteUserPermanently: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Onboarding / Approval Workflow
  // ---------------------------------------------------------------------------

  /// מנווט בוחר יחידה — שמירה עם isApproved="pending"
  Future<void> setUserUnit(String uid, String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      // עדכון Drift מקומי — למצב UI מיידי
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        unitId: Value(unitId),
        approvalStatus: const Value('pending'),
        updatedAt: Value(now),
      ));

      // Firestore — כל השדות + isApproved="pending" (JOIN rule allows self to set "pending")
      final fullUser = await getUser(uid);
      final Map<String, dynamic> firestoreData;
      if (fullUser != null) {
        firestoreData = fullUser.toMap();
        firestoreData['unitId'] = unitId;
        firestoreData['isApproved'] = 'pending';
        firestoreData.remove('role');
        firestoreData['updatedAt'] = FieldValue.serverTimestamp();
      } else {
        firestoreData = {
          'uid': uid,
          'unitId': unitId,
          'isApproved': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        };
      }

      // שלב 1: יצירת/עדכון המסמך ללא isApproved (create rule blocks privilege fields)
      final pendingValue = firestoreData.remove('isApproved');
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .set(firestoreData, SetOptions(merge: true));

      // שלב 2: עדכון isApproved ל-"pending" (JOIN/RE-REQUEST update rule allows this)
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({'isApproved': pendingValue ?? 'pending', 'updatedAt': FieldValue.serverTimestamp()});

      // ignore: unawaited_futures
      _syncManager.refreshUserContext();
    } catch (e) {
      print('DEBUG: Error in setUserUnit: $e');
      rethrow;
    }
  }

  /// מפקד מאשר משתמש — isApproved=true + אופציונלי שינוי תפקיד
  Future<void> approveUser(String uid, {String? role}) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      // Drift מקומי — UI מיידי
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        isApproved: const Value(true),
        approvalStatus: const Value('approved'),
        updatedAt: Value(now),
        role: role != null ? Value(role) : const Value.absent(),
      ));

      // Firestore — רק שדות האישור (מפקד יוצר את isApproved ו-role)
      final firestoreData = <String, dynamic>{
        'isApproved': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (role != null) firestoreData['role'] = role;

      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .set(firestoreData, SetOptions(merge: true));
    } catch (e) {
      print('DEBUG: Error in approveUser: $e');
    }
  }

  /// מפקד דוחה משתמש — unitId נשמר, isApproved=false (rejected)
  Future<void> rejectUser(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      // Drift מקומי — UI מיידי (שומרים unitId — משתמש יראה דיאלוג דחייה)
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        isApproved: const Value(false),
        approvalStatus: const Value('rejected'),
        updatedAt: Value(now),
      ));

      // Firestore — isApproved=false, שומרים unitId
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'isApproved': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // הסרת המשתמש מניווטים
      await NavigationRepository().removeParticipantFromAll(uid);
    } catch (e) {
      print('DEBUG: Error in rejectUser: $e');
    }
  }

  /// הוספה ידנית של משתמש ליחידה — isApproved=true מיידית (Firestore ישיר)
  Future<void> addUserToUnit(String uid, String unitId) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        unitId: Value(unitId),
        isApproved: const Value(true),
        approvalStatus: const Value('approved'),
        updatedAt: Value(now),
      ));

      // כתיבה ישירה ל-Firestore (עוקף את sync queue שמסיר isApproved)
      try {
        await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .set({
          'unitId': unitId,
          'isApproved': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        print('DEBUG: Direct Firestore failed for addUserToUnit, queueing: $e');
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
      }
      // Custom claims updated automatically by onUserWrite Cloud Function trigger
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
            tbl.approvalStatus.equals('pending')))
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
            tbl.approvalStatus.equals('pending')))
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
            tbl.approvalStatus.equals('approved')))
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
          approvalStatus: const Value(null),
          role: shouldResetRole
              ? const Value('navigator')
              : const Value.absent(),
          updatedAt: Value(now),
        ));

        // כתיבה ישירה ל-Firestore (עוקף את sync queue שמסיר role+isApproved+approvalStatus)
        final firestoreData = {
          'unitId': null,
          'isApproved': false,
          'approvalStatus': null,
          if (shouldResetRole) 'role': 'navigator',
          'updatedAt': FieldValue.serverTimestamp(),
        };
        try {
          await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .doc(user.uid)
              .update(firestoreData);
        } catch (e) {
          print('DEBUG: Direct Firestore failed for resetUser ${user.uid}, queueing: $e');
          await _syncManager.queueOperation(
            collection: AppConstants.usersCollection,
            documentId: user.uid,
            operation: 'update',
            data: {
              'unitId': null,
              'isApproved': false,
              'approvalStatus': null,
              if (shouldResetRole) 'role': 'navigator',
              'updatedAt': now.toIso8601String(),
            },
            priority: SyncPriority.high,
          );
        }
        // Custom claims updated automatically by onUserWrite Cloud Function trigger

        // הסרת המשתמש מניווטים של יחידות אחרות
        await NavigationRepository().removeParticipantFromAll(user.uid);
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
        approvalStatus: const Value(null),
        role: shouldResetRole
            ? const Value('navigator')
            : const Value.absent(),
        updatedAt: Value(now),
      ));

      // כתיבה ישירה ל-Firestore (למניעת מרוץ עם listener שמחזיר נתונים ישנים)
      final firestoreData = {
        'unitId': null,
        'isApproved': false,
        'approvalStatus': null,
        if (shouldResetRole) 'role': 'navigator',
        'updatedAt': now.toIso8601String(),
      };
      try {
        await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .update(firestoreData);
        print('DEBUG: Direct Firestore update for user $uid (removeFromUnit)');
      } catch (e) {
        // Firestore לא זמין — fallback לסנכרון רגיל
        print('DEBUG: Direct Firestore failed, queueing: $e');
        await _syncManager.queueOperation(
          collection: AppConstants.usersCollection,
          documentId: uid,
          operation: 'update',
          data: firestoreData,
          priority: SyncPriority.high,
        );
      }

      // Custom claims updated automatically by onUserWrite Cloud Function trigger

      // Cascade: הסרת המשתמש מכל הניווטים שהוא משתתף בהם
      final navigationRepo = NavigationRepository();
      await navigationRepo.removeParticipantFromAll(uid);

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
            tbl.approvalStatus.equals('approved') &
            tbl.role.isIn(['commander', 'unit_admin', 'admin', 'developer'])))
          .get();
      return results.map((r) => _userFromRow(r)).toList();
    } catch (e) {
      print('DEBUG: Error in getCommandersForUnit: $e');
      return [];
    }
  }

  /// משתמש שנדחה מבקש שוב — approvalStatus חוזר ל-"pending"
  Future<void> requestAgain(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        approvalStatus: const Value('pending'),
        updatedAt: Value(now),
      ));

      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'isApproved': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('DEBUG: Error in requestAgain: $e');
    }
  }

  /// משתמש שנדחה בוחר יחידה אחרת — מאפס unitId ו-approvalStatus
  Future<void> cancelAndChooseNewUnit(String uid) async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final now = DateTime.now();
      await (db.update(db.users)..where((tbl) => tbl.uid.equals(uid)))
          .write(UsersCompanion(
        unitId: const Value(null),
        isApproved: const Value(false),
        approvalStatus: const Value(null),
        updatedAt: Value(now),
      ));

      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'unitId': FieldValue.delete(),
        'isApproved': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('DEBUG: Error in cancelAndChooseNewUnit: $e');
    }
  }

  /// קבלת משתמשים "אבודים" — לא מאושרים, לא ממתינים, ולא מדלגים על onboarding
  /// כולל: ללא יחידה, יחידה לא קיימת, נדחו, או ללא סטטוס
  Future<List<domain.User>> getLostUsers() async {
    final db = _localDatabase ?? AppDatabase();
    try {
      final allUsers = await db.select(db.users).get();
      final lost = <domain.User>[];
      for (final row in allUsers) {
        final user = _userFromRow(row);
        // דילוג על admin/developer — מדלגים על onboarding
        if (user.bypassesOnboarding) continue;
        // דילוג על מאושרים
        if (user.isApproved) continue;
        // דילוג על ממתינים (pending)
        if (user.isPending) continue;
        // מה שנשאר = "אבוד"
        lost.add(user);
      }
      return lost;
    } catch (e) {
      print('DEBUG: Error in getLostUsers: $e');
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
            tbl.approvalStatus.equals('approved') &
            tbl.role.equals('navigator')))
          .get();
      return results.map((r) => _userFromRow(r)).toList();
    } catch (e) {
      print('DEBUG: Error in getNavigatorsForUnit: $e');
      return [];
    }
  }
}
