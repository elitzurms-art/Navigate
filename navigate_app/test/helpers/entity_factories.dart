import 'package:latlong2/latlong.dart';
import 'package:navigate_app/domain/entities/user.dart';
import 'package:navigate_app/domain/entities/unit.dart';
import 'package:navigate_app/domain/entities/navigation.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';
import 'package:navigate_app/domain/entities/checkpoint.dart';
import 'package:navigate_app/domain/entities/checkpoint_punch.dart';
import 'package:navigate_app/domain/entities/boundary.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';
import 'package:navigate_app/domain/entities/security_violation.dart';
import 'package:navigate_app/domain/entities/navigation_score.dart';
import 'package:navigate_app/domain/entities/navigation_tree.dart';
import 'package:navigate_app/domain/entities/unit_checklist.dart';
import 'package:navigate_app/domain/entities/navigator_status.dart';
import 'package:navigate_app/domain/entities/commander_location.dart';
import 'package:navigate_app/domain/entities/navigation_doc_snapshot.dart';

final _now = DateTime(2026, 2, 15, 10, 0, 0);

User createTestUser({
  String uid = '1234567',
  String firstName = 'ישראל',
  String lastName = 'ישראלי',
  String phoneNumber = '0501234567',
  bool phoneVerified = true,
  String email = '',
  bool emailVerified = false,
  String role = 'navigator',
  String? unitId = 'unit-1',
  String? fcmToken,
  String? firebaseUid,
  String? approvalStatus = 'approved',
  DateTime? soloQuizPassedAt,
  int? soloQuizScore,
  DateTime? commanderQuizPassedAt,
  int? commanderQuizScore,
  String? activeSessionId,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return User(
    uid: uid,
    firstName: firstName,
    lastName: lastName,
    phoneNumber: phoneNumber,
    phoneVerified: phoneVerified,
    email: email,
    emailVerified: emailVerified,
    role: role,
    unitId: unitId,
    fcmToken: fcmToken,
    firebaseUid: firebaseUid,
    approvalStatus: approvalStatus,
    soloQuizPassedAt: soloQuizPassedAt,
    soloQuizScore: soloQuizScore,
    commanderQuizPassedAt: commanderQuizPassedAt,
    commanderQuizScore: commanderQuizScore,
    activeSessionId: activeSessionId,
    createdAt: createdAt ?? _now,
    updatedAt: updatedAt ?? _now,
  );
}

Unit createTestUnit({
  String id = 'unit-1',
  String name = 'פלוגה א',
  String description = '',
  String type = 'company',
  String? parentUnitId,
  List<String> managerIds = const ['1234567'],
  String createdBy = '1234567',
  DateTime? createdAt,
  DateTime? updatedAt,
  bool isClassified = false,
  int? level = 4,
  bool isNavigators = false,
  bool isGeneral = false,
  List<UnitChecklist> checklists = const [],
}) {
  return Unit(
    id: id,
    name: name,
    description: description,
    type: type,
    parentUnitId: parentUnitId,
    managerIds: managerIds,
    createdBy: createdBy,
    createdAt: createdAt ?? _now,
    updatedAt: updatedAt ?? _now,
    isClassified: isClassified,
    level: level,
    isNavigators: isNavigators,
    isGeneral: isGeneral,
    checklists: checklists,
  );
}

Checkpoint createTestCheckpoint({
  String id = 'cp-1',
  String areaId = 'area-1',
  String? boundaryId,
  String name = 'נקודה 1',
  String description = '',
  String type = 'checkpoint',
  String color = 'blue',
  String geometryType = 'point',
  Coordinate? coordinates,
  List<Coordinate>? polygonCoordinates,
  int sequenceNumber = 1,
  List<String> labels = const [],
  String createdBy = '1234567',
  DateTime? createdAt,
}) {
  return Checkpoint(
    id: id,
    areaId: areaId,
    boundaryId: boundaryId,
    name: name,
    description: description,
    type: type,
    color: color,
    geometryType: geometryType,
    coordinates: coordinates ?? const Coordinate(lat: 31.5, lng: 34.8, utm: '640000450000'),
    polygonCoordinates: polygonCoordinates,
    sequenceNumber: sequenceNumber,
    labels: labels,
    createdBy: createdBy,
    createdAt: createdAt ?? _now,
  );
}

CheckpointPunch createTestCheckpointPunch({
  String id = 'punch-1',
  String navigationId = 'nav-1',
  String navigatorId = '1234567',
  String checkpointId = 'cp-1',
  Coordinate? punchLocation,
  DateTime? punchTime,
  PunchStatus status = PunchStatus.active,
  double? distanceFromCheckpoint,
  String? rejectionReason,
  DateTime? approvalTime,
  String? approvedBy,
  int? punchIndex,
  String? supersededByPunchId,
}) {
  return CheckpointPunch(
    id: id,
    navigationId: navigationId,
    navigatorId: navigatorId,
    checkpointId: checkpointId,
    punchLocation: punchLocation ?? const Coordinate(lat: 31.5, lng: 34.8, utm: '640000450000'),
    punchTime: punchTime ?? _now,
    status: status,
    distanceFromCheckpoint: distanceFromCheckpoint,
    rejectionReason: rejectionReason,
    approvalTime: approvalTime,
    approvedBy: approvedBy,
    punchIndex: punchIndex,
    supersededByPunchId: supersededByPunchId,
  );
}

Boundary createTestBoundary({
  String id = 'boundary-1',
  String areaId = 'area-1',
  String name = 'גבול גזרה',
  String description = '',
  List<Coordinate>? coordinates,
  String color = 'black',
  double strokeWidth = 3.0,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return Boundary(
    id: id,
    areaId: areaId,
    name: name,
    description: description,
    coordinates: coordinates ?? const [
      Coordinate(lat: 31.0, lng: 34.0, utm: '600000430000'),
      Coordinate(lat: 31.0, lng: 35.0, utm: '700000430000'),
      Coordinate(lat: 32.0, lng: 35.0, utm: '700000540000'),
      Coordinate(lat: 32.0, lng: 34.0, utm: '600000540000'),
    ],
    color: color,
    strokeWidth: strokeWidth,
    createdAt: createdAt ?? _now,
    updatedAt: updatedAt ?? _now,
  );
}

Coordinate createTestCoordinate({
  double lat = 31.5,
  double lng = 34.8,
  String utm = '640000450000',
}) {
  return Coordinate(lat: lat, lng: lng, utm: utm);
}

SecurityViolation createTestSecurityViolation({
  String id = 'violation-1',
  String navigationId = 'nav-1',
  String navigatorId = '1234567',
  ViolationType type = ViolationType.exitLockTask,
  ViolationSeverity severity = ViolationSeverity.high,
  String description = 'חריגת אבטחה',
  DateTime? timestamp,
  Map<String, dynamic>? metadata,
}) {
  return SecurityViolation(
    id: id,
    navigationId: navigationId,
    navigatorId: navigatorId,
    type: type,
    severity: severity,
    description: description,
    timestamp: timestamp ?? _now,
    metadata: metadata,
  );
}

NavigationScore createTestNavigationScore({
  String id = 'score-1',
  String navigationId = 'nav-1',
  String navigatorId = '1234567',
  int totalScore = 85,
  Map<String, CheckpointScore>? checkpointScores,
  Map<String, int> customCriteriaScores = const {},
  DateTime? calculatedAt,
  bool isManual = false,
  String? notes,
  bool isPublished = false,
  DateTime? publishedAt,
}) {
  return NavigationScore(
    id: id,
    navigationId: navigationId,
    navigatorId: navigatorId,
    totalScore: totalScore,
    checkpointScores: checkpointScores ?? const {},
    customCriteriaScores: customCriteriaScores,
    calculatedAt: calculatedAt ?? _now,
    isManual: isManual,
    notes: notes,
    isPublished: isPublished,
    publishedAt: publishedAt,
  );
}

NavigationTree createTestNavigationTree({
  String id = 'tree-1',
  String name = 'עץ ניווט',
  List<SubFramework>? subFrameworks,
  String createdBy = '1234567',
  DateTime? createdAt,
  DateTime? updatedAt,
  String? treeType,
  String? sourceTreeId,
  String? unitId = 'unit-1',
}) {
  return NavigationTree(
    id: id,
    name: name,
    subFrameworks: subFrameworks ?? [
      createTestSubFramework(),
    ],
    createdBy: createdBy,
    createdAt: createdAt ?? _now,
    updatedAt: updatedAt ?? _now,
    treeType: treeType,
    sourceTreeId: sourceTreeId,
    unitId: unitId,
  );
}

SubFramework createTestSubFramework({
  String id = 'sf-1',
  String name = 'מפקדים',
  List<String> userIds = const ['1234567'],
  Map<String, String> userLevels = const {},
  String? navigatorType,
  bool isFixed = true,
  String? unitId = 'unit-1',
}) {
  return SubFramework(
    id: id,
    name: name,
    userIds: userIds,
    userLevels: userLevels,
    navigatorType: navigatorType,
    isFixed: isFixed,
    unitId: unitId,
  );
}

/// Builds a minimal Navigation map with all required fields.
/// Promoted from navigation_entities_test.dart.
Map<String, dynamic> buildMinimalNavigationMap([
  Map<String, dynamic> overrides = const {},
]) {
  final base = <String, dynamic>{
    'id': 'nav-001',
    'name': '',
    'status': 'preparation',
    'createdBy': '',
    'treeId': '',
    'areaId': '',
    'layerNzId': '',
    'layerNbId': '',
    'layerGgId': '',
    'distributionMethod': 'automatic',
    'learningSettings': const LearningSettings().toMap(),
    'verificationSettings':
        const VerificationSettings(autoVerification: false).toMap(),
    'alerts': const NavigationAlerts(enabled: false).toMap(),
    'displaySettings': const DisplaySettings().toMap(),
    'routes': <String, dynamic>{},
    'permissions': const NavigationPermissions(
      managers: [],
      viewers: [],
    ).toMap(),
    'gpsUpdateIntervalSeconds': 30,
    'gpsSyncIntervalSeconds': 30,
    'createdAt': _now.toIso8601String(),
    'updatedAt': _now.toIso8601String(),
  };
  base.addAll(overrides);
  return base;
}

NavigatorStatus createTestNavigatorStatus({
  bool isConnected = true,
  bool hasReported = true,
  int batteryLevel = 85,
  bool hasGPS = true,
  int receptionLevel = 3,
  double? latitude = 31.5,
  double? longitude = 34.8,
  String positionSource = 'gps',
  DateTime? positionUpdatedAt,
  double gpsAccuracy = 5.0,
  String mapsStatus = 'completed',
  bool hasMicrophonePermission = true,
  bool hasPhonePermission = true,
  bool hasDNDPermission = true,
}) {
  return NavigatorStatus(
    isConnected: isConnected,
    hasReported: hasReported,
    batteryLevel: batteryLevel,
    hasGPS: hasGPS,
    receptionLevel: receptionLevel,
    latitude: latitude,
    longitude: longitude,
    positionSource: positionSource,
    positionUpdatedAt: positionUpdatedAt ?? _now,
    gpsAccuracy: gpsAccuracy,
    mapsStatus: mapsStatus,
    hasMicrophonePermission: hasMicrophonePermission,
    hasPhonePermission: hasPhonePermission,
    hasDNDPermission: hasDNDPermission,
  );
}

CommanderLocation createTestCommanderLocation({
  String userId = '7654321',
  String name = 'מפקד א',
  double latitude = 31.5,
  double longitude = 34.8,
  DateTime? lastUpdate,
}) {
  return CommanderLocation(
    userId: userId,
    name: name,
    position: LatLng(latitude, longitude),
    lastUpdate: lastUpdate ?? _now,
  );
}

NavigationDocSnapshot createTestNavigationDocSnapshot({
  String id = 'nav-001',
  Navigation? navigation,
  bool emergencyActive = false,
  int emergencyMode = 0,
  String? activeBroadcastId,
  String? cancelBroadcastId,
}) {
  return NavigationDocSnapshot(
    id: id,
    navigation: navigation,
    emergencyActive: emergencyActive,
    emergencyMode: emergencyMode,
    activeBroadcastId: activeBroadcastId,
    cancelBroadcastId: cancelBroadcastId,
  );
}
