import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/user.dart' as app_user;
import '../data/repositories/user_repository.dart';
import '../data/sync/sync_manager.dart';
import 'session_service.dart';
import 'notification_service.dart';

/// שירות אימות — מבוסס מספר אישי + SMS / Email Link
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const _projectId = 'navigate-native';
  static const _region = 'us-central1';

  /// קריאה ל-Cloud Function — SDK רגיל במובייל, HTTP ישיר בדסקטופ
  Future<Map<String, dynamic>> _callCloudFunction(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    // במובייל — ניסיון SDK רגיל, עם fallback ל-HTTP אם נכשל (App Check / UNAUTHENTICATED)
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(functionName);
        final result = await callable.call(data);
        return Map<String, dynamic>.from(result.data as Map);
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'unauthenticated' || e.code == 'UNAUTHENTICATED') {
          print('DEBUG _callCloudFunction: callable failed ($e), falling back to HTTP');
          // fall through to HTTP path below
        } else {
          rethrow;
        }
      }
    }

    // בדסקטופ — HTTP ישיר (cloud_functions SDK לא נתמך ב-Windows)
    // שימוש ב-endpoints מסוג onRequest (http prefix) — פתוחים ללא IAM
    final httpName = 'http${functionName[0].toUpperCase()}${functionName.substring(1)}';
    final url = Uri.parse('https://$_region-$_projectId.cloudfunctions.net/$httpName');

    // קבלת token אימות
    String? idToken;
    final user = _auth.currentUser;
    if (user != null) {
      try {
        idToken = await user.getIdToken();
        // ניקוי תווים לא חוקיים שיכולים לשבור header parsing ב-Windows
        idToken = idToken?.trim().replaceAll(RegExp(r'[\r\n]'), '');
      } catch (e) {
        print('DEBUG _callCloudFunction: getIdToken failed: $e');
      }
    }

    // בניית HTTP request ידנית דרך SecureSocket — עוקף בעיית header validation ב-Windows
    final host = url.host;
    final path = url.path;
    final bodyStr = jsonEncode({'data': data});
    final bodyBytes = utf8.encode(bodyStr);

    final socket = await SecureSocket.connect(host, 443);
    try {
      final sb = StringBuffer();
      sb.write('POST $path HTTP/1.1\r\n');
      sb.write('Host: $host\r\n');
      sb.write('Content-Type: application/json\r\n');
      sb.write('Content-Length: ${bodyBytes.length}\r\n');
      if (idToken != null) {
        sb.write('Authorization: Bearer $idToken\r\n');
      }
      sb.write('Connection: close\r\n');
      sb.write('\r\n');

      socket.add(utf8.encode(sb.toString()));
      socket.add(bodyBytes);
      await socket.flush();

      // קריאת תגובה
      final responseBytes = <int>[];
      await for (final chunk in socket) {
        responseBytes.addAll(chunk);
      }
      final responseStr = utf8.decode(responseBytes);

      // פרסור HTTP response — חילוץ status code ו-body
      final headerEnd = responseStr.indexOf('\r\n\r\n');
      if (headerEnd == -1) {
        throw Exception('Invalid HTTP response from $functionName');
      }
      final headerPart = responseStr.substring(0, headerEnd);
      var responseBody = responseStr.substring(headerEnd + 4);

      // פרסור status line
      final statusLine = headerPart.split('\r\n').first;
      final statusMatch = RegExp(r'HTTP/\d\.\d (\d+)').firstMatch(statusLine);
      final statusCode = statusMatch != null ? int.parse(statusMatch.group(1)!) : 0;

      // טיפול ב-chunked transfer encoding
      if (headerPart.toLowerCase().contains('transfer-encoding: chunked')) {
        responseBody = _decodeChunked(responseBody);
      }

      print('DEBUG _callCloudFunction $functionName: status=$statusCode');

      if (statusCode != 200) {
        try {
          final errorJson = jsonDecode(responseBody);
          final errorMsg = errorJson['error']?['message'] ??
              errorJson['error']?['status'] ??
              responseBody;
          throw Exception(errorMsg);
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('Cloud Function error ($functionName): $statusCode $responseBody');
        }
      }

      final responseData = jsonDecode(responseBody);
      if (responseData is Map && responseData.containsKey('result')) {
        return Map<String, dynamic>.from(responseData['result'] as Map);
      }
      return Map<String, dynamic>.from(responseData as Map);
    } finally {
      await socket.close();
    }
  }

  /// פענוח chunked transfer encoding
  String _decodeChunked(String body) {
    final result = StringBuffer();
    var remaining = body;
    while (remaining.isNotEmpty) {
      final lineEnd = remaining.indexOf('\r\n');
      if (lineEnd == -1) break;
      final sizeStr = remaining.substring(0, lineEnd).trim();
      if (sizeStr.isEmpty) break;
      final size = int.tryParse(sizeStr, radix: 16) ?? 0;
      if (size == 0) break;
      final chunkStart = lineEnd + 2;
      final chunkEnd = chunkStart + size;
      if (chunkEnd > remaining.length) {
        result.write(remaining.substring(chunkStart));
        break;
      }
      result.write(remaining.substring(chunkStart, chunkEnd));
      remaining = remaining.substring(chunkEnd + 2); // skip \r\n after chunk
    }
    return result.toString();
  }

  // ─── אכיפת מכשיר יחיד ───
  static const _sessionIdKey = 'active_session_id';
  final StreamController<void> _forceLogoutController =
      StreamController<void>.broadcast();

  /// stream שנורה כשמזוהה התחברות ממכשיר אחר
  Stream<void> get onForceLogout => _forceLogoutController.stream;

  /// נקרא מ-SyncManager כשמזוהה activeSessionId שונה
  void notifyForceLogout() {
    if (!_forceLogoutController.isClosed) {
      _forceLogoutController.add(null);
    }
  }

  /// התנתקות כפויה — ניקוי מקומי בלבד (לא כותב ל-Firestore)
  Future<void> performForceLogout() async {
    // מחיקת commander_tokens לפני signOut
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('logged_in_uid');
    if (uid != null) {
      try {
        await _firestore.collection('commander_tokens').doc(uid).delete();
      } catch (_) {}
    }

    await NotificationService().clearToken();
    await SessionService().clearSession();
    await prefs.remove('logged_in_uid');
    await prefs.remove('pending_email_link');
    await prefs.remove(_sessionIdKey);
    await _auth.signOut();
  }

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
  /// שומר על שדות קיימים (unitId, firebaseUid וכו') ומוודא role=developer
  /// תיקון Firestore מבוצע ב-Cloud Function (initSession) — שם יש admin SDK
  Future<void> ensureDeveloperUser() async {
    final userRepo = UserRepository();
    const devUid = '6868383';
    final existing = await userRepo.getUser(devUid);

    final now = DateTime.now();
    if (existing != null && existing.role == 'developer') {
      return;
    }

    final devUser = existing != null
        ? existing.copyWith(role: 'developer', updatedAt: now)
        : app_user.User(
            uid: devUid,
            firstName: 'משה',
            lastName: 'אליצור',
            phoneNumber: '0556625578',
            phoneVerified: false,
            email: 'moshe@elitzur.net',
            emailVerified: false,
            role: 'developer',
            createdAt: now,
            updatedAt: now,
          );
    await userRepo.saveUserLocally(devUser);
  }

  // ─── כניסה ───

  /// כניסה לפי מספר אישי — חיפוש מקומי, אם לא נמצא → Firestore fallback
  /// מחזיר User אם נמצא (עדיין לא שומר session — צריך אימות קודם)
  Future<app_user.User?> loginByPersonalNumber(String personalNumber) async {
    final userRepo = UserRepository();

    // 1. חיפוש מקומי
    final localUser = await userRepo.getUserByPersonalNumber(personalNumber);
    if (localUser != null) return localUser;

    // 2. Firestore fallback — צריך אימות Firebase לגישה
    if (_auth.currentUser == null) {
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        print('DEBUG loginByPersonalNumber: anonymous sign-in failed: $e');
      }
    }

    // 3. חיפוש לפי doc ID (get — לא צריך auth_mapping)
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

    // עדכון firebaseUid + custom claims
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      final userRepo = UserRepository();
      final user = await userRepo.getUser(personalNumber);
      if (user != null) {
        // שמירת firebaseUid אם חסר
        if (user.firebaseUid != firebaseUser.uid) {
          final updatedUser = user.copyWith(
            firebaseUid: firebaseUser.uid,
            updatedAt: DateTime.now(),
          );
          await userRepo.saveUserLocally(updatedUser);
        }
      }

      // קריאה ל-Cloud Function לקביעת custom claims + כתיבת activeSessionId
      // CF blocks until claims verified server-side — no race condition
      String sessionId = '${personalNumber}_${DateTime.now().millisecondsSinceEpoch}';
      try {
        final result = await initSessionClaims(personalNumber);
        if (result['sessionId'] != null) {
          sessionId = result['sessionId'] as String;
        }
      } catch (e) {
        print('DEBUG: initSession call failed: $e');
        // fallback: ניסיון כתיבה ישירה (עלול להיכשל אם אין claims)
        try {
          await _firestore.collection('users').doc(personalNumber).update({
            'activeSessionId': sessionId,
          });
        } catch (e2) {
          print('DEBUG: Failed to write activeSessionId directly: $e2');
        }
      }

      await prefs.setString(_sessionIdKey, sessionId);

      // Windows workaround: Firestore C++ SDK may not pick up refreshed auth token.
      // Cycling the network forces a fresh gRPC connection with updated claims.
      try {
        await _firestore.disableNetwork();
        await Future.delayed(const Duration(milliseconds: 500));
        await _firestore.enableNetwork();
        print('DEBUG completeLogin: Firestore network cycled for token refresh');
      } catch (_) {}
    } else {
      // אין Firebase user — שמירת session ID מקומי בלבד
      final sessionId = '${personalNumber}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_sessionIdKey, sessionId);
    }

    // דחיפת נתוני משתמש מלאים ל-Firestore (אם יש unitId)
    // מטפל במקרה שבו setUserUnit נכשל בעבר (permission-denied לפני initSession)
    final userRepo = UserRepository();
    final currentUser = await userRepo.getUser(personalNumber);
    if (currentUser != null && currentUser.unitId != null) {
      try {
        final firestoreData = currentUser.toMap();
        firestoreData.remove('role');
        firestoreData.remove('isApproved');
        firestoreData['updatedAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('users').doc(personalNumber)
            .set(firestoreData, SetOptions(merge: true));
        print('DEBUG: Pushed full user data to Firestore for $personalNumber');
      } catch (e) {
        print('DEBUG: Failed to push user data to Firestore: $e');
      }
    }

    // רענון SyncManager — claims מעודכנים עכשיו, re-pull נדרש אם ה-pull הראשוני נכשל
    try {
      final syncManager = SyncManager();
      await syncManager.refreshUserContext();
    } catch (_) {}

    // עדכון phone_lookup (הגירה עצלנית — כל כניסה מעדכנת)
    if (currentUser != null && currentUser.phoneNumber.isNotEmpty) {
      await _writePhoneLookup(currentUser.phoneNumber, personalNumber);
    }

    // עדכון email_lookup (הגירה עצלנית — כל כניסה מעדכנת)
    if (currentUser != null && currentUser.email.isNotEmpty) {
      await _writeEmailLookup(currentUser.email, personalNumber);
    }

    // רישום FCM token
    await NotificationService().setUserId(personalNumber);
  }

  /// כתיבת phone_lookup — מיפוי טלפון → מספר אישי (בשני פורמטים)
  Future<void> _writePhoneLookup(String phoneNumber, String personalNumber) async {
    try {
      final normalized = phoneNumber.replaceAll(RegExp(r'[\s\-]'), '');
      final data = {
        'uid': personalNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // כתיבה בפורמט המקורי
      await _firestore.collection('phone_lookup').doc(normalized).set(data);

      // כתיבה גם בפורמט אלטרנטיבי (05↔+972)
      if (normalized.startsWith('05') && normalized.length == 10) {
        final intl = '+972${normalized.substring(1)}';
        await _firestore.collection('phone_lookup').doc(intl).set(data);
      } else if (normalized.startsWith('+9725')) {
        final local = '0${normalized.substring(4)}';
        await _firestore.collection('phone_lookup').doc(local).set(data);
      }
    } catch (e) {
      print('DEBUG: phone_lookup write failed: $e');
    }
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

    // כתיבת phone_lookup (להרשמות הבאות)
    if (phoneNumber.isNotEmpty) {
      await _writePhoneLookup(phoneNumber, personalNumber);
    }

    // כתיבת email_lookup (להרשמות הבאות)
    if (email.isNotEmpty) {
      await _writeEmailLookup(email, personalNumber);
    }

    // שמירת session
    await completeLogin(personalNumber);

    // הכתיבה ל-Firestore מתבצעת אוטומטית דרך תור הסנכרון
    // (saveUserLocally מוסיף לתור עם priority: high)

    return user;
  }

  /// המרת מספר טלפון מקומי לפורמט בינלאומי
  /// 05XXXXXXXX → +9725XXXXXXXX
  String formatPhoneForFirebase(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-]'), '');
    if (cleaned.startsWith('05') && cleaned.length == 10) {
      return '+972${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('+')) return cleaned;
    return '+972$cleaned';
  }

  /// כניסה לפי מספר טלפון — חיפוש מקומי, אם לא נמצא → phone_lookup + user doc
  Future<app_user.User?> loginByPhoneNumber(String phoneNumber) async {
    final userRepo = UserRepository();

    // נרמול — הסרת רווחים ומקפים
    final normalizedPhone = phoneNumber.replaceAll(RegExp(r'[\s\-]'), '');

    // חישוב פורמט אלטרנטיבי (05↔+972)
    String? altPhone;
    if (normalizedPhone.startsWith('05') && normalizedPhone.length == 10) {
      altPhone = '+972${normalizedPhone.substring(1)}';
    } else if (normalizedPhone.startsWith('+9725')) {
      altPhone = '0${normalizedPhone.substring(4)}';
    }

    // 1. חיפוש מקומי (getUserByPhoneNumber כבר מחפש בשני הפורמטים)
    final localUser = await userRepo.getUserByPhoneNumber(normalizedPhone);
    if (localUser != null) return localUser;

    // 2. Firestore fallback — צריך אימות Firebase לגישה
    if (_auth.currentUser == null) {
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        print('DEBUG loginByPhoneNumber: anonymous sign-in failed: $e');
      }
    }

    try {
      // 3. חיפוש ב-phone_lookup (get — לא צריך auth_mapping)
      String? personalNumber;

      final lookupDoc = await _firestore
          .collection('phone_lookup')
          .doc(normalizedPhone)
          .get()
          .timeout(const Duration(seconds: 5));

      if (lookupDoc.exists && lookupDoc.data() != null) {
        personalNumber = lookupDoc.data()!['uid'] as String?;
      }

      // ניסיון בפורמט אלטרנטיבי
      if (personalNumber == null && altPhone != null) {
        final altDoc = await _firestore
            .collection('phone_lookup')
            .doc(altPhone)
            .get()
            .timeout(const Duration(seconds: 5));

        if (altDoc.exists && altDoc.data() != null) {
          personalNumber = altDoc.data()!['uid'] as String?;
        }
      }

      if (personalNumber == null) return null;

      // 4. קריאת user doc לפי personalNumber (get — לא צריך auth_mapping)
      final userDoc = await _firestore
          .collection('users')
          .doc(personalNumber)
          .get()
          .timeout(const Duration(seconds: 5));

      if (userDoc.exists && userDoc.data() != null) {
        final data = _sanitizeFirestoreData(userDoc.data()!);
        data['uid'] = userDoc.id;
        final user = app_user.User.fromMap(data);
        await userRepo.saveUserLocally(user, queueSync: false);
        return user;
      }
    } catch (e) {
      print('DEBUG: Firestore phone lookup failed: $e');
    }

    return null;
  }

  // ─── כניסה לפי מייל (דסקטופ) ───

  /// כניסה לפי כתובת מייל — חיפוש מקומי, אם לא נמצא → email_lookup + user doc
  Future<app_user.User?> loginByEmail(String email) async {
    final userRepo = UserRepository();
    final normalizedEmail = email.trim().toLowerCase();

    // 1. חיפוש מקומי
    final localUser = await userRepo.getUserByEmail(normalizedEmail);
    if (localUser != null) return localUser;

    // 2. Firestore fallback — צריך אימות Firebase לגישה
    if (_auth.currentUser == null) {
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        print('DEBUG loginByEmail: anonymous sign-in failed: $e');
      }
    }

    try {
      // 3. חיפוש ב-email_lookup
      final lookupDoc = await _firestore
          .collection('email_lookup')
          .doc(normalizedEmail)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!lookupDoc.exists || lookupDoc.data() == null) return null;
      final personalNumber = lookupDoc.data()!['uid'] as String?;
      if (personalNumber == null) return null;

      // 4. קריאת user doc
      final userDoc = await _firestore
          .collection('users')
          .doc(personalNumber)
          .get()
          .timeout(const Duration(seconds: 5));

      if (userDoc.exists && userDoc.data() != null) {
        final data = _sanitizeFirestoreData(userDoc.data()!);
        data['uid'] = userDoc.id;
        final user = app_user.User.fromMap(data);
        await userRepo.saveUserLocally(user, queueSync: false);
        return user;
      }
    } catch (e) {
      print('DEBUG: Firestore email lookup failed: $e');
    }

    return null;
  }

  /// Mutex: prevent duplicate concurrent initSession calls
  Future<Map<String, dynamic>>? _initSessionInFlight;

  /// קריאה ל-initSession Cloud Function — קובעת custom claims + מרעננת token
  /// נקראת מ-main.dart _ensureFirebaseAuth ומ-completeLogin
  /// CF blocks until claims verified server-side — no client guessing
  Future<Map<String, dynamic>> initSessionClaims(String personalNumber) {
    if (_initSessionInFlight != null) return _initSessionInFlight!;
    _initSessionInFlight = _doInitSessionClaims(personalNumber)
        .whenComplete(() => _initSessionInFlight = null);
    return _initSessionInFlight!;
  }

  Future<Map<String, dynamic>> _doInitSessionClaims(String personalNumber) async {
    final user = _auth.currentUser;
    if (user == null) return {};

    // CF blocks until claims verified server-side — single refresh suffices
    final result = await _callCloudFunction('initSession', {'personalNumber': personalNumber});
    await user.getIdToken(true);

    // Verify claims actually contain the expected appUid.
    // Safety net for propagation delays (Windows platform-channel threading,
    // network latency, or CF deployment lag).
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final token = await user.getIdToken(false);
        if (token != null) {
          final parts = token.split('.');
          if (parts.length == 3) {
            final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
            final claims = jsonDecode(payload) as Map<String, dynamic>;
            print('DEBUG initSessionClaims: attempt=$attempt, role=${claims['role']}, appUid=${claims['appUid']}, unitId=${claims['unitId']}');
            if (claims['appUid'] == personalNumber) {
              return result; // Claims verified
            }
          }
        }
      } catch (e) {
        print('DEBUG initSessionClaims: JWT decode failed (attempt $attempt): $e');
      }
      // Claims not set yet — wait and force-refresh
      await Future.delayed(const Duration(milliseconds: 500));
      await user.getIdToken(true);
    }

    print('WARNING initSessionClaims: claims verification failed after 3 attempts for $personalNumber');
    return result;
  }

  // ─── אימות Email OTP (דסקטופ) ───

  /// שליחת קוד אימות למייל דרך Cloud Function
  /// מחזיר את הקוד אם השרת לא הצליח לשלוח מייל (fallback), אחרת null
  Future<String?> sendEmailVerificationCode({
    required String email,
    required String personalNumber,
    required String purpose,
  }) async {
    // ודא אימות אנונימי (לגישת Cloud Functions)
    if (_auth.currentUser == null) {
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        print('DEBUG sendEmailVerificationCode: anonymous sign-in failed: $e');
      }
    }

    final result = await _callCloudFunction('sendEmailCode', {
      'email': email.trim().toLowerCase(),
      'personalNumber': personalNumber,
      'purpose': purpose,
    });

    // אם SMTP לא מוגדר — השרת מחזיר את הקוד בתגובה
    if (result.containsKey('code')) {
      return result['code']?.toString();
    }
    return null;
  }

  /// אימות קוד מייל דרך Cloud Function
  Future<bool> verifyEmailCode({
    required String personalNumber,
    required String code,
  }) async {
    final result = await _callCloudFunction('verifyEmailCode', {
      'personalNumber': personalNumber,
      'code': code,
    });
    return result['success'] == true;
  }

  /// כתיבת email_lookup — מיפוי מייל → מספר אישי
  Future<void> _writeEmailLookup(String email, String personalNumber) async {
    if (email.isEmpty) return;
    try {
      final normalizedEmail = email.trim().toLowerCase();
      await _firestore.collection('email_lookup').doc(normalizedEmail).set({
        'uid': personalNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('DEBUG: email_lookup write failed: $e');
    }
  }

  // ─── אימות SMS (מובייל) ───

  /// האם הפלטפורמה תומכת ב-SMS verification
  bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  /// אימות מספר טלפון - שליחת קוד SMS
  /// בדסקטופ (Windows/macOS/Linux) — מדלג על SMS ומפעיל onAutoVerified ישירות
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onVerificationFailed,
    Function(firebase_auth.PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    // Desktop — Firebase Phone Auth לא נתמך, מדלגים על SMS
    if (!isMobilePlatform) {
      print('DEBUG: Desktop platform — skipping SMS verification');
      onCodeSent('desktop-bypass');
      return;
    }

    // Re-apply debug settings — anonymous sign-in may reset them
    if (kDebugMode) {
      await firebase_auth.FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: true,
      );
      print('DEBUG verifyPhoneNumber: appVerificationDisabledForTesting=true');
    }

    // Play Integrity first, reCAPTCHA fallback on failure
    void doVerify({bool forceRecaptcha = false}) async {
      if (forceRecaptcha) {
        await firebase_auth.FirebaseAuth.instance.setSettings(
          forceRecaptchaFlow: true,
        );
        print('DEBUG verifyPhoneNumber: Retrying with forceRecaptchaFlow=true');
      }

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
          if (!forceRecaptcha &&
              (e.message ?? '').contains('missing a valid app identifier')) {
            print('DEBUG verifyPhoneNumber: Play Integrity failed, falling back to reCAPTCHA');
            doVerify(forceRecaptcha: true);
          } else {
            onVerificationFailed(e.message ?? 'אימות מספר טלפון נכשל');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
        timeout: const Duration(seconds: 120),
      );
    }

    doVerify();
  }

  /// כניסה עם קוד SMS
  /// בדסקטופ עם bypass — מדלג על signInWithCredential
  Future<firebase_auth.UserCredential> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    // Desktop bypass — אין צורך ב-signInWithCredential
    if (verificationId == 'desktop-bypass') {
      // ודא שיש אימות אנונימי (לגישת Firestore)
      if (_auth.currentUser == null) {
        return await _auth.signInAnonymously();
      }
      // מחזיר UserCredential ריק — ב-desktop לא צריך credential אמיתי
      // נשתמש ב-signInAnonymously כ-fallback
      return await _auth.signInAnonymously();
    }

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
    // ניקוי activeSessionId + commander_tokens ב-Firestore (לפני Firebase signOut!)
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('logged_in_uid');
    if (uid != null) {
      try {
        await _firestore.collection('users').doc(uid).update({
          'activeSessionId': FieldValue.delete(),
        });
      } catch (e) {
        print('DEBUG: Failed to clear activeSessionId: $e');
      }
      try {
        await _firestore.collection('commander_tokens').doc(uid).delete();
      } catch (e) {
        print('DEBUG: Failed to delete commander_tokens: $e');
      }
    }

    await NotificationService().clearToken();
    await SessionService().clearSession();
    await prefs.remove('logged_in_uid');
    await prefs.remove('pending_email_link');
    await prefs.remove(_sessionIdKey);
    await _auth.signOut();
  }
}
