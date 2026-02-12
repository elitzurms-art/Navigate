import 'package:equatable/equatable.dart';
import 'coordinate.dart';
import 'navigation_settings.dart';
import 'security_violation.dart';

/// מסלול מוקצה למנווט
class AssignedRoute extends Equatable {
  final List<String> checkpointIds;
  final double routeLengthKm;
  final List<String> sequence;
  final String? startPointId; // נקודת התחלה של הציר
  final String? endPointId; // נקודת הסיום של הציר
  final String status; // 'optimal', 'too_short', 'too_long', 'needs_adjustment'
  final bool isVerified; // האם הציר עבר וידוא
  final String approvalStatus; // 'not_submitted', 'pending_approval', 'approved'
  final List<Coordinate> plannedPath; // נקודות ציר שצייר המנווט

  /// תאימות אחורה — isApproved נגזר מ-approvalStatus
  bool get isApproved => approvalStatus == 'approved';

  const AssignedRoute({
    required this.checkpointIds,
    required this.routeLengthKm,
    required this.sequence,
    this.startPointId,
    this.endPointId,
    this.status = 'optimal',
    this.isVerified = false,
    this.approvalStatus = 'not_submitted',
    this.plannedPath = const [],
  });

  AssignedRoute copyWith({
    List<String>? checkpointIds,
    double? routeLengthKm,
    List<String>? sequence,
    String? startPointId,
    String? endPointId,
    String? status,
    bool? isVerified,
    String? approvalStatus,
    List<Coordinate>? plannedPath,
  }) {
    return AssignedRoute(
      checkpointIds: checkpointIds ?? this.checkpointIds,
      routeLengthKm: routeLengthKm ?? this.routeLengthKm,
      sequence: sequence ?? this.sequence,
      startPointId: startPointId ?? this.startPointId,
      endPointId: endPointId ?? this.endPointId,
      status: status ?? this.status,
      isVerified: isVerified ?? this.isVerified,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      plannedPath: plannedPath ?? this.plannedPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'checkpointIds': checkpointIds,
      'routeLengthKm': routeLengthKm,
      'sequence': sequence,
      if (startPointId != null) 'startPointId': startPointId,
      if (endPointId != null) 'endPointId': endPointId,
      'status': status,
      'isVerified': isVerified,
      'approvalStatus': approvalStatus,
      'isApproved': isApproved, // תאימות אחורה
      if (plannedPath.isNotEmpty)
        'plannedPath': plannedPath.map((c) => c.toMap()).toList(),
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
      status: map['status'] as String? ?? 'optimal',
      isVerified: map['isVerified'] as bool? ?? false,
      approvalStatus: approvalStatus,
      plannedPath: map['plannedPath'] != null
          ? (map['plannedPath'] as List)
              .map((c) => Coordinate.fromMap(c as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [checkpointIds, routeLengthKm, sequence, startPointId, endPointId, status, isVerified, approvalStatus, plannedPath];
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
  bool get isApproval => status == 'approval';
  bool get isReview => status == 'review';

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
      'permissions': permissions.toMap(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Navigation.fromMap(Map<String, dynamic> map) {
    return Navigation(
      id: map['id'] as String,
      name: map['name'] as String,
      status: map['status'] as String,
      createdBy: map['createdBy'] as String,
      treeId: map['treeId'] as String,
      areaId: map['areaId'] as String,
      selectedUnitId: (map['selectedUnitId'] ?? map['frameworkId']) as String?,
      selectedSubFrameworkIds: map['selectedSubFrameworkIds'] != null
          ? List<String>.from(map['selectedSubFrameworkIds'] as List)
          : const [],
      selectedParticipantIds: map['selectedParticipantIds'] != null
          ? List<String>.from(map['selectedParticipantIds'] as List)
          : const [],
      layerNzId: map['layerNzId'] as String,
      layerNbId: map['layerNbId'] as String,
      layerGgId: map['layerGgId'] as String,
      layerBaId: map['layerBaId'] as String?,
      distributionMethod: map['distributionMethod'] as String,
      navigationType: map['navigationType'] as String?,
      executionOrder: map['executionOrder'] as String?,
      routeLengthKm: map['routeLengthKm'] != null
          ? RouteLengthRange.fromMap(map['routeLengthKm'] as Map<String, dynamic>)
          : null,
      checkpointsPerNavigator: map['checkpointsPerNavigator'] as int?,
      startPoint: map['startPoint'] as String?,
      endPoint: map['endPoint'] as String?,
      waypointSettings: map['waypointSettings'] != null
          ? WaypointSettings.fromMap(map['waypointSettings'] as Map<String, dynamic>)
          : const WaypointSettings(),
      boundaryLayerId: map['boundaryLayerId'] as String?,
      safetyTime: map['safetyTime'] != null
          ? SafetyTimeSettings.fromMap(map['safetyTime'] as Map<String, dynamic>)
          : null,
      distributeNow: map['distributeNow'] as bool? ?? false,
      learningSettings: LearningSettings.fromMap(
        map['learningSettings'] as Map<String, dynamic>,
      ),
      verificationSettings: VerificationSettings.fromMap(
        map['verificationSettings'] as Map<String, dynamic>,
      ),
      allowOpenMap: map['allowOpenMap'] as bool? ?? false,
      showSelfLocation: map['showSelfLocation'] as bool? ?? false,
      showRouteOnMap: map['showRouteOnMap'] as bool? ?? false,
      alerts: NavigationAlerts.fromMap(
        map['alerts'] as Map<String, dynamic>,
      ),
      securitySettings: map['securitySettings'] != null
          ? SecuritySettings.fromMap(map['securitySettings'] as Map<String, dynamic>)
          : const SecuritySettings(),
      reviewSettings: map['reviewSettings'] != null
          ? ReviewSettings.fromMap(map['reviewSettings'] as Map<String, dynamic>)
          : const ReviewSettings(),
      displaySettings: DisplaySettings.fromMap(
        map['displaySettings'] as Map<String, dynamic>,
      ),
      routes: (map['routes'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, AssignedRoute.fromMap(v as Map<String, dynamic>)),
      ),
      routesStage: map['routesStage'] as String?,
      routesDistributed: map['routesDistributed'] as bool? ?? false,
      trainingStartTime: map['trainingStartTime'] != null
          ? DateTime.parse(map['trainingStartTime'] as String)
          : null,
      systemCheckStartTime: map['systemCheckStartTime'] != null
          ? DateTime.parse(map['systemCheckStartTime'] as String)
          : null,
      activeStartTime: map['activeStartTime'] != null
          ? DateTime.parse(map['activeStartTime'] as String)
          : null,
      gpsUpdateIntervalSeconds: map['gpsUpdateIntervalSeconds'] as int,
      permissions: NavigationPermissions.fromMap(
        map['permissions'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
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
    permissions,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'Navigation(id: $id, name: $name, status: $status)';
}
