import 'package:equatable/equatable.dart';

/// הגדרות זמן בטיחות
class SafetyTimeSettings extends Equatable {
  final String type; // 'hours' או 'after_last_mission'
  final int? hours; // אם בחרו שעות קבועות
  final int? hoursAfterMission; // שעות אחרי משימה אחרונה

  const SafetyTimeSettings({
    required this.type,
    this.hours,
    this.hoursAfterMission,
  });

  SafetyTimeSettings copyWith({
    String? type,
    int? hours,
    int? hoursAfterMission,
  }) {
    return SafetyTimeSettings(
      type: type ?? this.type,
      hours: hours ?? this.hours,
      hoursAfterMission: hoursAfterMission ?? this.hoursAfterMission,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (hours != null) 'hours': hours,
      if (hoursAfterMission != null) 'hoursAfterMission': hoursAfterMission,
    };
  }

  factory SafetyTimeSettings.fromMap(Map<String, dynamic> map) {
    return SafetyTimeSettings(
      type: map['type'] as String,
      hours: map['hours'] as int?,
      hoursAfterMission: map['hoursAfterMission'] as int?,
    );
  }

  @override
  List<Object?> get props => [type, hours, hoursAfterMission];
}

/// טווח מרחק עם ציון
class DistanceScoreRange extends Equatable {
  final int maxDistance; // במטרים
  final int scorePercentage; // אחוז ציון

  const DistanceScoreRange({
    required this.maxDistance,
    required this.scorePercentage,
  });

  Map<String, dynamic> toMap() {
    return {
      'maxDistance': maxDistance,
      'scorePercentage': scorePercentage,
    };
  }

  factory DistanceScoreRange.fromMap(Map<String, dynamic> map) {
    return DistanceScoreRange(
      maxDistance: map['maxDistance'] as int,
      scorePercentage: map['scorePercentage'] as int,
    );
  }

  @override
  List<Object?> get props => [maxDistance, scorePercentage];
}

/// הגדרות אימות נקודות
class VerificationSettings extends Equatable {
  final bool autoVerification; // האם מופעל אימות אוטומטי
  final String? verificationType; // 'approved_failed' או 'score_by_distance'
  final int? approvalDistance; // מרחק לאישור במטרים (אם בחרו approved_failed)
  final List<DistanceScoreRange>? scoreRanges; // טווחי מרחק וציון (אם בחרו score_by_distance)
  final String punchMode; // 'sequential' או 'free'

  const VerificationSettings({
    required this.autoVerification,
    this.verificationType,
    this.approvalDistance,
    this.scoreRanges,
    this.punchMode = 'sequential',
  });

  VerificationSettings copyWith({
    bool? autoVerification,
    String? verificationType,
    int? approvalDistance,
    List<DistanceScoreRange>? scoreRanges,
    String? punchMode,
  }) {
    return VerificationSettings(
      autoVerification: autoVerification ?? this.autoVerification,
      verificationType: verificationType ?? this.verificationType,
      approvalDistance: approvalDistance ?? this.approvalDistance,
      scoreRanges: scoreRanges ?? this.scoreRanges,
      punchMode: punchMode ?? this.punchMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'autoVerification': autoVerification,
      if (verificationType != null) 'verificationType': verificationType,
      if (approvalDistance != null) 'approvalDistance': approvalDistance,
      if (scoreRanges != null)
        'scoreRanges': scoreRanges!.map((r) => r.toMap()).toList(),
      'punchMode': punchMode,
    };
  }

  factory VerificationSettings.fromMap(Map<String, dynamic> map) {
    return VerificationSettings(
      autoVerification: map['autoVerification'] as bool? ?? true,
      verificationType: map['verificationType'] as String?,
      approvalDistance: map['approvalDistance'] as int?,
      scoreRanges: map['scoreRanges'] != null
          ? (map['scoreRanges'] as List)
              .map((r) => DistanceScoreRange.fromMap(r as Map<String, dynamic>))
              .toList()
          : null,
      punchMode: map['punchMode'] as String? ?? 'sequential',
    );
  }

  @override
  List<Object?> get props => [
        autoVerification,
        verificationType,
        approvalDistance,
        scoreRanges,
        punchMode,
      ];
}

/// הגדרות התראות
class NavigationAlerts extends Equatable {
  final bool enabled; // האם התראות מופעלות

  // התראת מהירות
  final bool speedAlertEnabled;
  final int? maxSpeed; // קמ"ש

  // התראת חוסר תנועה
  final bool noMovementAlertEnabled;
  final int? noMovementMinutes;

  // התראת גבול גזרה
  final bool ggAlertEnabled;
  final int? ggAlertRange; // מטרים

  // התראת נתבים
  final bool routesAlertEnabled;
  final int? routesAlertRange; // מטרים

  // התראת נת"ב
  final bool nbAlertEnabled;
  final int? nbAlertRange; // מטרים

  // התראת קרבת מנווטים
  final bool navigatorProximityAlertEnabled;
  final int? proximityDistance; // מטרים
  final int? proximityMinTime; // דקות

  // התראת סוללה
  final bool batteryAlertEnabled;
  final int? batteryPercentage;

  // התראת חוסר קליטה
  final bool noReceptionAlertEnabled;
  final int? noReceptionMinTime; // שניות

  // בדיקת תקינות מנווטים
  final bool healthCheckEnabled;
  final int healthCheckIntervalMinutes; // דקות (30-600, קפיצות 30)

  const NavigationAlerts({
    required this.enabled,
    this.speedAlertEnabled = false,
    this.maxSpeed,
    this.noMovementAlertEnabled = false,
    this.noMovementMinutes,
    this.ggAlertEnabled = false,
    this.ggAlertRange,
    this.routesAlertEnabled = false,
    this.routesAlertRange,
    this.nbAlertEnabled = false,
    this.nbAlertRange,
    this.navigatorProximityAlertEnabled = false,
    this.proximityDistance,
    this.proximityMinTime,
    this.batteryAlertEnabled = false,
    this.batteryPercentage,
    this.noReceptionAlertEnabled = false,
    this.noReceptionMinTime,
    this.healthCheckEnabled = true,
    this.healthCheckIntervalMinutes = 60,
  });

  NavigationAlerts copyWith({
    bool? enabled,
    bool? speedAlertEnabled,
    int? maxSpeed,
    bool? noMovementAlertEnabled,
    int? noMovementMinutes,
    bool? ggAlertEnabled,
    int? ggAlertRange,
    bool? routesAlertEnabled,
    int? routesAlertRange,
    bool? nbAlertEnabled,
    int? nbAlertRange,
    bool? navigatorProximityAlertEnabled,
    int? proximityDistance,
    int? proximityMinTime,
    bool? batteryAlertEnabled,
    int? batteryPercentage,
    bool? noReceptionAlertEnabled,
    int? noReceptionMinTime,
    bool? healthCheckEnabled,
    int? healthCheckIntervalMinutes,
  }) {
    return NavigationAlerts(
      enabled: enabled ?? this.enabled,
      speedAlertEnabled: speedAlertEnabled ?? this.speedAlertEnabled,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      noMovementAlertEnabled: noMovementAlertEnabled ?? this.noMovementAlertEnabled,
      noMovementMinutes: noMovementMinutes ?? this.noMovementMinutes,
      ggAlertEnabled: ggAlertEnabled ?? this.ggAlertEnabled,
      ggAlertRange: ggAlertRange ?? this.ggAlertRange,
      routesAlertEnabled: routesAlertEnabled ?? this.routesAlertEnabled,
      routesAlertRange: routesAlertRange ?? this.routesAlertRange,
      nbAlertEnabled: nbAlertEnabled ?? this.nbAlertEnabled,
      nbAlertRange: nbAlertRange ?? this.nbAlertRange,
      navigatorProximityAlertEnabled:
          navigatorProximityAlertEnabled ?? this.navigatorProximityAlertEnabled,
      proximityDistance: proximityDistance ?? this.proximityDistance,
      proximityMinTime: proximityMinTime ?? this.proximityMinTime,
      batteryAlertEnabled: batteryAlertEnabled ?? this.batteryAlertEnabled,
      batteryPercentage: batteryPercentage ?? this.batteryPercentage,
      noReceptionAlertEnabled: noReceptionAlertEnabled ?? this.noReceptionAlertEnabled,
      noReceptionMinTime: noReceptionMinTime ?? this.noReceptionMinTime,
      healthCheckEnabled: healthCheckEnabled ?? this.healthCheckEnabled,
      healthCheckIntervalMinutes: healthCheckIntervalMinutes ?? this.healthCheckIntervalMinutes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'speedAlertEnabled': speedAlertEnabled,
      if (maxSpeed != null) 'maxSpeed': maxSpeed,
      'noMovementAlertEnabled': noMovementAlertEnabled,
      if (noMovementMinutes != null) 'noMovementMinutes': noMovementMinutes,
      'ggAlertEnabled': ggAlertEnabled,
      if (ggAlertRange != null) 'ggAlertRange': ggAlertRange,
      'routesAlertEnabled': routesAlertEnabled,
      if (routesAlertRange != null) 'routesAlertRange': routesAlertRange,
      'nbAlertEnabled': nbAlertEnabled,
      if (nbAlertRange != null) 'nbAlertRange': nbAlertRange,
      'navigatorProximityAlertEnabled': navigatorProximityAlertEnabled,
      if (proximityDistance != null) 'proximityDistance': proximityDistance,
      if (proximityMinTime != null) 'proximityMinTime': proximityMinTime,
      'batteryAlertEnabled': batteryAlertEnabled,
      if (batteryPercentage != null) 'batteryPercentage': batteryPercentage,
      'noReceptionAlertEnabled': noReceptionAlertEnabled,
      if (noReceptionMinTime != null) 'noReceptionMinTime': noReceptionMinTime,
      'healthCheckEnabled': healthCheckEnabled,
      'healthCheckIntervalMinutes': healthCheckIntervalMinutes,
    };
  }

  factory NavigationAlerts.fromMap(Map<String, dynamic> map) {
    return NavigationAlerts(
      enabled: map['enabled'] as bool? ?? false,
      speedAlertEnabled: map['speedAlertEnabled'] as bool? ?? false,
      maxSpeed: map['maxSpeed'] as int?,
      noMovementAlertEnabled: map['noMovementAlertEnabled'] as bool? ?? false,
      noMovementMinutes: map['noMovementMinutes'] as int?,
      ggAlertEnabled: map['ggAlertEnabled'] as bool? ?? false,
      ggAlertRange: map['ggAlertRange'] as int?,
      routesAlertEnabled: map['routesAlertEnabled'] as bool? ?? false,
      routesAlertRange: map['routesAlertRange'] as int?,
      nbAlertEnabled: map['nbAlertEnabled'] as bool? ?? false,
      nbAlertRange: map['nbAlertRange'] as int?,
      navigatorProximityAlertEnabled:
          map['navigatorProximityAlertEnabled'] as bool? ?? false,
      proximityDistance: map['proximityDistance'] as int?,
      proximityMinTime: map['proximityMinTime'] as int?,
      batteryAlertEnabled: map['batteryAlertEnabled'] as bool? ?? false,
      batteryPercentage: map['batteryPercentage'] as int?,
      noReceptionAlertEnabled: map['noReceptionAlertEnabled'] as bool? ?? false,
      noReceptionMinTime: map['noReceptionMinTime'] as int?,
      healthCheckEnabled: map['healthCheckEnabled'] as bool? ?? true,
      healthCheckIntervalMinutes: map['healthCheckIntervalMinutes'] as int? ?? 60,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        speedAlertEnabled,
        maxSpeed,
        noMovementAlertEnabled,
        noMovementMinutes,
        ggAlertEnabled,
        ggAlertRange,
        routesAlertEnabled,
        routesAlertRange,
        nbAlertEnabled,
        nbAlertRange,
        navigatorProximityAlertEnabled,
        proximityDistance,
        proximityMinTime,
        batteryAlertEnabled,
        batteryPercentage,
        noReceptionAlertEnabled,
        noReceptionMinTime,
        healthCheckEnabled,
        healthCheckIntervalMinutes,
      ];
}

/// הגדרות למידה
class LearningSettings extends Equatable {
  final bool enabledWithPhones; // אפשר למידה עם פלאפונים
  final bool showAllCheckpoints; // אפשר לראות כל נקודות כל המנווטים
  final bool showNavigationDetails; // הצגת פרטי ניווט
  final bool showMissionTimes; // הצגת זמני משימה למנווט
  final bool showRoutes; // הצגת צירים
  final bool allowRouteEditing; // אפשר עריכת צירים
  final bool allowRouteNarration; // אפשר סיפור דרך
  final bool autoLearningTimes; // הגדר זמני לימוד אוטומטיים
  final DateTime? learningDate; // תאריך לימוד
  final String? learningStartTime; // שעת התחלה (HH:mm)
  final String? learningEndTime; // שעת סיום (HH:mm)
  final bool requireCommanderQuiz; // הפעל מבחן מפקדים
  final bool requireSoloQuiz; // חובת מבחן ניווט בדד
  final String quizType; // סוג מבחן: 'solo' (בדד) או 'regular' (רגיל)
  final bool quizOpenManually; // מפקד פתח מבחן ידנית
  final bool autoQuizTimes; // זמני מבחן אוטומטיים
  final DateTime? quizDate; // תאריך מבחן
  final String? quizStartTime; // שעת התחלת מבחן (HH:mm)
  final String? quizEndTime; // שעת סיום מבחן (HH:mm)

  const LearningSettings({
    this.enabledWithPhones = true,
    this.showAllCheckpoints = false,
    this.showNavigationDetails = true,
    this.showMissionTimes = true,
    this.showRoutes = true,
    this.allowRouteEditing = true,
    this.allowRouteNarration = true,
    this.autoLearningTimes = false,
    this.learningDate,
    this.learningStartTime,
    this.learningEndTime,
    this.requireCommanderQuiz = false,
    this.requireSoloQuiz = false,
    this.quizType = 'solo',
    this.quizOpenManually = false,
    this.autoQuizTimes = false,
    this.quizDate,
    this.quizStartTime,
    this.quizEndTime,
  });

  LearningSettings copyWith({
    bool? enabledWithPhones,
    bool? showAllCheckpoints,
    bool? showNavigationDetails,
    bool? showMissionTimes,
    bool? showRoutes,
    bool? allowRouteEditing,
    bool? allowRouteNarration,
    bool? autoLearningTimes,
    DateTime? learningDate,
    String? learningStartTime,
    String? learningEndTime,
    bool? requireCommanderQuiz,
    bool? requireSoloQuiz,
    String? quizType,
    bool? quizOpenManually,
    bool? autoQuizTimes,
    DateTime? quizDate,
    String? quizStartTime,
    String? quizEndTime,
  }) {
    return LearningSettings(
      enabledWithPhones: enabledWithPhones ?? this.enabledWithPhones,
      showAllCheckpoints: showAllCheckpoints ?? this.showAllCheckpoints,
      showNavigationDetails: showNavigationDetails ?? this.showNavigationDetails,
      showMissionTimes: showMissionTimes ?? this.showMissionTimes,
      showRoutes: showRoutes ?? this.showRoutes,
      allowRouteEditing: allowRouteEditing ?? this.allowRouteEditing,
      allowRouteNarration: allowRouteNarration ?? this.allowRouteNarration,
      autoLearningTimes: autoLearningTimes ?? this.autoLearningTimes,
      learningDate: learningDate ?? this.learningDate,
      learningStartTime: learningStartTime ?? this.learningStartTime,
      learningEndTime: learningEndTime ?? this.learningEndTime,
      requireCommanderQuiz: requireCommanderQuiz ?? this.requireCommanderQuiz,
      requireSoloQuiz: requireSoloQuiz ?? this.requireSoloQuiz,
      quizType: quizType ?? this.quizType,
      quizOpenManually: quizOpenManually ?? this.quizOpenManually,
      autoQuizTimes: autoQuizTimes ?? this.autoQuizTimes,
      quizDate: quizDate ?? this.quizDate,
      quizStartTime: quizStartTime ?? this.quizStartTime,
      quizEndTime: quizEndTime ?? this.quizEndTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabledWithPhones': enabledWithPhones,
      'showAllCheckpoints': showAllCheckpoints,
      'showNavigationDetails': showNavigationDetails,
      'showMissionTimes': showMissionTimes,
      'showRoutes': showRoutes,
      'allowRouteEditing': allowRouteEditing,
      'allowRouteNarration': allowRouteNarration,
      'autoLearningTimes': autoLearningTimes,
      if (learningDate != null)
        'learningDate': learningDate!.toIso8601String(),
      if (learningStartTime != null) 'learningStartTime': learningStartTime,
      if (learningEndTime != null) 'learningEndTime': learningEndTime,
      'requireCommanderQuiz': requireCommanderQuiz,
      'requireSoloQuiz': requireSoloQuiz,
      'quizType': quizType,
      'quizOpenManually': quizOpenManually,
      'autoQuizTimes': autoQuizTimes,
      if (quizDate != null)
        'quizDate': quizDate!.toIso8601String(),
      if (quizStartTime != null) 'quizStartTime': quizStartTime,
      if (quizEndTime != null) 'quizEndTime': quizEndTime,
    };
  }

  factory LearningSettings.fromMap(Map<String, dynamic> map) {
    return LearningSettings(
      enabledWithPhones: map['enabledWithPhones'] as bool? ?? true,
      showAllCheckpoints: map['showAllCheckpoints'] as bool? ?? false,
      showNavigationDetails: map['showNavigationDetails'] as bool? ?? true,
      showMissionTimes: map['showMissionTimes'] as bool? ?? true,
      showRoutes: map['showRoutes'] as bool? ?? true,
      allowRouteEditing: map['allowRouteEditing'] as bool? ?? true,
      allowRouteNarration: map['allowRouteNarration'] as bool? ?? true,
      autoLearningTimes: map['autoLearningTimes'] as bool? ?? false,
      learningDate: map['learningDate'] != null
          ? DateTime.parse(map['learningDate'] as String)
          : null,
      learningStartTime: map['learningStartTime'] as String?,
      learningEndTime: map['learningEndTime'] as String?,
      requireCommanderQuiz: map['requireCommanderQuiz'] as bool? ?? false,
      // commanderQuizOpenManually — removed, ignored from old Firestore docs
      requireSoloQuiz: map['requireSoloQuiz'] as bool? ?? false,
      quizType: map['quizType'] as String? ?? 'solo',
      quizOpenManually: map['quizOpenManually'] as bool? ?? false,
      autoQuizTimes: map['autoQuizTimes'] as bool? ?? false,
      quizDate: map['quizDate'] != null
          ? DateTime.parse(map['quizDate'] as String)
          : null,
      quizStartTime: map['quizStartTime'] as String?,
      quizEndTime: map['quizEndTime'] as String?,
    );
  }

  /// האם המבחן פתוח כרגע (ידנית או אוטומטית)
  bool get isQuizCurrentlyOpen {
    if (!requireSoloQuiz) return false;
    if (quizOpenManually) return true;
    if (autoQuizTimes && quizDate != null && quizStartTime != null && quizEndTime != null) {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      final quizDay = DateTime(quizDate!.year, quizDate!.month, quizDate!.day);
      if (todayDate.isAtSameMomentAs(quizDay)) {
        final startParts = quizStartTime!.split(':');
        final endParts = quizEndTime!.split(':');
        final start = DateTime(now.year, now.month, now.day, int.parse(startParts[0]), int.parse(startParts[1]));
        final end = DateTime(now.year, now.month, now.day, int.parse(endParts[0]), int.parse(endParts[1]));
        return now.isAfter(start) && now.isBefore(end);
      }
    }
    return false;
  }

  /// האם מבחן מפקדים פתוח כרגע (מיידי — ברגע שהופעל)
  bool get isCommanderQuizCurrentlyOpen => requireCommanderQuiz;

  @override
  List<Object?> get props => [
        requireCommanderQuiz,
        enabledWithPhones,
        showAllCheckpoints,
        showNavigationDetails,
        showMissionTimes,
        showRoutes,
        allowRouteEditing,
        allowRouteNarration,
        autoLearningTimes,
        learningDate,
        learningStartTime,
        learningEndTime,
        requireSoloQuiz,
        quizType,
        quizOpenManually,
        autoQuizTimes,
        quizDate,
        quizStartTime,
        quizEndTime,
      ];
}

/// קריטריון ניקוד מותאם אישית
class CustomCriterion extends Equatable {
  final String id;
  final String name;
  final int weight; // ניקוד מקסימלי

  const CustomCriterion({
    required this.id,
    required this.name,
    required this.weight,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'weight': weight,
    };
  }

  factory CustomCriterion.fromMap(Map<String, dynamic> map) {
    return CustomCriterion(
      id: map['id'] as String,
      name: map['name'] as String,
      weight: map['weight'] as int,
    );
  }

  CustomCriterion copyWith({
    String? id,
    String? name,
    int? weight,
  }) {
    return CustomCriterion(
      id: id ?? this.id,
      name: name ?? this.name,
      weight: weight ?? this.weight,
    );
  }

  @override
  List<Object?> get props => [id, name, weight];
}

/// קריטריוני ניקוד לניווט
class ScoringCriteria extends Equatable {
  final String mode; // 'equal' | 'custom'
  final int? equalWeightPerCheckpoint; // משקל לכל נקודה במצב שווה
  final Map<String, int> checkpointWeights; // position index → weight במצב מותאם
  final List<CustomCriterion> customCriteria;

  const ScoringCriteria({
    required this.mode,
    this.equalWeightPerCheckpoint,
    this.checkpointWeights = const {},
    this.customCriteria = const [],
  });

  ScoringCriteria copyWith({
    String? mode,
    int? equalWeightPerCheckpoint,
    Map<String, int>? checkpointWeights,
    List<CustomCriterion>? customCriteria,
  }) {
    return ScoringCriteria(
      mode: mode ?? this.mode,
      equalWeightPerCheckpoint: equalWeightPerCheckpoint ?? this.equalWeightPerCheckpoint,
      checkpointWeights: checkpointWeights ?? this.checkpointWeights,
      customCriteria: customCriteria ?? this.customCriteria,
    );
  }

  int get totalWeight {
    int total = 0;
    if (mode == 'equal') {
      // equalWeightPerCheckpoint is per-checkpoint — actual total depends on checkpoint count
      // so totalWeight here sums the custom criteria only (checkpoint part computed externally)
      total = 0; // will be computed with checkpoint count
    } else {
      total = checkpointWeights.values.fold(0, (s, w) => s + w);
    }
    total += customCriteria.fold(0, (s, c) => s + c.weight);
    return total;
  }

  int totalWeightWithCheckpoints(int checkpointCount) {
    int total = 0;
    if (mode == 'equal') {
      total = (equalWeightPerCheckpoint ?? 0) * checkpointCount;
    } else {
      total = checkpointWeights.values.fold(0, (s, w) => s + w);
    }
    total += customCriteria.fold(0, (s, c) => s + c.weight);
    return total;
  }

  Map<String, dynamic> toMap() {
    return {
      'mode': mode,
      if (equalWeightPerCheckpoint != null) 'equalWeightPerCheckpoint': equalWeightPerCheckpoint,
      if (checkpointWeights.isNotEmpty) 'checkpointWeights': checkpointWeights,
      if (customCriteria.isNotEmpty)
        'customCriteria': customCriteria.map((c) => c.toMap()).toList(),
    };
  }

  factory ScoringCriteria.fromMap(Map<String, dynamic> map) {
    return ScoringCriteria(
      mode: map['mode'] as String? ?? 'equal',
      equalWeightPerCheckpoint: map['equalWeightPerCheckpoint'] as int?,
      checkpointWeights: map['checkpointWeights'] is Map
          ? Map<String, int>.from(map['checkpointWeights'] as Map)
          : const {},
      customCriteria: map['customCriteria'] != null
          ? (map['customCriteria'] as List)
              .map((c) => CustomCriterion.fromMap(c as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [mode, equalWeightPerCheckpoint, checkpointWeights, customCriteria];
}

/// הגדרות תחקיר
class ReviewSettings extends Equatable {
  final bool showScoresAfterApproval; // הצג ציונים לאחר אישרור
  final ScoringCriteria? scoringCriteria; // קריטריוני ניקוד משוקללים

  const ReviewSettings({
    this.showScoresAfterApproval = true,
    this.scoringCriteria,
  });

  ReviewSettings copyWith({
    bool? showScoresAfterApproval,
    ScoringCriteria? scoringCriteria,
  }) {
    return ReviewSettings(
      showScoresAfterApproval: showScoresAfterApproval ?? this.showScoresAfterApproval,
      scoringCriteria: scoringCriteria ?? this.scoringCriteria,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'showScoresAfterApproval': showScoresAfterApproval,
      if (scoringCriteria != null) 'scoringCriteria': scoringCriteria!.toMap(),
    };
  }

  factory ReviewSettings.fromMap(Map<String, dynamic> map) {
    return ReviewSettings(
      showScoresAfterApproval: map['showScoresAfterApproval'] as bool? ?? true,
      scoringCriteria: map['scoringCriteria'] != null
          ? ScoringCriteria.fromMap(map['scoringCriteria'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  List<Object?> get props => [showScoresAfterApproval, scoringCriteria];
}

/// הגדרות תצוגה
class DisplaySettings extends Equatable {
  final String? defaultMap; // מפת ברירת מחדל
  final double? openingLat; // קו רוחב לפתיחת הניווט
  final double? openingLng; // קו אורך לפתיחת הניווט
  final Map<String, bool>? activeLayers; // שכבות פעילות
  final Map<String, double>? layerOpacity; // שקיפות שכבות
  final bool enableVariablesSheet; // מילוי דף משתנים דיגיטלי

  const DisplaySettings({
    this.defaultMap,
    this.openingLat,
    this.openingLng,
    this.activeLayers,
    this.layerOpacity,
    this.enableVariablesSheet = true,
  });

  DisplaySettings copyWith({
    String? defaultMap,
    double? openingLat,
    double? openingLng,
    Map<String, bool>? activeLayers,
    Map<String, double>? layerOpacity,
    bool? enableVariablesSheet,
  }) {
    return DisplaySettings(
      defaultMap: defaultMap ?? this.defaultMap,
      openingLat: openingLat ?? this.openingLat,
      openingLng: openingLng ?? this.openingLng,
      activeLayers: activeLayers ?? this.activeLayers,
      layerOpacity: layerOpacity ?? this.layerOpacity,
      enableVariablesSheet: enableVariablesSheet ?? this.enableVariablesSheet,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (defaultMap != null) 'defaultMap': defaultMap,
      if (openingLat != null) 'openingLat': openingLat,
      if (openingLng != null) 'openingLng': openingLng,
      if (activeLayers != null) 'activeLayers': activeLayers,
      if (layerOpacity != null) 'layerOpacity': layerOpacity,
      'enableVariablesSheet': enableVariablesSheet,
    };
  }

  factory DisplaySettings.fromMap(Map<String, dynamic> map) {
    return DisplaySettings(
      defaultMap: map['defaultMap'] as String?,
      openingLat: map['openingLat'] as double?,
      openingLng: map['openingLng'] as double?,
      activeLayers: map['activeLayers'] is Map
          ? Map<String, bool>.from(map['activeLayers'] as Map)
          : null,
      layerOpacity: map['layerOpacity'] is Map
          ? (map['layerOpacity'] as Map).map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()))
          : null,
      enableVariablesSheet: map['enableVariablesSheet'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
        defaultMap,
        openingLat,
        openingLng,
        activeLayers,
        layerOpacity,
        enableVariablesSheet,
      ];
}

/// הגדרות חישוב זמני ניווט
class TimeCalculationSettings extends Equatable {
  final bool enabled;           // טוגל (default: true)
  final bool isHeavyLoad;       // מעל 40% משקל גוף
  final bool isNightNavigation; // ניווט לילה
  final bool isSummer;          // קיץ (true) / חורף (false)
  final bool allowExtensionRequests; // אפשר בקשות הארכה
  final String extensionWindowType;  // 'all' = כל הניווט, 'timed' = זמן מוגדר מסיום
  final int? extensionWindowMinutes; // דקות לפני סיום (null = ללא הגבלה)

  const TimeCalculationSettings({
    this.enabled = true,
    this.isHeavyLoad = false,
    this.isNightNavigation = false,
    this.isSummer = true,
    this.allowExtensionRequests = true,
    this.extensionWindowType = 'all',
    this.extensionWindowMinutes,
  });

  /// מהירות הליכה בקמ"ש לפי משקל ותאורה
  double get walkingSpeedKmh {
    if (isHeavyLoad) return isNightNavigation ? 2.0 : 3.5;
    return isNightNavigation ? 2.5 : 4.0;
  }

  /// דקות הפסקה לפי אורך ציר (הפסקה כל 10 ק"מ)
  int breakDurationMinutes(double routeLengthKm) {
    if (routeLengthKm <= 10) return 0;
    final breakCount = (routeLengthKm / 10).floor();
    final minutesPerBreak = isSummer ? 15 : 10;
    return breakCount * minutesPerBreak;
  }

  TimeCalculationSettings copyWith({
    bool? enabled,
    bool? isHeavyLoad,
    bool? isNightNavigation,
    bool? isSummer,
    bool? allowExtensionRequests,
    String? extensionWindowType,
    int? extensionWindowMinutes,
  }) {
    return TimeCalculationSettings(
      enabled: enabled ?? this.enabled,
      isHeavyLoad: isHeavyLoad ?? this.isHeavyLoad,
      isNightNavigation: isNightNavigation ?? this.isNightNavigation,
      isSummer: isSummer ?? this.isSummer,
      allowExtensionRequests: allowExtensionRequests ?? this.allowExtensionRequests,
      extensionWindowType: extensionWindowType ?? this.extensionWindowType,
      extensionWindowMinutes: extensionWindowMinutes ?? this.extensionWindowMinutes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'isHeavyLoad': isHeavyLoad,
      'isNightNavigation': isNightNavigation,
      'isSummer': isSummer,
      'allowExtensionRequests': allowExtensionRequests,
      'extensionWindowType': extensionWindowType,
      if (extensionWindowMinutes != null) 'extensionWindowMinutes': extensionWindowMinutes,
    };
  }

  factory TimeCalculationSettings.fromMap(Map<String, dynamic> map) {
    return TimeCalculationSettings(
      enabled: map['enabled'] as bool? ?? true,
      isHeavyLoad: map['isHeavyLoad'] as bool? ?? false,
      isNightNavigation: map['isNightNavigation'] as bool? ?? false,
      isSummer: map['isSummer'] as bool? ?? true,
      allowExtensionRequests: map['allowExtensionRequests'] as bool? ?? true,
      extensionWindowType: map['extensionWindowType'] as String? ?? 'all',
      extensionWindowMinutes: map['extensionWindowMinutes'] as int?,
    );
  }

  @override
  List<Object?> get props => [
    enabled, isHeavyLoad, isNightNavigation, isSummer,
    allowExtensionRequests, extensionWindowType, extensionWindowMinutes,
  ];
}

/// הגדרות תקשורת (ווקי טוקי)
class CommunicationSettings extends Equatable {
  final bool walkieTalkieEnabled;

  const CommunicationSettings({
    this.walkieTalkieEnabled = true,
  });

  CommunicationSettings copyWith({
    bool? walkieTalkieEnabled,
  }) {
    return CommunicationSettings(
      walkieTalkieEnabled: walkieTalkieEnabled ?? this.walkieTalkieEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'walkieTalkieEnabled': walkieTalkieEnabled,
    };
  }

  factory CommunicationSettings.fromMap(Map<String, dynamic> map) {
    return CommunicationSettings(
      walkieTalkieEnabled: map['walkieTalkieEnabled'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [walkieTalkieEnabled];
}

/// נקודת ביניים - נ.צ. שכולם עוברים בה
class WaypointCheckpoint extends Equatable {
  final String checkpointId; // מזהה נקודת הציון
  final String placementType; // 'distance' או 'between_checkpoints'

  // עבור placementType == 'distance' — טווח מרחק
  final double? afterDistanceMinKm; // טווח מינימום
  final double? afterDistanceMaxKm; // טווח מקסימום

  // עבור placementType == 'between_checkpoints'
  // -1 = בין התחלה לנקודה 1, 0 = בין נקודה 1 לנקודה 2, וכו'
  final int? afterCheckpointIndex;

  const WaypointCheckpoint({
    required this.checkpointId,
    required this.placementType,
    this.afterDistanceMinKm,
    this.afterDistanceMaxKm,
    this.afterCheckpointIndex,
  });

  WaypointCheckpoint copyWith({
    String? checkpointId,
    String? placementType,
    double? afterDistanceMinKm,
    double? afterDistanceMaxKm,
    int? afterCheckpointIndex,
  }) {
    return WaypointCheckpoint(
      checkpointId: checkpointId ?? this.checkpointId,
      placementType: placementType ?? this.placementType,
      afterDistanceMinKm: afterDistanceMinKm ?? this.afterDistanceMinKm,
      afterDistanceMaxKm: afterDistanceMaxKm ?? this.afterDistanceMaxKm,
      afterCheckpointIndex: afterCheckpointIndex ?? this.afterCheckpointIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'checkpointId': checkpointId,
      'placementType': placementType,
      if (afterDistanceMinKm != null) 'afterDistanceMinKm': afterDistanceMinKm,
      if (afterDistanceMaxKm != null) 'afterDistanceMaxKm': afterDistanceMaxKm,
      if (afterCheckpointIndex != null) 'afterCheckpointIndex': afterCheckpointIndex,
    };
  }

  factory WaypointCheckpoint.fromMap(Map<String, dynamic> map) {
    // תאימות לאחור: afterDistanceKm ישן → min=max=afterDistanceKm
    final oldDistance = (map['afterDistanceKm'] as num?)?.toDouble();
    return WaypointCheckpoint(
      checkpointId: map['checkpointId'] as String,
      placementType: map['placementType'] as String,
      afterDistanceMinKm: (map['afterDistanceMinKm'] as num?)?.toDouble() ?? oldDistance,
      afterDistanceMaxKm: (map['afterDistanceMaxKm'] as num?)?.toDouble() ?? oldDistance,
      afterCheckpointIndex: map['afterCheckpointIndex'] as int?,
      // beforeCheckpointIndex ישן — מתעלם
    );
  }

  @override
  List<Object?> get props => [checkpointId, placementType, afterDistanceMinKm, afterDistanceMaxKm, afterCheckpointIndex];
}

/// הגדרות נקודות ביניים
class WaypointSettings extends Equatable {
  final bool enabled; // האם להשתמש בנקודות ביניים
  final List<WaypointCheckpoint> waypoints; // רשימת נקודות ביניים

  const WaypointSettings({
    this.enabled = false,
    this.waypoints = const [],
  });

  WaypointSettings copyWith({
    bool? enabled,
    List<WaypointCheckpoint>? waypoints,
  }) {
    return WaypointSettings(
      enabled: enabled ?? this.enabled,
      waypoints: waypoints ?? this.waypoints,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'waypoints': waypoints.map((w) => w.toMap()).toList(),
    };
  }

  factory WaypointSettings.fromMap(Map<String, dynamic> map) {
    return WaypointSettings(
      enabled: map['enabled'] as bool? ?? false,
      waypoints: map['waypoints'] != null
          ? (map['waypoints'] as List)
              .map((w) => WaypointCheckpoint.fromMap(w as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [enabled, waypoints];
}

/// שלבי ניווט כוכב — מחושב מ-timestamps + punch state בזמן ריצה, אף פעם לא נשמר
enum StarPhase { atCenter, learning, navigating, returning, timeout, completed }

/// חישוב שלב כוכב נוכחי מנתונים שמורים
StarPhase computeStarPhase({
  int? index,
  DateTime? learningEnd,
  DateTime? navigatingEnd,
  bool currentPointPunched = false,
  bool returned = false,
  int totalPoints = 0,
  required DateTime now,
}) {
  if (index == null || index < 0) return StarPhase.atCenter;
  if (returned && currentPointPunched) {
    if (index >= totalPoints - 1) return StarPhase.completed;
    return StarPhase.atCenter;
  }
  if (returned && !currentPointPunched) return StarPhase.atCenter; // safety
  if (learningEnd != null && now.isBefore(learningEnd)) return StarPhase.learning;
  if (currentPointPunched) return StarPhase.returning;
  if (navigatingEnd == null || now.isBefore(navigatingEnd)) return StarPhase.navigating;
  return StarPhase.timeout;
}

/// הגדרות אשכולות
class ClusterSettings extends Equatable {
  final int clusterSize;           // 2-8, default 3
  final int clusterSpreadMeters;   // רדיוס התחלתי לנקודות מטעות (50-500m, default 200)
  final bool revealOpenManually;   // חשיפה ידנית מהלמידה — ברירת מחדל false
  final bool autoRevealTimes;      // תזמון אוטומטי — ברירת מחדל false
  final DateTime? revealDate;      // תאריך חשיפה
  final String? revealStartTime;   // שעת התחלה (HH:mm)
  final String? revealEndTime;     // שעת סיום (HH:mm)

  const ClusterSettings({
    this.clusterSize = 3,
    this.clusterSpreadMeters = 200,
    this.revealOpenManually = false,
    this.autoRevealTimes = false,
    this.revealDate,
    this.revealStartTime,
    this.revealEndTime,
  });

  /// האם החשיפה פתוחה כרגע (ידנית או אוטומטית)
  bool get isRevealCurrentlyOpen {
    if (revealOpenManually) return true;
    if (autoRevealTimes && revealDate != null && revealStartTime != null && revealEndTime != null) {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      final revealDay = DateTime(revealDate!.year, revealDate!.month, revealDate!.day);
      if (todayDate.isAtSameMomentAs(revealDay)) {
        final startParts = revealStartTime!.split(':');
        final endParts = revealEndTime!.split(':');
        final start = DateTime(now.year, now.month, now.day,
            int.parse(startParts[0]), int.parse(startParts[1]));
        final end = DateTime(now.year, now.month, now.day,
            int.parse(endParts[0]), int.parse(endParts[1]));
        return now.isAfter(start) && now.isBefore(end);
      }
    }
    return false;
  }

  ClusterSettings copyWith({
    int? clusterSize,
    int? clusterSpreadMeters,
    bool? revealOpenManually,
    bool? autoRevealTimes,
    DateTime? revealDate,
    String? revealStartTime,
    String? revealEndTime,
  }) {
    return ClusterSettings(
      clusterSize: clusterSize ?? this.clusterSize,
      clusterSpreadMeters: clusterSpreadMeters ?? this.clusterSpreadMeters,
      revealOpenManually: revealOpenManually ?? this.revealOpenManually,
      autoRevealTimes: autoRevealTimes ?? this.autoRevealTimes,
      revealDate: revealDate ?? this.revealDate,
      revealStartTime: revealStartTime ?? this.revealStartTime,
      revealEndTime: revealEndTime ?? this.revealEndTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clusterSize': clusterSize,
      'clusterSpreadMeters': clusterSpreadMeters,
      'revealOpenManually': revealOpenManually,
      'autoRevealTimes': autoRevealTimes,
      if (revealDate != null) 'revealDate': revealDate!.toIso8601String(),
      if (revealStartTime != null) 'revealStartTime': revealStartTime,
      if (revealEndTime != null) 'revealEndTime': revealEndTime,
    };
  }

  factory ClusterSettings.fromMap(Map<String, dynamic> map) {
    // תאימות קדימה: פורמט ישן עם revealEnabled + revealAfterMinutes
    final oldRevealEnabled = map['revealEnabled'] as bool? ?? false;

    DateTime? revealDate;
    if (map['revealDate'] != null) {
      revealDate = DateTime.tryParse(map['revealDate'] as String);
    }

    return ClusterSettings(
      clusterSize: (map['clusterSize'] as num?)?.toInt() ?? 3,
      clusterSpreadMeters: (map['clusterSpreadMeters'] as num?)?.toInt() ?? 200,
      revealOpenManually: map['revealOpenManually'] as bool? ?? oldRevealEnabled,
      autoRevealTimes: map['autoRevealTimes'] as bool? ?? false,
      revealDate: revealDate,
      revealStartTime: map['revealStartTime'] as String?,
      revealEndTime: map['revealEndTime'] as String?,
    );
  }

  @override
  List<Object?> get props => [clusterSize, clusterSpreadMeters, revealOpenManually, autoRevealTimes, revealDate, revealStartTime, revealEndTime];
}

/// הרכב הכוח — בדד / מאבטח / צמד / חוליה
class ForceComposition extends Equatable {
  final String type; // 'solo', 'guard', 'pair', 'squad'
  final String? swapPointId; // נקודת החלפה גלובלית — רק ל-guard
  final Map<String, List<String>> manualGroups; // שיבוץ ידני (groupId → navigatorIds)
  final Map<String, String> learningRepresentatives; // groupId → navigatorId (נציג למידה)
  final Map<String, String> activeRepresentatives; // groupId → navigatorId (נציג ניווט פעיל)

  const ForceComposition({
    this.type = 'solo',
    this.swapPointId,
    this.manualGroups = const {},
    this.learningRepresentatives = const {},
    this.activeRepresentatives = const {},
  });

  int get baseGroupSize => switch (type) {
    'guard' || 'pair' => 2,
    'squad' => 4,
    _ => 1,
  };

  int get maxGroupSize => switch (type) {
    'guard' || 'pair' => 3,
    'squad' => 5,
    _ => 1,
  };

  bool get isSolo => type == 'solo';
  bool get isGuard => type == 'guard';
  bool get isGrouped => type != 'solo';
  /// צמד/חוליה — קבוצתי "אמיתי" (לא מאבטח, שהוא שני ניווטי בדד רצופים)
  bool get isGroupedPairOrSquad => type == 'pair' || type == 'squad';

  /// נציג למידה לקבוצה
  String? getLearningRepresentative(String? groupId) =>
      groupId != null ? learningRepresentatives[groupId] : null;

  /// נציג ניווט פעיל לקבוצה
  String? getActiveRepresentative(String? groupId) =>
      groupId != null ? activeRepresentatives[groupId] : null;

  /// האם מנווט הוא נציג למידה של הקבוצה
  bool isLearningRepresentative(String? groupId, String navigatorId) =>
      getLearningRepresentative(groupId) == navigatorId;

  /// האם מנווט הוא נציג ניווט פעיל של הקבוצה
  bool isActiveRepresentative(String? groupId, String navigatorId) =>
      getActiveRepresentative(groupId) == navigatorId;

  ForceComposition copyWith({
    String? type,
    String? swapPointId,
    bool clearSwapPointId = false,
    Map<String, List<String>>? manualGroups,
    Map<String, String>? learningRepresentatives,
    bool clearLearningRepresentatives = false,
    Map<String, String>? activeRepresentatives,
    bool clearActiveRepresentatives = false,
  }) {
    return ForceComposition(
      type: type ?? this.type,
      swapPointId: clearSwapPointId ? null : (swapPointId ?? this.swapPointId),
      manualGroups: manualGroups ?? this.manualGroups,
      learningRepresentatives: clearLearningRepresentatives
          ? const {}
          : (learningRepresentatives ?? this.learningRepresentatives),
      activeRepresentatives: clearActiveRepresentatives
          ? const {}
          : (activeRepresentatives ?? this.activeRepresentatives),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (swapPointId != null) 'swapPointId': swapPointId,
      if (manualGroups.isNotEmpty)
        'manualGroups': manualGroups.map((k, v) => MapEntry(k, v)),
      if (learningRepresentatives.isNotEmpty)
        'learningRepresentatives': learningRepresentatives,
      if (activeRepresentatives.isNotEmpty)
        'activeRepresentatives': activeRepresentatives,
    };
  }

  factory ForceComposition.fromMap(Map<String, dynamic> map) {
    return ForceComposition(
      type: map['type'] as String? ?? 'solo',
      swapPointId: map['swapPointId'] as String?,
      manualGroups: map['manualGroups'] is Map
          ? (map['manualGroups'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, List<String>.from(v as List)),
            )
          : const {},
      learningRepresentatives: map['learningRepresentatives'] is Map
          ? (map['learningRepresentatives'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, v as String),
            )
          : const {},
      activeRepresentatives: map['activeRepresentatives'] is Map
          ? (map['activeRepresentatives'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, v as String),
            )
          : const {},
    );
  }

  @override
  List<Object?> get props => [type, swapPointId, manualGroups, learningRepresentatives, activeRepresentatives];
}

/// הגדרות ניווט צנחנים
class ParachuteSettings extends Equatable {
  final List<String> dropPointIds; // נקודות הצנחה — מתוך נ"צ
  final String assignmentMethod; // 'random', 'manual', 'by_sub_framework'
  final Map<String, String> navigatorDropPoints; // navigatorId -> dropPointId (תוצאה סופית)
  final Map<String, List<String>> subFrameworkDropPoints; // sfId -> [dropPointIds] (לשיטת תת-מסגרת)
  final bool samePointPerSubFramework; // כל מנווטי תת-מסגרת באותה נקודה
  final String routeMode; // 'checkpoints' (ברירת מחדל) או 'clusters'

  const ParachuteSettings({
    this.dropPointIds = const [],
    this.assignmentMethod = 'random',
    this.navigatorDropPoints = const {},
    this.subFrameworkDropPoints = const {},
    this.samePointPerSubFramework = false,
    this.routeMode = 'checkpoints',
  });

  ParachuteSettings copyWith({
    List<String>? dropPointIds,
    String? assignmentMethod,
    Map<String, String>? navigatorDropPoints,
    Map<String, List<String>>? subFrameworkDropPoints,
    bool? samePointPerSubFramework,
    String? routeMode,
  }) {
    return ParachuteSettings(
      dropPointIds: dropPointIds ?? this.dropPointIds,
      assignmentMethod: assignmentMethod ?? this.assignmentMethod,
      navigatorDropPoints: navigatorDropPoints ?? this.navigatorDropPoints,
      subFrameworkDropPoints: subFrameworkDropPoints ?? this.subFrameworkDropPoints,
      samePointPerSubFramework: samePointPerSubFramework ?? this.samePointPerSubFramework,
      routeMode: routeMode ?? this.routeMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dropPointIds': dropPointIds,
      'assignmentMethod': assignmentMethod,
      if (navigatorDropPoints.isNotEmpty) 'navigatorDropPoints': navigatorDropPoints,
      if (subFrameworkDropPoints.isNotEmpty)
        'subFrameworkDropPoints': subFrameworkDropPoints.map((k, v) => MapEntry(k, v)),
      'samePointPerSubFramework': samePointPerSubFramework,
      'routeMode': routeMode,
    };
  }

  factory ParachuteSettings.fromMap(Map<String, dynamic> map) {
    return ParachuteSettings(
      dropPointIds: map['dropPointIds'] is List
          ? List<String>.from(map['dropPointIds'] as List)
          : const [],
      assignmentMethod: map['assignmentMethod'] as String? ?? 'random',
      navigatorDropPoints: map['navigatorDropPoints'] is Map
          ? (map['navigatorDropPoints'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, v as String),
            )
          : const {},
      subFrameworkDropPoints: map['subFrameworkDropPoints'] is Map
          ? (map['subFrameworkDropPoints'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, List<String>.from(v as List)),
            )
          : const {},
      samePointPerSubFramework: map['samePointPerSubFramework'] as bool? ?? false,
      routeMode: map['routeMode'] as String? ?? 'checkpoints',
    );
  }

  @override
  List<Object?> get props => [
    dropPointIds, assignmentMethod, navigatorDropPoints,
    subFrameworkDropPoints, samePointPerSubFramework, routeMode,
  ];
}
