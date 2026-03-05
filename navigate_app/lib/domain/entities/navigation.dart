import 'package:equatable/equatable.dart';
import 'coordinate.dart';
import 'narration_entry.dart';
import 'navigation_settings.dart';
import 'security_violation.dart';
import 'unit_checklist.dart';
import 'variables_sheet.dart';

/// מסלול מוקצה למנווט
class AssignedRoute extends Equatable {
  final List<String> checkpointIds;
  final double routeLengthKm;
  final List<String> sequence;
  final String? startPointId; // נקודת התחלה של הציר
  final String? endPointId; // נקודת הסיום של הציר
  final List<String> waypointIds; // מזהי נקודות ביניים (משותפות לכל המנווטים)
  final String status; // 'optimal', 'too_short', 'too_long', 'needs_adjustment'
  final bool isVerified; // האם הציר עבר וידוא
  final String approvalStatus; // 'not_submitted', 'pending_approval', 'approved', 'rejected'
  final String? rejectionNotes; // הערות פסילה מהמפקד
  final List<Coordinate> plannedPath; // נקודות ציר שצייר המנווט
  final List<NarrationEntry> narrationEntries; // שורות סיפור דרך
  final String? groupId; // מזהה קבוצה (לקישור בין מנווטים באותו ציר)
  final String? segmentType; // 'full', 'first_half', 'second_half' (רלוונטי למאבטח)
  final String? swapPointId; // נקודת ההחלפה (רלוונטי למאבטח)
  final int? manualTimeMinutes; // זמן ידני (דקות) — דורס את החישוב האוטומטי

  /// תאימות אחורה — isApproved נגזר מ-approvalStatus
  bool get isApproved => approvalStatus == 'approved';

  const AssignedRoute({
    required this.checkpointIds,
    required this.routeLengthKm,
    required this.sequence,
    this.startPointId,
    this.endPointId,
    this.waypointIds = const [],
    this.status = 'optimal',
    this.isVerified = false,
    this.approvalStatus = 'not_submitted',
    this.rejectionNotes,
    this.plannedPath = const [],
    this.narrationEntries = const [],
    this.groupId,
    this.segmentType,
    this.swapPointId,
    this.manualTimeMinutes,
  });

  AssignedRoute copyWith({
    List<String>? checkpointIds,
    double? routeLengthKm,
    List<String>? sequence,
    String? startPointId,
    String? endPointId,
    List<String>? waypointIds,
    String? status,
    bool? isVerified,
    String? approvalStatus,
    String? rejectionNotes,
    bool clearRejectionNotes = false,
    List<Coordinate>? plannedPath,
    List<NarrationEntry>? narrationEntries,
    String? groupId,
    String? segmentType,
    String? swapPointId,
    int? manualTimeMinutes,
    bool clearManualTimeMinutes = false,
  }) {
    return AssignedRoute(
      checkpointIds: checkpointIds ?? this.checkpointIds,
      routeLengthKm: routeLengthKm ?? this.routeLengthKm,
      sequence: sequence ?? this.sequence,
      startPointId: startPointId ?? this.startPointId,
      endPointId: endPointId ?? this.endPointId,
      waypointIds: waypointIds ?? this.waypointIds,
      status: status ?? this.status,
      isVerified: isVerified ?? this.isVerified,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      rejectionNotes: clearRejectionNotes ? null : (rejectionNotes ?? this.rejectionNotes),
      plannedPath: plannedPath ?? this.plannedPath,
      narrationEntries: narrationEntries ?? this.narrationEntries,
      groupId: groupId ?? this.groupId,
      segmentType: segmentType ?? this.segmentType,
      swapPointId: swapPointId ?? this.swapPointId,
      manualTimeMinutes: clearManualTimeMinutes ? null : (manualTimeMinutes ?? this.manualTimeMinutes),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'checkpointIds': checkpointIds,
      'routeLengthKm': routeLengthKm,
      'sequence': sequence,
      if (startPointId != null) 'startPointId': startPointId,
      if (endPointId != null) 'endPointId': endPointId,
      if (waypointIds.isNotEmpty) 'waypointIds': waypointIds,
      'status': status,
      'isVerified': isVerified,
      'approvalStatus': approvalStatus,
      'isApproved': isApproved, // תאימות אחורה
      if (rejectionNotes != null) 'rejectionNotes': rejectionNotes,
      if (plannedPath.isNotEmpty)
        'plannedPath': plannedPath.map((c) => c.toMap()).toList(),
      if (narrationEntries.isNotEmpty)
        'narrationEntries': narrationEntries.map((e) => e.toMap()).toList(),
      if (groupId != null) 'groupId': groupId,
      if (segmentType != null) 'segmentType': segmentType,
      if (swapPointId != null) 'swapPointId': swapPointId,
      if (manualTimeMinutes != null) 'manualTimeMinutes': manualTimeMinutes,
    };
  }

  factory AssignedRoute.fromMap(Map<String, dynamic> map) {
    // תאימות אחורה: אם אין approvalStatus, גוזרים מ-isApproved
    final legacyApproved = map['isApproved'] as bool? ?? false;
    final approvalStatus = map['approvalStatus'] as String? ??
        (legacyApproved ? 'approved' : 'not_submitted');

    return AssignedRoute(
      checkpointIds: List<String>.from(map['checkpointIds'] as List),
      routeLengthKm: (map['routeLengthKm'] as num).toDouble(),
      sequence: List<String>.from(map['sequence'] as List),
      startPointId: map['startPointId'] as String?,
      endPointId: map['endPointId'] as String?,
      waypointIds: map['waypointIds'] != null
          ? List<String>.from(map['waypointIds'] as List)
          : const [],
      status: map['status'] as String? ?? 'optimal',
      isVerified: map['isVerified'] as bool? ?? false,
      approvalStatus: approvalStatus,
      rejectionNotes: map['rejectionNotes'] as String?,
      plannedPath: map['plannedPath'] != null
          ? (map['plannedPath'] as List)
              .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
              .toList()
          : const [],
      narrationEntries: map['narrationEntries'] != null
          ? (map['narrationEntries'] as List)
              .map((e) => NarrationEntry.fromMap(e as Map<String, dynamic>))
              .toList()
          : const [],
      groupId: map['groupId'] as String?,
      segmentType: map['segmentType'] as String?,
      swapPointId: map['swapPointId'] as String?,
      manualTimeMinutes: map['manualTimeMinutes'] as int?,
    );
  }

  @override
  List<Object?> get props => [checkpointIds, routeLengthKm, sequence, startPointId, endPointId, waypointIds, status, isVerified, approvalStatus, rejectionNotes, plannedPath, narrationEntries, groupId, segmentType, swapPointId, manualTimeMinutes];
}

/// אפשרות אישור כשחלוקה חורגת מהטווח
class ApprovalOption extends Equatable {
  final String type; // 'expand_range', 'reduce_checkpoints', 'accept_best'
  final String label; // תיאור לתצוגה
  final double? expandedMin; // טווח מורחב (עבור expand_range)
  final double? expandedMax;
  final int? reducedCheckpoints; // כמות מופחתת (עבור reduce_checkpoints)
  final int? outOfRangeCount; // כמות צירים חורגים (עבור accept_best)

  const ApprovalOption({
    required this.type,
    required this.label,
    this.expandedMin,
    this.expandedMax,
    this.reducedCheckpoints,
    this.outOfRangeCount,
  });

  @override
  List<Object?> get props => [type, label, expandedMin, expandedMax, reducedCheckpoints, outOfRangeCount];
}

/// תוצאת חלוקה אוטומטית
class DistributionResult extends Equatable {
  final String status; // 'success', 'needs_approval', 'needs_swap_point'
  final Map<String, AssignedRoute> routes;
  final List<ApprovalOption> approvalOptions;
  final bool hasSharedCheckpoints;
  final int sharedCheckpointCount;
  final ForceComposition? forceComposition; // nullable לתאימות אחורה

  const DistributionResult({
    required this.status,
    required this.routes,
    this.approvalOptions = const [],
    this.hasSharedCheckpoints = false,
    this.sharedCheckpointCount = 0,
    this.forceComposition,
  });

  bool get isSuccess => status == 'success';
  bool get needsApproval => status == 'needs_approval';
  bool get needsSwapPoint => status == 'needs_swap_point';

  @override
  List<Object?> get props => [status, routes, approvalOptions, hasSharedCheckpoints, sharedCheckpointCount, forceComposition];
}

/// טווח אורך מסלול
class RouteLengthRange extends Equatable {
  final double min;
  final double max;

  const RouteLengthRange({
    required this.min,
    required this.max,
  });

  Map<String, dynamic> toMap() {
    return {'min': min, 'max': max};
  }

  factory RouteLengthRange.fromMap(Map<String, dynamic> map) {
    return RouteLengthRange(
      min: (map['min'] as num).toDouble(),
      max: (map['max'] as num).toDouble(),
    );
  }

  @override
  List<Object?> get props => [min, max];
}

/// הרשאות ניווט
class NavigationPermissions extends Equatable {
  final List<String> managers;
  final List<String> viewers;

  const NavigationPermissions({
    required this.managers,
    required this.viewers,
  });

  NavigationPermissions copyWith({
    List<String>? managers,
    List<String>? viewers,
  }) {
    return NavigationPermissions(
      managers: managers ?? this.managers,
      viewers: viewers ?? this.viewers,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'managers': managers,
      'viewers': viewers,
    };
  }

  factory NavigationPermissions.fromMap(Map<String, dynamic> map) {
    return NavigationPermissions(
      managers: map['managers'] != null
          ? List<String>.from(map['managers'] as List)
          : [],
      viewers: map['viewers'] != null
          ? List<String>.from(map['viewers'] as List)
          : [],
    );
  }

  @override
  List<Object?> get props => [managers, viewers];
}

DateTime _parseDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  // Firestore Timestamp: has toDate() method
  if (value != null && value.runtimeType.toString() == 'Timestamp') {
    return (value as dynamic).toDate();
  }
  return DateTime.now();
}

DateTime? _parseDateTimeOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value.runtimeType.toString() == 'Timestamp') {
    return (value as dynamic).toDate();
  }
  return null;
}

/// ישות ניווט
class Navigation extends Equatable {
  final String id;
  final String name;
  final String status;
  final String createdBy;
  final String treeId;
  final String areaId;

  // בחירת יחידה ומשתתפים
  final String? selectedUnitId; // מזהה היחידה שנבחרה
  final List<String> selectedSubFrameworkIds; // מזהי תתי-מסגרות שנבחרו
  final List<String> selectedParticipantIds; // מזהי משתתפים שנבחרו (מתוך תתי-המסגרות)

  // Layers
  final String layerNzId;
  final String layerNbId;
  final String layerGgId;
  final String? layerBaId;

  // Settings - הגדרות שטח ומשתתפים
  final String distributionMethod; // 'automatic', 'manual_app', 'manual_full'
  final String? navigationType; // 'regular', 'clusters', 'star', 'reverse', 'parachute', 'developing'
  final String? executionOrder;
  final RouteLengthRange? routeLengthKm; // טווח מרחק ניווט
  final int? checkpointsPerNavigator;
  final String? startPoint; // נקודת התחלה משותפת לכל המנווטים
  final String? endPoint; // נקודת הסיום משותפת לכל המנווטים
  final WaypointSettings waypointSettings; // הגדרות נקודות ביניים משותפות
  final String? scoringCriterion; // קריטריון חלוקה (fairness, midpoint, uniqueness)
  final String? boundaryLayerId; // גבול גזרה
  final SafetyTimeSettings? safetyTime; // זמן בטיחות
  final bool distributeNow; // האם לחלק נקודות עכשיו

  // הגדרות למידה
  final LearningSettings learningSettings;

  // הגדרות ניווט
  final VerificationSettings verificationSettings;
  final bool allowOpenMap; // אפשר ניווט עם מפה פתוחה
  final bool showSelfLocation; // הצג מיקום עצמי למנווט
  final bool showRouteOnMap; // הצג ציר ניווט על המפה
  final NavigationAlerts alerts; // התראות
  final SecuritySettings securitySettings; // הגדרות אבטחה ונעילה

  // הגדרות תחקיר
  final ReviewSettings reviewSettings;

  // הגדרות תצוגה
  final DisplaySettings displaySettings;

  // Assigned routes
  final Map<String, AssignedRoute> routes;
  final String? routesStage; // 'not_started', 'setup', 'verification', 'editing', 'ready'
  final bool routesDistributed; // האם חולקו צירים

  // Timing
  final DateTime? trainingStartTime;
  final DateTime? systemCheckStartTime;
  final DateTime? activeStartTime;

  // Active settings
  final int gpsUpdateIntervalSeconds;

  // Location sources
  final List<String> enabledPositionSources;

  // Manual position
  final bool allowManualPosition;

  // GPS Spoofing detection
  final bool gpsSpoofingDetectionEnabled;
  final int gpsSpoofingMaxDistanceKm;

  // Force composition (הרכב הכוח)
  final ForceComposition forceComposition;

  // Communication (PTT)
  final CommunicationSettings communicationSettings;

  // Variables sheet (דף משתנים)
  final VariablesSheet? variablesSheet;

  // Checklists completion (צ'קליסטים)
  final ChecklistCompletion? checklistCompletion;

  // Time calculation
  final TimeCalculationSettings timeCalculationSettings;

  // Permissions
  final NavigationPermissions permissions;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Navigation({
    required this.id,
    required this.name,
    required this.status,
    required this.createdBy,
    required this.treeId,
    required this.areaId,
    this.selectedUnitId,
    this.selectedSubFrameworkIds = const [],
    this.selectedParticipantIds = const [],
    required this.layerNzId,
    required this.layerNbId,
    required this.layerGgId,
    this.layerBaId,
    required this.distributionMethod,
    this.navigationType,
    this.executionOrder,
    this.routeLengthKm,
    this.checkpointsPerNavigator,
    this.startPoint,
    this.endPoint,
    this.waypointSettings = const WaypointSettings(),
    this.scoringCriterion,
    this.boundaryLayerId,
    this.safetyTime,
    this.distributeNow = false,
    required this.learningSettings,
    required this.verificationSettings,
    this.allowOpenMap = false,
    this.showSelfLocation = false,
    this.showRouteOnMap = false,
    required this.alerts,
    this.securitySettings = const SecuritySettings(),
    this.reviewSettings = const ReviewSettings(),
    required this.displaySettings,
    required this.routes,
    this.routesStage,
    this.routesDistributed = false,
    this.trainingStartTime,
    this.systemCheckStartTime,
    this.activeStartTime,
    required this.gpsUpdateIntervalSeconds,
    this.enabledPositionSources = const ['gps', 'cellTower', 'pdr', 'pdrCellHybrid'],
    this.allowManualPosition = false,
    this.gpsSpoofingDetectionEnabled = true,
    this.gpsSpoofingMaxDistanceKm = 50,
    this.forceComposition = const ForceComposition(),
    this.communicationSettings = const CommunicationSettings(),
    this.variablesSheet,
    this.checklistCompletion,
    this.timeCalculationSettings = const TimeCalculationSettings(),
    required this.permissions,
    required this.createdAt,
    required this.updatedAt,
  });

  /// בדיקות מצב
  bool get isPreparation => status == 'preparation';
  bool get isReady => status == 'ready';
  bool get isLearning => status == 'learning';
  bool get isWaiting => status == 'waiting';
  bool get isSystemCheck => status == 'system_check';
  bool get isActive => status == 'active';
  bool get isApproval => status == 'approval'; // backward compat — mapped to review
  bool get isReview => status == 'review' || status == 'approval';

  Navigation copyWith({
    String? id,
    String? name,
    String? status,
    String? createdBy,
    String? treeId,
    String? areaId,
    String? selectedUnitId,
    List<String>? selectedSubFrameworkIds,
    List<String>? selectedParticipantIds,
    String? layerNzId,
    String? layerNbId,
    String? layerGgId,
    String? layerBaId,
    String? distributionMethod,
    String? navigationType,
    String? executionOrder,
    RouteLengthRange? routeLengthKm,
    int? checkpointsPerNavigator,
    String? startPoint,
    String? endPoint,
    WaypointSettings? waypointSettings,
    String? scoringCriterion,
    String? boundaryLayerId,
    SafetyTimeSettings? safetyTime,
    bool? distributeNow,
    LearningSettings? learningSettings,
    VerificationSettings? verificationSettings,
    bool? allowOpenMap,
    bool? showSelfLocation,
    bool? showRouteOnMap,
    NavigationAlerts? alerts,
    SecuritySettings? securitySettings,
    ReviewSettings? reviewSettings,
    DisplaySettings? displaySettings,
    Map<String, AssignedRoute>? routes,
    String? routesStage,
    bool? routesDistributed,
    DateTime? trainingStartTime,
    DateTime? systemCheckStartTime,
    DateTime? activeStartTime,
    int? gpsUpdateIntervalSeconds,
    List<String>? enabledPositionSources,
    bool? allowManualPosition,
    bool? gpsSpoofingDetectionEnabled,
    int? gpsSpoofingMaxDistanceKm,
    ForceComposition? forceComposition,
    CommunicationSettings? communicationSettings,
    VariablesSheet? variablesSheet,
    bool clearVariablesSheet = false,
    ChecklistCompletion? checklistCompletion,
    bool clearChecklistCompletion = false,
    TimeCalculationSettings? timeCalculationSettings,
    NavigationPermissions? permissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Navigation(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      treeId: treeId ?? this.treeId,
      areaId: areaId ?? this.areaId,
      selectedUnitId: selectedUnitId ?? this.selectedUnitId,
      selectedSubFrameworkIds: selectedSubFrameworkIds ?? this.selectedSubFrameworkIds,
      selectedParticipantIds: selectedParticipantIds ?? this.selectedParticipantIds,
      layerNzId: layerNzId ?? this.layerNzId,
      layerNbId: layerNbId ?? this.layerNbId,
      layerGgId: layerGgId ?? this.layerGgId,
      layerBaId: layerBaId ?? this.layerBaId,
      distributionMethod: distributionMethod ?? this.distributionMethod,
      navigationType: navigationType ?? this.navigationType,
      executionOrder: executionOrder ?? this.executionOrder,
      routeLengthKm: routeLengthKm ?? this.routeLengthKm,
      checkpointsPerNavigator: checkpointsPerNavigator ?? this.checkpointsPerNavigator,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      waypointSettings: waypointSettings ?? this.waypointSettings,
      scoringCriterion: scoringCriterion ?? this.scoringCriterion,
      boundaryLayerId: boundaryLayerId ?? this.boundaryLayerId,
      safetyTime: safetyTime ?? this.safetyTime,
      distributeNow: distributeNow ?? this.distributeNow,
      learningSettings: learningSettings ?? this.learningSettings,
      verificationSettings: verificationSettings ?? this.verificationSettings,
      allowOpenMap: allowOpenMap ?? this.allowOpenMap,
      showSelfLocation: showSelfLocation ?? this.showSelfLocation,
      showRouteOnMap: showRouteOnMap ?? this.showRouteOnMap,
      alerts: alerts ?? this.alerts,
      securitySettings: securitySettings ?? this.securitySettings,
      reviewSettings: reviewSettings ?? this.reviewSettings,
      displaySettings: displaySettings ?? this.displaySettings,
      routes: routes ?? this.routes,
      routesStage: routesStage ?? this.routesStage,
      routesDistributed: routesDistributed ?? this.routesDistributed,
      trainingStartTime: trainingStartTime ?? this.trainingStartTime,
      systemCheckStartTime: systemCheckStartTime ?? this.systemCheckStartTime,
      activeStartTime: activeStartTime ?? this.activeStartTime,
      gpsUpdateIntervalSeconds: gpsUpdateIntervalSeconds ?? this.gpsUpdateIntervalSeconds,
      enabledPositionSources: enabledPositionSources ?? this.enabledPositionSources,
      allowManualPosition: allowManualPosition ?? this.allowManualPosition,
      gpsSpoofingDetectionEnabled: gpsSpoofingDetectionEnabled ?? this.gpsSpoofingDetectionEnabled,
      gpsSpoofingMaxDistanceKm: gpsSpoofingMaxDistanceKm ?? this.gpsSpoofingMaxDistanceKm,
      forceComposition: forceComposition ?? this.forceComposition,
      communicationSettings: communicationSettings ?? this.communicationSettings,
      variablesSheet: clearVariablesSheet ? null : (variablesSheet ?? this.variablesSheet),
      checklistCompletion: clearChecklistCompletion ? null : (checklistCompletion ?? this.checklistCompletion),
      timeCalculationSettings: timeCalculationSettings ?? this.timeCalculationSettings,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'createdBy': createdBy,
      'treeId': treeId,
      'areaId': areaId,
      if (selectedUnitId != null) 'selectedUnitId': selectedUnitId,
      if (selectedSubFrameworkIds.isNotEmpty) 'selectedSubFrameworkIds': selectedSubFrameworkIds,
      if (selectedParticipantIds.isNotEmpty) 'selectedParticipantIds': selectedParticipantIds,
      'layerNzId': layerNzId,
      'layerNbId': layerNbId,
      'layerGgId': layerGgId,
      if (layerBaId != null) 'layerBaId': layerBaId,
      'distributionMethod': distributionMethod,
      if (navigationType != null) 'navigationType': navigationType,
      if (executionOrder != null) 'executionOrder': executionOrder,
      if (routeLengthKm != null) 'routeLengthKm': routeLengthKm!.toMap(),
      if (checkpointsPerNavigator != null)
        'checkpointsPerNavigator': checkpointsPerNavigator,
      if (startPoint != null) 'startPoint': startPoint,
      if (endPoint != null) 'endPoint': endPoint,
      'waypointSettings': waypointSettings.toMap(),
      if (scoringCriterion != null) 'scoringCriterion': scoringCriterion,
      if (boundaryLayerId != null) 'boundaryLayerId': boundaryLayerId,
      if (safetyTime != null) 'safetyTime': safetyTime!.toMap(),
      'distributeNow': distributeNow,
      'learningSettings': learningSettings.toMap(),
      'verificationSettings': verificationSettings.toMap(),
      'allowOpenMap': allowOpenMap,
      'showSelfLocation': showSelfLocation,
      'showRouteOnMap': showRouteOnMap,
      'alerts': alerts.toMap(),
      'securitySettings': securitySettings.toMap(),
      'reviewSettings': reviewSettings.toMap(),
      'displaySettings': displaySettings.toMap(),
      'routes': routes.map((k, v) => MapEntry(k, v.toMap())),
      if (routesStage != null) 'routesStage': routesStage,
      'routesDistributed': routesDistributed,
      if (trainingStartTime != null)
        'trainingStartTime': trainingStartTime!.toIso8601String(),
      if (systemCheckStartTime != null)
        'systemCheckStartTime': systemCheckStartTime!.toIso8601String(),
      if (activeStartTime != null)
        'activeStartTime': activeStartTime!.toIso8601String(),
      'gpsUpdateIntervalSeconds': gpsUpdateIntervalSeconds,
      'enabledPositionSources': enabledPositionSources,
      'allowManualPosition': allowManualPosition,
      'gpsSpoofingDetectionEnabled': gpsSpoofingDetectionEnabled,
      'gpsSpoofingMaxDistanceKm': gpsSpoofingMaxDistanceKm,
      'forceComposition': forceComposition.toMap(),
      'communicationSettings': communicationSettings.toMap(),
      'timeCalculationSettings': timeCalculationSettings.toMap(),
      'permissions': permissions.toMap(),
      if (variablesSheet != null) 'variablesSheet': variablesSheet!.toMap(),
      if (checklistCompletion != null) 'checklistCompletion': checklistCompletion!.toMap(),
      // Computed field for Firestore security rules — not stored in Drift
      'participants': {
        ...selectedParticipantIds,
        ...permissions.managers,
        createdBy,
      }.toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Navigation.fromMap(Map<String, dynamic> map) {
    return Navigation(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      status: map['status'] as String? ?? 'preparation',
      createdBy: map['createdBy'] as String? ?? '',
      treeId: map['treeId'] as String? ?? '',
      areaId: map['areaId'] as String? ?? '',
      selectedUnitId: (map['selectedUnitId'] ?? map['frameworkId']) as String?,
      selectedSubFrameworkIds: map['selectedSubFrameworkIds'] != null
          ? List<String>.from(map['selectedSubFrameworkIds'] as List)
          : const [],
      selectedParticipantIds: map['selectedParticipantIds'] != null
          ? List<String>.from(map['selectedParticipantIds'] as List)
          : const [],
      layerNzId: map['layerNzId'] as String? ?? '',
      layerNbId: map['layerNbId'] as String? ?? '',
      layerGgId: map['layerGgId'] as String? ?? '',
      layerBaId: map['layerBaId'] as String?,
      distributionMethod: map['distributionMethod'] as String? ?? 'automatic',
      navigationType: map['navigationType'] as String?,
      executionOrder: map['executionOrder'] as String?,
      routeLengthKm: map['routeLengthKm'] is Map
          ? RouteLengthRange.fromMap(map['routeLengthKm'] as Map<String, dynamic>)
          : null,
      checkpointsPerNavigator: map['checkpointsPerNavigator'] as int?,
      startPoint: map['startPoint'] as String?,
      endPoint: map['endPoint'] as String?,
      waypointSettings: map['waypointSettings'] is Map
          ? WaypointSettings.fromMap(map['waypointSettings'] as Map<String, dynamic>)
          : const WaypointSettings(),
      scoringCriterion: map['scoringCriterion'] as String?,
      boundaryLayerId: map['boundaryLayerId'] as String?,
      safetyTime: map['safetyTime'] is Map
          ? SafetyTimeSettings.fromMap(map['safetyTime'] as Map<String, dynamic>)
          : null,
      distributeNow: map['distributeNow'] as bool? ?? false,
      learningSettings: map['learningSettings'] is Map
          ? LearningSettings.fromMap(map['learningSettings'] as Map<String, dynamic>)
          : const LearningSettings(),
      verificationSettings: map['verificationSettings'] is Map
          ? VerificationSettings.fromMap(map['verificationSettings'] as Map<String, dynamic>)
          : const VerificationSettings(autoVerification: false),
      allowOpenMap: map['allowOpenMap'] as bool? ?? false,
      showSelfLocation: map['showSelfLocation'] as bool? ?? false,
      showRouteOnMap: map['showRouteOnMap'] as bool? ?? false,
      alerts: map['alerts'] is Map
          ? NavigationAlerts.fromMap(map['alerts'] as Map<String, dynamic>)
          : const NavigationAlerts(enabled: false),
      securitySettings: map['securitySettings'] is Map
          ? SecuritySettings.fromMap(map['securitySettings'] as Map<String, dynamic>)
          : const SecuritySettings(),
      reviewSettings: map['reviewSettings'] is Map
          ? ReviewSettings.fromMap(map['reviewSettings'] as Map<String, dynamic>)
          : const ReviewSettings(),
      displaySettings: map['displaySettings'] is Map
          ? DisplaySettings.fromMap(map['displaySettings'] as Map<String, dynamic>)
          : const DisplaySettings(),
      routes: map['routes'] is Map
          ? (map['routes'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, AssignedRoute.fromMap(v as Map<String, dynamic>)),
            )
          : const {},
      routesStage: map['routesStage'] as String?,
      routesDistributed: map['routesDistributed'] as bool? ?? false,
      trainingStartTime: _parseDateTimeOrNull(map['trainingStartTime']),
      systemCheckStartTime: _parseDateTimeOrNull(map['systemCheckStartTime']),
      activeStartTime: _parseDateTimeOrNull(map['activeStartTime']),
      gpsUpdateIntervalSeconds: map['gpsUpdateIntervalSeconds'] as int? ?? 5,
      enabledPositionSources: (map['enabledPositionSources'] as List?)?.cast<String>() ?? const ['gps', 'cellTower', 'pdr', 'pdrCellHybrid'],
      allowManualPosition: map['allowManualPosition'] as bool? ?? false,
      gpsSpoofingDetectionEnabled: map['gpsSpoofingDetectionEnabled'] as bool? ?? true,
      gpsSpoofingMaxDistanceKm: (map['gpsSpoofingMaxDistanceKm'] as num?)?.toInt() ?? 50,
      forceComposition: map['forceComposition'] is Map
          ? ForceComposition.fromMap(map['forceComposition'] as Map<String, dynamic>)
          : const ForceComposition(),
      communicationSettings: map['communicationSettings'] is Map
          ? CommunicationSettings.fromMap(map['communicationSettings'] as Map<String, dynamic>)
          : const CommunicationSettings(),
      variablesSheet: map['variablesSheet'] is Map
          ? VariablesSheet.fromMap(map['variablesSheet'] as Map<String, dynamic>)
          : null,
      checklistCompletion: map['checklistCompletion'] is Map
          ? ChecklistCompletion.fromMap(map['checklistCompletion'] as Map<String, dynamic>)
          : null,
      timeCalculationSettings: map['timeCalculationSettings'] is Map
          ? TimeCalculationSettings.fromMap(map['timeCalculationSettings'] as Map<String, dynamic>)
          : const TimeCalculationSettings(),
      permissions: map['permissions'] is Map
          ? NavigationPermissions.fromMap(map['permissions'] as Map<String, dynamic>)
          : const NavigationPermissions(managers: [], viewers: []),
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    status,
    createdBy,
    treeId,
    areaId,
    selectedUnitId,
    selectedSubFrameworkIds,
    selectedParticipantIds,
    layerNzId,
    layerNbId,
    layerGgId,
    layerBaId,
    distributionMethod,
    navigationType,
    executionOrder,
    routeLengthKm,
    checkpointsPerNavigator,
    startPoint,
    endPoint,
    waypointSettings,
    scoringCriterion,
    boundaryLayerId,
    safetyTime,
    distributeNow,
    learningSettings,
    verificationSettings,
    allowOpenMap,
    showSelfLocation,
    showRouteOnMap,
    alerts,
    securitySettings,
    reviewSettings,
    displaySettings,
    routes,
    routesStage,
    routesDistributed,
    trainingStartTime,
    systemCheckStartTime,
    activeStartTime,
    gpsUpdateIntervalSeconds,
    enabledPositionSources,
    allowManualPosition,
    gpsSpoofingDetectionEnabled,
    gpsSpoofingMaxDistanceKm,
    forceComposition,
    communicationSettings,
    variablesSheet,
    checklistCompletion,
    timeCalculationSettings,
    permissions,
    createdAt,
    updatedAt,
  ];

  /// Sorts navigator IDs by force composition groups and execution order.
  /// For pair/squad: groups together. For guard: first_half before second_half.
  List<String> sortByGroup(Iterable<String> navigatorIds) {
    final ids = navigatorIds.toList();
    if (forceComposition.isSolo) return ids;

    final sortedGroupIds = routes.values
        .where((r) => r.groupId != null)
        .map((r) => r.groupId!)
        .toSet()
        .toList()
      ..sort();

    ids.sort((a, b) {
      final groupA = routes[a]?.groupId;
      final groupB = routes[b]?.groupId;
      if (groupA == null && groupB == null) return 0;
      if (groupA == null) return 1;
      if (groupB == null) return -1;
      final cmp = sortedGroupIds.indexOf(groupA).compareTo(sortedGroupIds.indexOf(groupB));
      if (cmp != 0) return cmp;
      if (forceComposition.isGuard) {
        const segOrder = {'first_half': 0, 'full': 1, 'second_half': 2};
        return (segOrder[routes[a]?.segmentType] ?? 1)
            .compareTo(segOrder[routes[b]?.segmentType] ?? 1);
      }
      return 0;
    });
    return ids;
  }

  @override
  String toString() => 'Navigation(id: $id, name: $name, status: $status)';
}
