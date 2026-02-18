import 'package:equatable/equatable.dart';

/// הודעה קולית (ווקי טוקי)
class VoiceMessage extends Equatable {
  final String id;
  final String navigationId;
  final String senderId;
  final String senderName;
  final String? targetId;      // null = שידור לכולם
  final String? targetName;
  final String audioUrl;
  final double duration;        // שניות
  final DateTime createdAt;

  const VoiceMessage({
    required this.id,
    required this.navigationId,
    required this.senderId,
    required this.senderName,
    this.targetId,
    this.targetName,
    required this.audioUrl,
    required this.duration,
    required this.createdAt,
  });

  VoiceMessage copyWith({
    String? id,
    String? navigationId,
    String? senderId,
    String? senderName,
    String? targetId,
    String? targetName,
    String? audioUrl,
    double? duration,
    DateTime? createdAt,
  }) {
    return VoiceMessage(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      targetId: targetId ?? this.targetId,
      targetName: targetName ?? this.targetName,
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'senderId': senderId,
      'senderName': senderName,
      if (targetId != null) 'targetId': targetId,
      if (targetName != null) 'targetName': targetName,
      'audioUrl': audioUrl,
      'duration': duration,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VoiceMessage.fromMap(Map<String, dynamic> map) {
    DateTime createdAt;
    final raw = map['createdAt'];
    if (raw is DateTime) {
      createdAt = raw;
    } else if (raw is String) {
      createdAt = DateTime.tryParse(raw) ?? DateTime.now();
    } else if (raw != null && raw.runtimeType.toString() == 'Timestamp') {
      createdAt = (raw as dynamic).toDate();
    } else {
      createdAt = DateTime.now();
    }

    return VoiceMessage(
      id: map['id'] as String? ?? '',
      navigationId: map['navigationId'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      senderName: map['senderName'] as String? ?? '',
      targetId: map['targetId'] as String?,
      targetName: map['targetName'] as String?,
      audioUrl: map['audioUrl'] as String? ?? '',
      duration: (map['duration'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id, navigationId, senderId, senderName,
    targetId, targetName, audioUrl, duration, createdAt,
  ];
}
