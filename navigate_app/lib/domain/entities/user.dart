import 'package:equatable/equatable.dart';

/// ישות משתמש
/// uid = מספר אישי (7 ספרות) — הוא ה-ID של המשתמש
class User extends Equatable {
  final String uid; // מספר אישי = ה-ID
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final bool phoneVerified;
  final String email;
  final bool emailVerified;
  final String role; // 'admin', 'commander', 'navigator', 'unit_admin', 'developer'
  final String? unitId; // יחידה שהמשתמש שייך אליה
  final String? fcmToken; // FCM push notification token
  final String? firebaseUid; // Firebase Auth UID (for auth_mapping)
  final bool isApproved; // האם המשתמש מאושר ביחידה
  final DateTime? soloQuizPassedAt; // מתי עבר מבחן בדד
  final int? soloQuizScore; // ציון מבחן בדד
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.uid,
    this.firstName = '',
    this.lastName = '',
    required this.phoneNumber,
    required this.phoneVerified,
    this.email = '',
    this.emailVerified = false,
    required this.role,
    this.unitId,
    this.fcmToken,
    this.firebaseUid,
    this.isApproved = false,
    this.soloQuizPassedAt,
    this.soloQuizScore,
    required this.createdAt,
    required this.updatedAt,
  });

  /// מספר אישי — תאימות לאחור (uid הוא המספר האישי)
  String get personalNumber => uid;

  /// שם מלא מחושב מ-firstName + lastName
  String get fullName {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty && last.isEmpty) {
      return '';
    }
    if (first.isEmpty) return last;
    if (last.isEmpty) return first;
    return '$first $last';
  }

  /// האם המשתמש הוא אדמין
  bool get isAdmin => role == 'admin';

  /// האם המשתמש הוא מפקד
  bool get isCommander => role == 'commander';

  /// האם המשתמש הוא מנווט
  bool get isNavigator => role == 'navigator';

  /// האם למשתמש יש הרשאות מפקד או גבוהות יותר
  bool get hasCommanderPermissions =>
      isAdmin || isCommander || isDeveloper || isUnitAdmin;

  /// האם המשתמש הוא מנהל מערכת יחידתי
  bool get isUnitAdmin => role == 'unit_admin';

  /// האם המשתמש הוא מפתח
  bool get isDeveloper => role == 'developer';

  /// האם המשתמש עבר onboarding מלא (יש יחידה + מאושר)
  bool get isOnboarded => unitId != null && unitId!.isNotEmpty && isApproved;

  /// האם ממתין לאישור מפקד
  bool get isAwaitingApproval => unitId != null && unitId!.isNotEmpty && !isApproved;

  /// האם צריך לבחור יחידה (אין unitId ואין הרשאות מפקד)
  bool get needsUnitSelection => (unitId == null || unitId!.isEmpty) && !hasCommanderPermissions;

  /// האם עוקף onboarding (admin/developer)
  bool get bypassesOnboarding => isAdmin || isDeveloper;

  /// האם מבחן בדד בתוקף (עבר ב-4 חודשים האחרונים)
  bool get hasSoloQuizValid {
    if (soloQuizPassedAt == null) return false;
    final fourMonthsAgo = DateTime.now().subtract(const Duration(days: 120));
    return soloQuizPassedAt!.isAfter(fourMonthsAgo);
  }

  /// העתקה עם שינויים
  User copyWith({
    String? uid,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    bool? phoneVerified,
    String? email,
    bool? emailVerified,
    String? role,
    String? unitId,
    bool clearUnitId = false,
    String? fcmToken,
    String? firebaseUid,
    bool clearFirebaseUid = false,
    bool? isApproved,
    DateTime? soloQuizPassedAt,
    bool clearSoloQuizPassedAt = false,
    int? soloQuizScore,
    bool clearSoloQuizScore = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      uid: uid ?? this.uid,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      role: role ?? this.role,
      unitId: clearUnitId ? null : (unitId ?? this.unitId),
      fcmToken: fcmToken ?? this.fcmToken,
      firebaseUid: clearFirebaseUid ? null : (firebaseUid ?? this.firebaseUid),
      isApproved: isApproved ?? this.isApproved,
      soloQuizPassedAt: clearSoloQuizPassedAt ? null : (soloQuizPassedAt ?? this.soloQuizPassedAt),
      soloQuizScore: clearSoloQuizScore ? null : (soloQuizScore ?? this.soloQuizScore),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// המרה ל-Map (Firestore)
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'firstName': firstName,
      'lastName': lastName,
      'personalNumber': uid, // תאימות לאחור
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'phoneVerified': phoneVerified,
      'email': email,
      'emailVerified': emailVerified,
      'role': role,
      if (unitId != null) 'unitId': unitId,
      if (fcmToken != null) 'fcmToken': fcmToken,
      if (firebaseUid != null) 'firebaseUid': firebaseUid,
      'isApproved': isApproved,
      if (soloQuizPassedAt != null) 'soloQuizPassedAt': soloQuizPassedAt!.toIso8601String(),
      if (soloQuizScore != null) 'soloQuizScore': soloQuizScore,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// יצירה מ-Map (Firestore) - תואם לאחור
  factory User.fromMap(Map<String, dynamic> map) {
    // תאימות לאחור: אם אין firstName/lastName, נפרק מ-fullName
    String firstName = map['firstName'] as String? ?? '';
    String lastName = map['lastName'] as String? ?? '';

    if (firstName.isEmpty && lastName.isEmpty) {
      final fullName = map['fullName'] as String? ?? '';
      final parts = fullName.trim().split(' ');
      if (parts.length >= 2) {
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      } else if (parts.length == 1) {
        firstName = parts.first;
      }
    }

    // תאימות לאחור: אם יש personalNumber ואין uid
    final uid = map['uid'] as String? ??
        map['personalNumber'] as String? ??
        '';

    final unitId = map['unitId'] as String?;

    return User(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      phoneNumber: map['phoneNumber'] as String? ?? '',
      phoneVerified: map['phoneVerified'] as bool? ?? false,
      email: map['email'] as String? ?? '',
      emailVerified: map['emailVerified'] as bool? ?? false,
      role: map['role'] as String? ?? 'navigator',
      unitId: unitId,
      fcmToken: map['fcmToken'] as String?,
      firebaseUid: map['firebaseUid'] as String?,
      isApproved: map['isApproved'] as bool? ??
          (unitId != null && unitId.isNotEmpty), // backward compat
      soloQuizPassedAt: map['soloQuizPassedAt'] != null
          ? DateTime.parse(map['soloQuizPassedAt'] as String)
          : null,
      soloQuizScore: map['soloQuizScore'] as int?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    uid,
    firstName,
    lastName,
    phoneNumber,
    phoneVerified,
    email,
    emailVerified,
    role,
    unitId,
    fcmToken,
    firebaseUid,
    isApproved,
    soloQuizPassedAt,
    soloQuizScore,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() {
    return 'User(uid: $uid, fullName: $fullName, role: $role)';
  }
}
