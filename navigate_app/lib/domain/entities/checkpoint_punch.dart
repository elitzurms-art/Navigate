import 'package:equatable/equatable.dart';
import 'coordinate.dart';

/// סטטוס דקירה
enum PunchStatus {
  active('active', 'פעיל'),
  deleted('deleted', 'נמחק'),
  approved('approved', 'מאושר'),
  rejected('rejected', 'נדחה');

  final String code;
  final String displayName;

  const PunchStatus(this.code, this.displayName);

  static PunchStatus fromCode(String code) {
    return PunchStatus.values.firstWhere(
      (status) => status.code == code,
      orElse: () => PunchStatus.active,
    );
  }
}

/// דקירת נקודת ציון
class CheckpointPunch extends Equatable {
  final String id;
  final String navigationId;
  final String navigatorId;
  final String checkpointId;
  final Coordinate punchLocation; // מיקום בפועל של הדקירה
  final DateTime punchTime;
  final PunchStatus status;
  final double? distanceFromCheckpoint; // מרחק מהנקודה המקורית (מטרים)
  final String? rejectionReason; // סיבת דחייה (אם נדחה)
  final DateTime? approvalTime; // זמן אישור
  final String? approvedBy; // מי אישר

  const CheckpointPunch({
    required this.id,
    required this.navigationId,
    required this.navigatorId,
    required this.checkpointId,
    required this.punchLocation,
    required this.punchTime,
    this.status = PunchStatus.active,
    this.distanceFromCheckpoint,
    this.rejectionReason,
    this.approvalTime,
    this.approvedBy,
  });

  bool get isApproved => status == PunchStatus.approved;
  bool get isRejected => status == PunchStatus.rejected;
  bool get isDeleted => status == PunchStatus.deleted;
  bool get isPending => status == PunchStatus.active;

  CheckpointPunch copyWith({
    String? id,
    String? navigationId,
    String? navigatorId,
    String? checkpointId,
    Coordinate? punchLocation,
    DateTime? punchTime,
    PunchStatus? status,
    double? distanceFromCheckpoint,
    String? rejectionReason,
    DateTime? approvalTime,
    String? approvedBy,
  }) {
    return CheckpointPunch(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      navigatorId: navigatorId ?? this.navigatorId,
      checkpointId: checkpointId ?? this.checkpointId,
      punchLocation: punchLocation ?? this.punchLocation,
      punchTime: punchTime ?? this.punchTime,
      status: status ?? this.status,
      distanceFromCheckpoint: distanceFromCheckpoint ?? this.distanceFromCheckpoint,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      approvalTime: approvalTime ?? this.approvalTime,
      approvedBy: approvedBy ?? this.approvedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'navigatorId': navigatorId,
      'checkpointId': checkpointId,
      'punchLat': punchLocation.lat,
      'punchLng': punchLocation.lng,
      'punchUtm': punchLocation.utm,
      'punchTime': punchTime.toIso8601String(),
      'status': status.code,
      if (distanceFromCheckpoint != null) 'distanceFromCheckpoint': distanceFromCheckpoint,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (approvalTime != null) 'approvalTime': approvalTime!.toIso8601String(),
      if (approvedBy != null) 'approvedBy': approvedBy,
    };
  }

  factory CheckpointPunch.fromMap(Map<String, dynamic> map) {
    return CheckpointPunch(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      navigatorId: map['navigatorId'] as String,
      checkpointId: map['checkpointId'] as String,
      punchLocation: Coordinate(
        lat: map['punchLat'] as double,
        lng: map['punchLng'] as double,
        utm: map['punchUtm'] as String,
      ),
      punchTime: DateTime.parse(map['punchTime'] as String),
      status: PunchStatus.fromCode(map['status'] as String),
      distanceFromCheckpoint: map['distanceFromCheckpoint'] as double?,
      rejectionReason: map['rejectionReason'] as String?,
      approvalTime: map['approvalTime'] != null
          ? DateTime.parse(map['approvalTime'] as String)
          : null,
      approvedBy: map['approvedBy'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        navigationId,
        navigatorId,
        checkpointId,
        punchTime,
        status,
      ];
}

/// סוג התראה
enum AlertType {
  emergency('emergency', 'חירום', '🚨'),
  barbur('barbur', 'ברבור', '⚠️'),
  healthCheckExpired('health_check_expired', 'תקינות לא דווחה', '⏰'),
  healthReport('health_report', 'דיווח תקינות', '✅'),
  speed('speed', 'חריגת מהירות', '🏎️'),
  noMovement('no_movement', 'חוסר תנועה', '⏸️'),
  boundary('boundary', 'חריגת גבול גזרה', '🚧'),
  routeDeviation('route_deviation', 'סטייה מציר', '↗️'),
  safetyPoint('safety_point', 'קרבת נת"ב', '⛔'),
  proximity('proximity', 'קרבת מנווטים', '👥'),
  battery('battery', 'סוללה נמוכה', '🔋'),
  noReception('no_reception', 'חוסר קליטה', '📵');

  final String code;
  final String displayName;
  final String emoji;

  const AlertType(this.code, this.displayName, this.emoji);

  static AlertType fromCode(String code) {
    return AlertType.values.firstWhere(
      (t) => t.code == code,
      orElse: () => AlertType.emergency,
    );
  }
}

/// התראה ממנווט
class NavigatorAlert extends Equatable {
  final String id;
  final String navigationId;
  final String navigatorId;
  final AlertType type;
  final Coordinate location;
  final DateTime timestamp;
  final bool isActive;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final int? minutesOverdue; // דקות מעבר לזמן המוגדר (לבדיקת תקינות)
  final String? navigatorName; // שם המנווט (לתצוגה בהתראה)

  const NavigatorAlert({
    required this.id,
    required this.navigationId,
    required this.navigatorId,
    required this.type,
    required this.location,
    required this.timestamp,
    this.isActive = true,
    this.resolvedAt,
    this.resolvedBy,
    this.minutesOverdue,
    this.navigatorName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'navigatorId': navigatorId,
      'type': type.code,
      'lat': location.lat,
      'lng': location.lng,
      'utm': location.utm,
      'timestamp': timestamp.toIso8601String(),
      'isActive': isActive,
      if (resolvedAt != null) 'resolvedAt': resolvedAt!.toIso8601String(),
      if (resolvedBy != null) 'resolvedBy': resolvedBy,
      if (minutesOverdue != null) 'minutesOverdue': minutesOverdue,
      if (navigatorName != null) 'navigatorName': navigatorName,
    };
  }

  factory NavigatorAlert.fromMap(Map<String, dynamic> map) {
    return NavigatorAlert(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      navigatorId: map['navigatorId'] as String,
      type: AlertType.fromCode(map['type'] as String),
      location: Coordinate(
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
        utm: map['utm'] as String? ?? '',
      ),
      timestamp: DateTime.parse(map['timestamp'] as String),
      isActive: map['isActive'] as bool? ?? true,
      resolvedAt: map['resolvedAt'] != null
          ? DateTime.parse(map['resolvedAt'] as String)
          : null,
      resolvedBy: map['resolvedBy'] as String?,
      minutesOverdue: map['minutesOverdue'] as int?,
      navigatorName: map['navigatorName'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, navigationId, navigatorId, type, timestamp];
}
