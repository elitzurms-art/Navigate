import 'package:equatable/equatable.dart';

/// סטטוס בקשת הארכה
enum ExtensionRequestStatus { pending, approved, rejected }

/// בקשת הארכה — מנווט מבקש זמן נוסף, מפקד מאשר/דוחה
class ExtensionRequest extends Equatable {
  final String id;
  final String navigationId;
  final String navigatorId;
  final String navigatorName;
  final int requestedMinutes;
  final ExtensionRequestStatus status;
  final int? approvedMinutes;
  final String? respondedBy;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const ExtensionRequest({
    required this.id,
    required this.navigationId,
    required this.navigatorId,
    required this.navigatorName,
    required this.requestedMinutes,
    this.status = ExtensionRequestStatus.pending,
    this.approvedMinutes,
    this.respondedBy,
    required this.createdAt,
    this.respondedAt,
  });

  ExtensionRequest copyWith({
    String? id,
    String? navigationId,
    String? navigatorId,
    String? navigatorName,
    int? requestedMinutes,
    ExtensionRequestStatus? status,
    int? approvedMinutes,
    String? respondedBy,
    DateTime? createdAt,
    DateTime? respondedAt,
  }) {
    return ExtensionRequest(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      navigatorId: navigatorId ?? this.navigatorId,
      navigatorName: navigatorName ?? this.navigatorName,
      requestedMinutes: requestedMinutes ?? this.requestedMinutes,
      status: status ?? this.status,
      approvedMinutes: approvedMinutes ?? this.approvedMinutes,
      respondedBy: respondedBy ?? this.respondedBy,
      createdAt: createdAt ?? this.createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'navigatorId': navigatorId,
      'navigatorName': navigatorName,
      'requestedMinutes': requestedMinutes,
      'status': status.name,
      if (approvedMinutes != null) 'approvedMinutes': approvedMinutes,
      if (respondedBy != null) 'respondedBy': respondedBy,
      'createdAt': createdAt.toIso8601String(),
      if (respondedAt != null) 'respondedAt': respondedAt!.toIso8601String(),
    };
  }

  factory ExtensionRequest.fromMap(Map<String, dynamic> map) {
    DateTime createdAt;
    final rawCreated = map['createdAt'];
    if (rawCreated is DateTime) {
      createdAt = rawCreated;
    } else if (rawCreated is String) {
      createdAt = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else if (rawCreated != null && rawCreated.runtimeType.toString() == 'Timestamp') {
      createdAt = (rawCreated as dynamic).toDate();
    } else {
      createdAt = DateTime.now();
    }

    DateTime? respondedAt;
    final rawResponded = map['respondedAt'];
    if (rawResponded is DateTime) {
      respondedAt = rawResponded;
    } else if (rawResponded is String) {
      respondedAt = DateTime.tryParse(rawResponded);
    } else if (rawResponded != null && rawResponded.runtimeType.toString() == 'Timestamp') {
      respondedAt = (rawResponded as dynamic).toDate();
    }

    return ExtensionRequest(
      id: map['id'] as String? ?? '',
      navigationId: map['navigationId'] as String? ?? '',
      navigatorId: map['navigatorId'] as String? ?? '',
      navigatorName: map['navigatorName'] as String? ?? '',
      requestedMinutes: map['requestedMinutes'] as int? ?? 30,
      status: ExtensionRequestStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String? ?? 'pending'),
        orElse: () => ExtensionRequestStatus.pending,
      ),
      approvedMinutes: map['approvedMinutes'] as int?,
      respondedBy: map['respondedBy'] as String?,
      createdAt: createdAt,
      respondedAt: respondedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, navigationId, navigatorId, navigatorName,
    requestedMinutes, status, approvedMinutes,
    respondedBy, createdAt, respondedAt,
  ];
}
