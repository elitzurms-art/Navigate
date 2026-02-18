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

  const VerificationSettings({
    required this.autoVerification,
    this.verificationType,
    this.approvalDistance,
    this.scoreRanges,
  });

  VerificationSettings copyWith({
    bool? autoVerification,
    String? verificationType,
    int? approvalDistance,
    List<DistanceScoreRange>? scoreRanges,
  }) {
    return VerificationSettings(
      autoVerification: autoVerification ?? this.autoVerification,
      verificationType: verificationType ?? this.verificationType,
      approvalDistance: approvalDistance ?? this.approvalDistance,
      scoreRanges: scoreRanges ?? this.scoreRanges,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'autoVerification': autoVerification,
      if (verificationType != null) 'verificationType': verificationType,
      if (approvalDistance != null) 'approvalDistance': approvalDistance,
      if (scoreRanges != null)
        'scoreRanges': scoreRanges!.map((r) => r.toMap()).toList(),
    };
  }

  factory VerificationSettings.fromMap(Map<String, dynamic> map) {
    return VerificationSettings(
      autoVerification: map['autoVerification'] as bool? ?? false,
      verificationType: map['verificationType'] as String?,
      approvalDistance: map['approvalDistance'] as int?,
      scoreRanges: map['scoreRanges'] != null
          ? (map['scoreRanges'] as List)
              .map((r) => DistanceScoreRange.fromMap(r as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  @override
  List<Object?> get props => [
        autoVerification,
        verificationType,
        approvalDistance,
        scoreRanges,
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
    );
  }

  @override
  List<Object?> get props => [
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
      checkpointWeights: map['checkpointWeights'] != null
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

  const DisplaySettings({
    this.defaultMap,
    this.openingLat,
    this.openingLng,
    this.activeLayers,
    this.layerOpacity,
  });

  DisplaySettings copyWith({
    String? defaultMap,
    double? openingLat,
    double? openingLng,
    Map<String, bool>? activeLayers,
    Map<String, double>? layerOpacity,
  }) {
    return DisplaySettings(
      defaultMap: defaultMap ?? this.defaultMap,
      openingLat: openingLat ?? this.openingLat,
      openingLng: openingLng ?? this.openingLng,
      activeLayers: activeLayers ?? this.activeLayers,
      layerOpacity: layerOpacity ?? this.layerOpacity,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (defaultMap != null) 'defaultMap': defaultMap,
      if (openingLat != null) 'openingLat': openingLat,
      if (openingLng != null) 'openingLng': openingLng,
      if (activeLayers != null) 'activeLayers': activeLayers,
      if (layerOpacity != null) 'layerOpacity': layerOpacity,
    };
  }

  factory DisplaySettings.fromMap(Map<String, dynamic> map) {
    return DisplaySettings(
      defaultMap: map['defaultMap'] as String?,
      openingLat: map['openingLat'] as double?,
      openingLng: map['openingLng'] as double?,
      activeLayers: map['activeLayers'] != null
          ? Map<String, bool>.from(map['activeLayers'] as Map)
          : null,
      layerOpacity: map['layerOpacity'] != null
          ? (map['layerOpacity'] as Map).map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()))
          : null,
    );
  }

  @override
  List<Object?> get props => [
        defaultMap,
        openingLat,
        openingLng,
        activeLayers,
        layerOpacity,
      ];
}

/// הגדרות חישוב זמני ניווט
class TimeCalculationSettings extends Equatable {
  final bool enabled;           // טוגל (default: true)
  final bool isHeavyLoad;       // מעל 40% משקל גוף
  final bool isNightNavigation; // ניווט לילה
  final bool isSummer;          // קיץ (true) / חורף (false)

  const TimeCalculationSettings({
    this.enabled = true,
    this.isHeavyLoad = false,
    this.isNightNavigation = false,
    this.isSummer = true,
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
  }) {
    return TimeCalculationSettings(
      enabled: enabled ?? this.enabled,
      isHeavyLoad: isHeavyLoad ?? this.isHeavyLoad,
      isNightNavigation: isNightNavigation ?? this.isNightNavigation,
      isSummer: isSummer ?? this.isSummer,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'isHeavyLoad': isHeavyLoad,
      'isNightNavigation': isNightNavigation,
      'isSummer': isSummer,
    };
  }

  factory TimeCalculationSettings.fromMap(Map<String, dynamic> map) {
    return TimeCalculationSettings(
      enabled: map['enabled'] as bool? ?? true,
      isHeavyLoad: map['isHeavyLoad'] as bool? ?? false,
      isNightNavigation: map['isNightNavigation'] as bool? ?? false,
      isSummer: map['isSummer'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [enabled, isHeavyLoad, isNightNavigation, isSummer];
}

/// הגדרות תקשורת (ווקי טוקי)
class CommunicationSettings extends Equatable {
  final bool walkieTalkieEnabled;

  const CommunicationSettings({
    this.walkieTalkieEnabled = false,
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
      walkieTalkieEnabled: map['walkieTalkieEnabled'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [walkieTalkieEnabled];
}

/// נקודת ביניים - נ.צ. שכולם עוברים בה
class WaypointCheckpoint extends Equatable {
  final String checkpointId; // מזהה נקודת הציון
  final String placementType; // 'distance' או 'between_checkpoints'

  // עבור placementType == 'distance'
  final double? afterDistanceKm; // לעבור בה אחרי מרחק מסוים

  // עבור placementType == 'between_checkpoints'
  final int? afterCheckpointIndex; // לעבור בה אחרי נקודת ציון מסוימת (0-based)
  final int? beforeCheckpointIndex; // לעבור בה לפני נקודת ציון מסוימת (0-based)

  const WaypointCheckpoint({
    required this.checkpointId,
    required this.placementType,
    this.afterDistanceKm,
    this.afterCheckpointIndex,
    this.beforeCheckpointIndex,
  });

  WaypointCheckpoint copyWith({
    String? checkpointId,
    String? placementType,
    double? afterDistanceKm,
    int? afterCheckpointIndex,
    int? beforeCheckpointIndex,
  }) {
    return WaypointCheckpoint(
      checkpointId: checkpointId ?? this.checkpointId,
      placementType: placementType ?? this.placementType,
      afterDistanceKm: afterDistanceKm ?? this.afterDistanceKm,
      afterCheckpointIndex: afterCheckpointIndex ?? this.afterCheckpointIndex,
      beforeCheckpointIndex: beforeCheckpointIndex ?? this.beforeCheckpointIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'checkpointId': checkpointId,
      'placementType': placementType,
      if (afterDistanceKm != null) 'afterDistanceKm': afterDistanceKm,
      if (afterCheckpointIndex != null) 'afterCheckpointIndex': afterCheckpointIndex,
      if (beforeCheckpointIndex != null) 'beforeCheckpointIndex': beforeCheckpointIndex,
    };
  }

  factory WaypointCheckpoint.fromMap(Map<String, dynamic> map) {
    return WaypointCheckpoint(
      checkpointId: map['checkpointId'] as String,
      placementType: map['placementType'] as String,
      afterDistanceKm: map['afterDistanceKm'] as double?,
      afterCheckpointIndex: map['afterCheckpointIndex'] as int?,
      beforeCheckpointIndex: map['beforeCheckpointIndex'] as int?,
    );
  }

  @override
  List<Object?> get props => [checkpointId, placementType, afterDistanceKm, afterCheckpointIndex, beforeCheckpointIndex];
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
