import 'package:equatable/equatable.dart';

/// ציון מנווט
class NavigationScore extends Equatable {
  final String id;
  final String navigationId;
  final String navigatorId;
  final int totalScore; // ציון כולל (0-100)
  final Map<String, CheckpointScore> checkpointScores; // ציון לכל נקודה
  final Map<String, int> customCriteriaScores; // criterionId → ציון שניתן (0..weight)
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
    this.customCriteriaScores = const {},
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
    Map<String, int>? customCriteriaScores,
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
      customCriteriaScores: customCriteriaScores ?? this.customCriteriaScores,
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
      if (customCriteriaScores.isNotEmpty) 'customCriteriaScores': customCriteriaScores,
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
      customCriteriaScores: map['customCriteriaScores'] != null
          ? Map<String, int>.from(map['customCriteriaScores'] as Map)
          : const {},
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
  final int weight; // משקל הנקודה (0 = מצב ממוצע רגיל)

  const CheckpointScore({
    required this.checkpointId,
    required this.approved,
    required this.score,
    required this.distanceMeters,
    this.rejectionReason,
    this.weight = 0,
  });

  CheckpointScore copyWith({
    String? checkpointId,
    bool? approved,
    int? score,
    double? distanceMeters,
    String? rejectionReason,
    int? weight,
  }) {
    return CheckpointScore(
      checkpointId: checkpointId ?? this.checkpointId,
      approved: approved ?? this.approved,
      score: score ?? this.score,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      weight: weight ?? this.weight,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'checkpointId': checkpointId,
      'approved': approved,
      'score': score,
      'distanceMeters': distanceMeters,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (weight > 0) 'weight': weight,
    };
  }

  factory CheckpointScore.fromMap(Map<String, dynamic> map) {
    return CheckpointScore(
      checkpointId: map['checkpointId'] as String,
      approved: map['approved'] as bool,
      score: map['score'] as int,
      distanceMeters: map['distanceMeters'] as double,
      rejectionReason: map['rejectionReason'] as String?,
      weight: map['weight'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [checkpointId, approved, score, weight];
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
