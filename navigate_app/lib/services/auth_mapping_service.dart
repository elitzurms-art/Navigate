import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import '../domain/entities/user.dart';
import '../data/repositories/unit_repository.dart';

/// שירות ניהול auth_mapping — מיפוי Firebase Auth UID → נתוני משתמש באפליקציה
///
/// משמש עבור Firestore Security Rules: הכללים יכולים לקרוא את auth_mapping
/// לפי request.auth.uid ולבדוק role, unitId, allowedUnitScopeIds
class AuthMappingService {
  static final AuthMappingService _instance = AuthMappingService._internal();
  factory AuthMappingService() => _instance;
  AuthMappingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// עדכון auth_mapping doc עבור משתמש ספציפי
  /// נקרא על ידי: completeLogin, approveUser, updateUserRole, setUserUnit וכו'
  Future<void> updateAuthMapping(String firebaseUid, User user) async {
    try {
      final unitRepo = UnitRepository();
      final descendantIds = user.unitId != null
          ? await unitRepo.getDescendantIds(user.unitId!)
          : <String>[];
      final scopeIds = user.unitId != null
          ? [user.unitId!, ...descendantIds]
          : <String>[];

      await _firestore.collection('auth_mapping').doc(firebaseUid).set({
        'appUid': user.uid,
        'role': user.role,
        'unitId': user.unitId,
        'allowedUnitScopeIds': scopeIds,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('AuthMappingService: Updated auth_mapping for Firebase UID $firebaseUid (appUid=${user.uid}, role=${user.role})');
    } catch (e) {
      print('AuthMappingService: Error updating auth_mapping: $e');
    }
  }

  /// עדכון auth_mapping עבור המשתמש הנוכחי (Firebase Auth)
  Future<void> updateCurrentUserMapping(User user) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return;
    await updateAuthMapping(firebaseUser.uid, user);
  }

  /// עדכון auth_mapping עבור משתמש אחר (לפי firebaseUid שלו)
  /// נקרא כשמפקד משנה role/unit של משתמש אחר
  Future<void> updateMappingForUser(User user) async {
    if (user.firebaseUid == null) return;
    await updateAuthMapping(user.firebaseUid!, user);
  }
}
