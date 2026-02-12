import 'package:equatable/equatable.dart';

/// סוג חריגת אבטחה
enum ViolationType {
  /// יציאה מ-Lock Task Mode
  exitLockTask('exit_lock_task', 'יציאה מנעילה'),

  /// מעבר לרקע
  appBackgrounded('app_backgrounded', 'מעבר לרקע'),

  /// כיבוי מסך
  screenOff('screen_off', 'כיבוי מסך'),

  /// הדלקת מסך
  screenOn('screen_on', 'הדלקת מסך'),

  /// סגירה חריגה
  appClosed('app_closed', 'סגירה חריגה'),

  /// יציאה מ-Guided Access (iOS)
  exitGuidedAccess('exit_guided_access', 'יציאה מ-Guided Access'),

  /// GPS כבוי
  gpsDisabled('gps_disabled', 'GPS כבוי'),

  /// אינטרנט נותק
  internetDisconnected('internet_disconnected', 'אינטרנט נותק');

  final String code;
  final String displayName;

  const ViolationType(this.code, this.displayName);

  static ViolationType fromCode(String code) {
    return ViolationType.values.firstWhere(
      (type) => type.code == code,
      orElse: () => ViolationType.appClosed,
    );
  }
}

/// רמת חומרה
enum ViolationSeverity {
  low('low', 'נמוכה', 'ℹ️'),
  medium('medium', 'בינונית', '⚠️'),
  high('high', 'גבוהה', '🔴'),
  critical('critical', 'קריטית', '🚨');

  final String code;
  final String displayName;
  final String emoji;

  const ViolationSeverity(this.code, this.displayName, this.emoji);
}

/// רישום חריגת אבטחה
class SecurityViolation extends Equatable {
  final String id;
  final String navigationId;
  final String navigatorId;
  final ViolationType type;
  final ViolationSeverity severity;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata; // מיקום GPS, רמת סוללה וכו'

  const SecurityViolation({
    required this.id,
    required this.navigationId,
    required this.navigatorId,
    required this.type,
    required this.severity,
    required this.description,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'navigatorId': navigatorId,
      'type': type.code,
      'severity': severity.code,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory SecurityViolation.fromMap(Map<String, dynamic> map) {
    return SecurityViolation(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      navigatorId: map['navigatorId'] as String,
      type: ViolationType.fromCode(map['type'] as String),
      severity: ViolationSeverity.values.firstWhere(
        (s) => s.code == map['severity'],
        orElse: () => ViolationSeverity.medium,
      ),
      description: map['description'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  List<Object?> get props => [id, navigationId, navigatorId, type, severity, timestamp];
}

/// הגדרות אבטחה לניווט
class SecuritySettings extends Equatable {
  final bool lockTaskEnabled; // Android Lock Task
  final bool requireGuidedAccess; // iOS Guided Access
  final String? unlockCode; // קוד לביטול נעילה
  final bool alertOnBackground; // התראה על מעבר לרקע
  final bool alertOnScreenOff; // התראה על כיבוי מסך
  final int maxViolationsBeforeAlert; // מספר חריגות לפני התראה

  const SecuritySettings({
    this.lockTaskEnabled = true,
    this.requireGuidedAccess = true,
    this.unlockCode,
    this.alertOnBackground = true,
    this.alertOnScreenOff = false,
    this.maxViolationsBeforeAlert = 3,
  });

  Map<String, dynamic> toMap() {
    return {
      'lockTaskEnabled': lockTaskEnabled,
      'requireGuidedAccess': requireGuidedAccess,
      if (unlockCode != null) 'unlockCode': unlockCode,
      'alertOnBackground': alertOnBackground,
      'alertOnScreenOff': alertOnScreenOff,
      'maxViolationsBeforeAlert': maxViolationsBeforeAlert,
    };
  }

  factory SecuritySettings.fromMap(Map<String, dynamic> map) {
    return SecuritySettings(
      lockTaskEnabled: map['lockTaskEnabled'] as bool? ?? true,
      requireGuidedAccess: map['requireGuidedAccess'] as bool? ?? true,
      unlockCode: map['unlockCode'] as String?,
      alertOnBackground: map['alertOnBackground'] as bool? ?? true,
      alertOnScreenOff: map['alertOnScreenOff'] as bool? ?? false,
      maxViolationsBeforeAlert: map['maxViolationsBeforeAlert'] as int? ?? 3,
    );
  }

  SecuritySettings copyWith({
    bool? lockTaskEnabled,
    bool? requireGuidedAccess,
    String? unlockCode,
    bool? alertOnBackground,
    bool? alertOnScreenOff,
    int? maxViolationsBeforeAlert,
  }) {
    return SecuritySettings(
      lockTaskEnabled: lockTaskEnabled ?? this.lockTaskEnabled,
      requireGuidedAccess: requireGuidedAccess ?? this.requireGuidedAccess,
      unlockCode: unlockCode ?? this.unlockCode,
      alertOnBackground: alertOnBackground ?? this.alertOnBackground,
      alertOnScreenOff: alertOnScreenOff ?? this.alertOnScreenOff,
      maxViolationsBeforeAlert: maxViolationsBeforeAlert ?? this.maxViolationsBeforeAlert,
    );
  }

  @override
  List<Object?> get props => [
        lockTaskEnabled,
        requireGuidedAccess,
        unlockCode,
        alertOnBackground,
        alertOnScreenOff,
        maxViolationsBeforeAlert,
      ];
}
