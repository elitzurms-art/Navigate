import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/user.dart' as app_user;
import '../data/repositories/user_repository.dart';
import 'session_service.dart';
import 'notification_service.dart';

/// שירות אימות — מבוסס מספר אישי + SMS / Email Link
class AuthService {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// זיהוי פלטפורמת דסקטופ
  bool get isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// מאזין למשתמש מחובר
  Stream<app_user.User?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) {
        return null;
      }
      return await getUserData(firebaseUser.uid);
    });
  }

  /// משתמש מחובר נוכחי ב-Firebase
  firebase_auth.User? get currentFirebaseUser => _auth.currentUser;

  /// קבלת משתמש נוכחי — מ-SharedPreferences + DB מקומי
  Future<app_user.User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedInUid = prefs.getString('logged_in_uid');
    if (loggedInUid != null && loggedInUid.isNotEmpty) {
      final userRepo = UserRepository();
      // חיפוש לפי uid (פורמט חדש)
      final user = await userRepo.getUser(loggedInUid);
      if (user != null) return user;
      // fallback — חיפוש לפי personalNumber (רשומות ישנות)
      final userByPn = await userRepo.getUserByPersonalNumber(loggedInUid);
      if (userByPn != null) return userByPn;
    }

    // בדיקת Firebase auth
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      return await getUserData(firebaseUser.uid);
    }

    return null;
  }

  /// יצירת/עדכון משתמש מפתח
  Future<void> ensureDeveloperUser() async {
    final userRepo = UserRepository();
    const devUid = '6868383';
    final existing = await userRepo.getUser(devUid);

    final now = DateTime.now();
    final devUser = app_user.User(
      uid: devUid,
      firstName: 'משה',
      lastName: 'אליצור',
      phoneNumber: '0556625578',
      phoneVerified: false,
      email: 'moshe@elitzur.net',
      emailVerified: false,
      role: 'developer',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await userRepo.saveUserLocally(devUser);
  }

  /// יצירת משתמשי ניסוי אם לא קיימים
  Future<void> ensureTestUsers() async {
    final userRepo = UserRepository();
    final now = DateTime.now();

    final testUsers = [
      app_user.User(
        uid: '1111111',
        firstName: 'יוסי',
        lastName: 'כהן',
        phoneNumber: '0501111111',
        phoneVerified: true,
        email: 'yossi.cohen@test.com',
        emailVerified: true,
        role: 'navigator',
        createdAt: now,
        updatedAt: now,
      ),
      app_user.User(
        uid: '2222222',
        firstName: 'דנה',
        lastName: 'לוי',
        phoneNumber: '0502222222',
        phoneVerified: true,
        email: 'dana.levi@test.com',
        emailVerified: true,
        role: 'commander',
        createdAt: now,
        updatedAt: now,
      ),
      app_user.User(
        uid: '3333333',
        firstName: 'אורי',
        lastName: 'מזרחי',
        phoneNumber: '0503333333',
        phoneVerified: true,
        email: 'ori.mizrachi@test.com',
        emailVerified: true,
        role: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
      app_user.User(
        uid: '4444444',
        firstName: 'רחל',
        lastName: 'אברהם',
        phoneNumber: '0504444444',
        phoneVerified: true,
        email: 'rachel.avraham@test.com',
        emailVerified: true,
        role: 'unit_admin',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (final user in testUsers) {
      final existing = await userRepo.getUser(user.uid);
      await userRepo.saveUserLocally(
        existing != null ? user.copyWith(createdAt: existing.createdAt) : user,
      );
    }
  }

  // ─── כניסה ───

  /// כניסה לפי מספר אישי — חיפוש מקומי, אם לא נמצא → Firestore fallback
  /// מחזיר User אם נמצא (עדיין לא שומר session — צריך אימות קודם)
  Future<app_user.User?> loginByPersonalNumber(String personalNumber) async {
    final userRepo = UserRepository();

    // 1. חיפוש מקומי
    final localUser = await userRepo.getUserByPersonalNumber(personalNumber);
    if (localUser != null) return localUser;

    // 2. Firestore fallback — חיפוש לפי doc ID
    try {
      final doc = await _firestore
          .collection('users')
          .doc(personalNumber)
          .get()
          .timeout(const Duration(seconds: 5));

      if (doc.exists && doc.data() != null) {
        final data = _sanitizeFirestoreData(doc.data()!);
        data['uid'] = doc.id;
        final user = app_user.User.fromMap(data);
        await userRepo.saveUserLocally(user, queueSync: false);
        return user;
      }

      // 3. fallback — חיפוש לפי שדה personalNumber (רשומות ישנות)
      final query = await _firestore
          .collection('users')
          .where('personalNumber', isEqualTo: personalNumber)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      if (query.docs.isNotEmpty) {
        final data = _sanitizeFirestoreData(query.docs.first.data());
        data['uid'] = query.docs.first.id;
        final user = app_user.User.fromMap(data);
        await userRepo.saveUserLocally(user, queueSync: false);
        return user;
      }
    } catch (e) {
      // timeout או שגיאת רשת — המשתמש ינסה שוב כשיש רשת
      print('DEBUG: Firestore user lookup failed: $e');
    }

    return null;
  }

  /// המרת אובייקטי Firestore Timestamp ל-ISO strings
  Map<String, dynamic> _sanitizeFirestoreData(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      } else if (value is Map<String, dynamic>) {
        return MapEntry(key, _sanitizeFirestoreData(value));
      }
      return MapEntry(key, value);
    });
  }

  /// השלמת כניסה — שמירת session ב-SharedPreferences + אימות Firebase
  Future<void> completeLogin(String personalNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('logged_in_uid', personalNumber);

    // אם אין משתמש מאומת ב-Firebase Auth — כניסה אנונימית
    // כדי לאפשר גישה ל-Firestore (הכללים דורשים isAuthenticated)
    if (_auth.currentUser == null) {
      try {
        await _auth.signInAnonymously();
        print('DEBUG: Signed in anonymously for Firestore access');
      } catch (e) {
        print('DEBUG: Anonymous sign-in failed: $e');
      }
    }

    // רישום FCM token
    await NotificationService().setUserId(personalNumber);
  }

  // ─── הרשמה ───

  /// בדיקה אם מספר אישי כבר רשום (מקומי + Firestore עם timeout)
  Future<bool> isPersonalNumberRegistered(String personalNumber) async {
    // בדיקה מקומית
    final userRepo = UserRepository();
    final localUser = await userRepo.getUserByPersonalNumber(personalNumber);
    if (localUser != null) return true;

    // בדיקה ב-Firestore עם timeout — אם אין חיבור, ממשיכים
    try {
      final doc = await _firestore
          .collection('users')
          .doc(personalNumber)
          .get()
          .timeout(const Duration(seconds: 5));
      if (doc.exists) return true;

      // fallback — חיפוש לפי שדה personalNumber
      final query = await _firestore
          .collection('users')
          .where('personalNumber', isEqualTo: personalNumber)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      return query.docs.isNotEmpty;
    } catch (e) {
      // timeout או שגיאת רשת — מניחים שלא רשום (הבדיקה המקומית כבר עברה)
      return false;
    }
  }

  /// רישום משתמש חדש — offline-first
  /// UID = personalNumber
  /// שומר מקומית קודם, אז מנסה Firestore עם timeout
  Future<app_user.User> registerUser({
    required String personalNumber,
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
    bool phoneVerified = false,
    bool emailVerified = false,
  }) async {
    final now = DateTime.now();
    final user = app_user.User(
      uid: personalNumber,
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      phoneVerified: phoneVerified,
      email: email,
      emailVerified: emailVerified,
      role: 'navigator',
      createdAt: now,
      updatedAt: now,
    );

    // שמירה מקומית קודם (offline-first)
    final userRepo = UserRepository();
    await userRepo.saveUserLocally(user);

    // שמירת session
    await completeLogin(personalNumber);

    // הכתיבה ל-Firestore מתבצעת אוטומטית דרך תור הסנכרון
    // (saveUserLocally מוסיף לתור עם priority: high)

    return user;
  }

  // ─── אימות SMS (מובייל) ───

  /// אימות מספר טלפון - שליחת קוד SMS
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onVerificationFailed,
    Function(firebase_auth.PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted:
          (firebase_auth.PhoneAuthCredential credential) async {
        if (onAutoVerified != null) {
          onAutoVerified(credential);
        }
        try {
          await _auth.signInWithCredential(credential);
        } catch (e) {
          print('DEBUG: Auto-verification sign-in error: $e');
        }
      },
      verificationFailed: (firebase_auth.FirebaseAuthException e) {
        onVerificationFailed(e.message ?? 'אימות מספר טלפון נכשל');
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
      timeout: const Duration(seconds: 120),
    );
  }

  /// כניסה עם קוד SMS
  Future<firebase_auth.UserCredential> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = firebase_auth.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return await _auth.signInWithCredential(credential);
  }

  // ─── אימות Email Link (Windows) ───

  /// שליחת לינק אימות למייל
  Future<void> sendEmailSignInLink({
    required String email,
    required Function() onSuccess,
    required Function(String error) onFailed,
  }) async {
    try {
      final actionCodeSettings = firebase_auth.ActionCodeSettings(
        // URL שאליו יופנה המשתמש לאחר לחיצה על הלינק
        url: 'https://navigate-1b70d.firebaseapp.com/finishSignUp?email=${Uri.encodeComponent(email)}',
        handleCodeInApp: true,
        // הגדרות Android (לא רלוונטי לווינדוס, אבל נדרש)
        androidPackageName: 'com.navigate.navigate_app',
        androidInstallApp: false,
        // iOS (לא רלוונטי לווינדוס)
        iOSBundleId: 'com.navigate.navigateApp',
      );

      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );

      // שמירת המייל ב-SharedPreferences לאימות מאוחר יותר
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_email_link', email);

      onSuccess();
    } catch (e) {
      onFailed(e.toString());
    }
  }

  /// בדיקה אם לינק הוא email sign-in link תקין
  bool isValidEmailSignInLink(String link) {
    try {
      return _auth.isSignInWithEmailLink(link);
    } catch (e) {
      return false;
    }
  }

  /// כניסה עם Email Link (המשתמש מדביק את הלינק מהמייל)
  Future<firebase_auth.UserCredential?> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    try {
      if (_auth.isSignInWithEmailLink(emailLink)) {
        return await _auth.signInWithEmailLink(
          email: email,
          emailLink: emailLink,
        );
      }
      return null;
    } catch (e) {
      print('DEBUG: Email link sign-in error: $e');
      return null;
    }
  }

  // ─── שאילתות ───

  /// בדיקה אם משתמש קיים (לפי UID)
  Future<bool> isUserRegistered(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// קבלת נתוני משתמש מ-Firestore
  Future<app_user.User?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return app_user.User.fromMap(doc.data()!);
    } catch (e) {
      return null;
    }
  }

  /// עדכון הרשאת משתמש
  Future<void> updateUserRole(String uid, String role) async {
    await _firestore.collection('users').doc(uid).update({
      'role': role,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// יציאה
  Future<void> signOut() async {
    await NotificationService().clearToken();
    await SessionService().clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logged_in_uid');
    await prefs.remove('pending_email_link');
    await _auth.signOut();
  }
}
