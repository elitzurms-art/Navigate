import 'package:equatable/equatable.dart';

/// ציון מנווט
class NavigationScore extends Equatable {
  final String id;
  final String navigationId;
  final String navigatorId;
  final int totalScore; // ציון כולל (0-100)
  final Map<String, CheckpointScore> checkpointScores; // ציון לכל נקודה
  final DateTime calculatedAt;
  final bool isManual; // האם ציון ידני או אוטומטי
  final String? notes; // הערות מהמפקד
  final bool isPublished; // האם הופץ למנווט
  final DateTime? publishedAt;

  const NavigationScore({
    required this.id,
    required this.navigationId,
    required this.navigatorId,
    required this.totalScore,
    required this.checkpointScores,
    required this.calculatedAt,
    this.isManual = false,
    this.notes,
    this.isPublished = false,
    this.publishedAt,
  });

  NavigationScore copyWith({
    String? id,
    String? navigationId,
    String? navigatorId,
    int? totalScore,
    Map<String, CheckpointScore>? checkpointScores,
    DateTime? calculatedAt,
    bool? isManual,
    String? notes,
    bool? isPublished,
    DateTime? publishedAt,
  }) {
    return NavigationScore(
      id: id ?? this.id,
      navigationId: navigationId ?? this.navigationId,
      navigatorId: navigatorId ?? this.navigatorId,
      totalScore: totalScore ?? this.totalScore,
      checkpointScores: checkpointScores ?? this.checkpointScores,
      calculatedAt: calculatedAt ?? this.calculatedAt,
      isManual: isManual ?? this.isManual,
      notes: notes ?? this.notes,
      isPublished: isPublished ?? this.isPublished,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'navigationId': navigationId,
      'navigatorId': navigatorId,
      'totalScore': totalScore,
      'checkpointScores': checkpointScores.map((k, v) => MapEntry(k, v.toMap())),
      'calculatedAt': calculatedAt.toIso8601String(),
      'isManual': isManual,
      if (notes != null) 'notes': notes,
      'isPublished': isPublished,
      if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    };
  }

  factory NavigationScore.fromMap(Map<String, dynamic> map) {
    return NavigationScore(
      id: map['id'] as String,
      navigationId: map['navigationId'] as String,
      navigatorId: map['navigatorId'] as String,
      totalScore: map['totalScore'] as int,
      checkpointScores: (map['checkpointScores'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, CheckpointScore.fromMap(v as Map<String, dynamic>)),
      ),
      calculatedAt: DateTime.parse(map['calculatedAt'] as String),
      isManual: map['isManual'] as bool? ?? false,
      notes: map['notes'] as String?,
      isPublished: map['isPublished'] as bool? ?? false,
      publishedAt: map['publishedAt'] != null
          ? DateTime.parse(map['publishedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, navigationId, navigatorId, totalScore, isPublished];
}

/// ציון לנקודת ציון בודדת
class CheckpointScore extends Equatable {
  final String checkpointId;
  final bool approved; // האם אושרה
  final int score; // ציון (0-100)
  final double distanceMeters; // מרחק מהנקודה המקורית
  final String? rejectionReason; // סיבת דחייה

  const CheckpointScore({
    required this.checkpointId,
    required this.approved,
    required this.score,
    required this.distanceMeters,
    this.rejectionReason,
  });

  Map<String, dynamic> toMap() {
    return {
      'checkpointId': checkpointId,
      'approved': approved,
      'score': score,
      'distanceMeters': distanceMeters,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };
  }

  factory CheckpointScore.fromMap(Map<String, dynamic> map) {
    return CheckpointScore(
      checkpointId: map['checkpointId'] as String,
      approved: map['approved'] as bool,
      score: map['score'] as int,
      distanceMeters: map['distanceMeters'] as double,
      rejectionReason: map['rejectionReason'] as String?,
    );
  }

  @override
  List<Object?> get props => [checkpointId, approved, score];
}

/// שיטת חישוב ציון
enum ScoringMethod {
  /// אישור/נכשל פשוט
  approvedFailed('approved_failed', 'אישור/נכשל'),

  /// ציון לפי מרחק
  distanceBased('distance_based', 'לפי מרחק'),

  /// ציון ידני
  manual('manual', 'ידני');

  final String code;
  final String displayName;

  const ScoringMethod(this.code, this.displayName);

  static ScoringMethod fromCode(String code) {
    return ScoringMethod.values.firstWhere(
      (method) => method.code == code,
      orElse: () => ScoringMethod.approvedFailed,
    );
  }
}
