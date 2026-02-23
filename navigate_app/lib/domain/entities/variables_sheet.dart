import 'package:equatable/equatable.dart';

/// שורת לוח זמנים הכנה (סעיף 2)
class PreparationScheduleRow extends Equatable {
  final String? preparationType;
  final String? executionDate;
  final String? notes;

  const PreparationScheduleRow({
    this.preparationType,
    this.executionDate,
    this.notes,
  });

  PreparationScheduleRow copyWith({
    String? preparationType,
    String? executionDate,
    String? notes,
    bool clearPreparationType = false,
    bool clearExecutionDate = false,
    bool clearNotes = false,
  }) {
    return PreparationScheduleRow(
      preparationType: clearPreparationType ? null : (preparationType ?? this.preparationType),
      executionDate: clearExecutionDate ? null : (executionDate ?? this.executionDate),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (preparationType != null) 'preparationType': preparationType,
      if (executionDate != null) 'executionDate': executionDate,
      if (notes != null) 'notes': notes,
    };
  }

  factory PreparationScheduleRow.fromMap(Map<String, dynamic> map) {
    return PreparationScheduleRow(
      preparationType: map['preparationType'] as String?,
      executionDate: map['executionDate'] as String?,
      notes: map['notes'] as String?,
    );
  }

  bool get isEmpty => preparationType == null && executionDate == null && notes == null;

  @override
  List<Object?> get props => [preparationType, executionDate, notes];
}

/// שורת בדיקת מערכות (סעיף 10)
class SystemCheckRow extends Equatable {
  final String? systemName;
  final bool? checkPerformed;
  final bool? findingsOk;
  final String? gpsReception;

  const SystemCheckRow({
    this.systemName,
    this.checkPerformed,
    this.findingsOk,
    this.gpsReception,
  });

  SystemCheckRow copyWith({
    String? systemName,
    bool? checkPerformed,
    bool? findingsOk,
    String? gpsReception,
    bool clearSystemName = false,
    bool clearGpsReception = false,
  }) {
    return SystemCheckRow(
      systemName: clearSystemName ? null : (systemName ?? this.systemName),
      checkPerformed: checkPerformed ?? this.checkPerformed,
      findingsOk: findingsOk ?? this.findingsOk,
      gpsReception: clearGpsReception ? null : (gpsReception ?? this.gpsReception),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (systemName != null) 'systemName': systemName,
      if (checkPerformed != null) 'checkPerformed': checkPerformed,
      if (findingsOk != null) 'findingsOk': findingsOk,
      if (gpsReception != null) 'gpsReception': gpsReception,
    };
  }

  factory SystemCheckRow.fromMap(Map<String, dynamic> map) {
    return SystemCheckRow(
      systemName: map['systemName'] as String?,
      checkPerformed: map['checkPerformed'] as bool?,
      findingsOk: map['findingsOk'] as bool?,
      gpsReception: map['gpsReception'] as String?,
    );
  }

  @override
  List<Object?> get props => [systemName, checkPerformed, findingsOk, gpsReception];
}

/// שורת תקשורת (סעיף 11)
class CommunicationRow extends Equatable {
  final String? networkType;
  final String? networkName;
  final String? frequency;

  const CommunicationRow({
    this.networkType,
    this.networkName,
    this.frequency,
  });

  CommunicationRow copyWith({
    String? networkType,
    String? networkName,
    String? frequency,
    bool clearNetworkType = false,
    bool clearNetworkName = false,
    bool clearFrequency = false,
  }) {
    return CommunicationRow(
      networkType: clearNetworkType ? null : (networkType ?? this.networkType),
      networkName: clearNetworkName ? null : (networkName ?? this.networkName),
      frequency: clearFrequency ? null : (frequency ?? this.frequency),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (networkType != null) 'networkType': networkType,
      if (networkName != null) 'networkName': networkName,
      if (frequency != null) 'frequency': frequency,
    };
  }

  factory CommunicationRow.fromMap(Map<String, dynamic> map) {
    return CommunicationRow(
      networkType: map['networkType'] as String?,
      networkName: map['networkName'] as String?,
      frequency: map['frequency'] as String?,
    );
  }

  bool get isEmpty => networkType == null && networkName == null && frequency == null;

  @override
  List<Object?> get props => [networkType, networkName, frequency];
}

/// שורת כוחות שכנים (סעיף 12)
class NeighboringForceRow extends Equatable {
  final String? forceName;
  final String? location;
  final String? distance;
  final String? direction;
  final String? trainingType;
  final String? notes;

  const NeighboringForceRow({
    this.forceName,
    this.location,
    this.distance,
    this.direction,
    this.trainingType,
    this.notes,
  });

  NeighboringForceRow copyWith({
    String? forceName,
    String? location,
    String? distance,
    String? direction,
    String? trainingType,
    String? notes,
  }) {
    return NeighboringForceRow(
      forceName: forceName ?? this.forceName,
      location: location ?? this.location,
      distance: distance ?? this.distance,
      direction: direction ?? this.direction,
      trainingType: trainingType ?? this.trainingType,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (forceName != null) 'forceName': forceName,
      if (location != null) 'location': location,
      if (distance != null) 'distance': distance,
      if (direction != null) 'direction': direction,
      if (trainingType != null) 'trainingType': trainingType,
      if (notes != null) 'notes': notes,
    };
  }

  factory NeighboringForceRow.fromMap(Map<String, dynamic> map) {
    return NeighboringForceRow(
      forceName: map['forceName'] as String?,
      location: map['location'] as String?,
      distance: map['distance'] as String?,
      direction: map['direction'] as String?,
      trainingType: map['trainingType'] as String?,
      notes: map['notes'] as String?,
    );
  }

  bool get isEmpty => forceName == null && location == null && distance == null;

  @override
  List<Object?> get props => [forceName, location, distance, direction, trainingType, notes];
}

/// שורת נתונים נוספים (סעיף 17)
class AdditionalDataRow extends Equatable {
  final String? navigationPhase;
  final String? dataItem;
  final String? preventionActivity;

  const AdditionalDataRow({
    this.navigationPhase,
    this.dataItem,
    this.preventionActivity,
  });

  AdditionalDataRow copyWith({
    String? navigationPhase,
    String? dataItem,
    String? preventionActivity,
  }) {
    return AdditionalDataRow(
      navigationPhase: navigationPhase ?? this.navigationPhase,
      dataItem: dataItem ?? this.dataItem,
      preventionActivity: preventionActivity ?? this.preventionActivity,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (navigationPhase != null) 'navigationPhase': navigationPhase,
      if (dataItem != null) 'dataItem': dataItem,
      if (preventionActivity != null) 'preventionActivity': preventionActivity,
    };
  }

  factory AdditionalDataRow.fromMap(Map<String, dynamic> map) {
    return AdditionalDataRow(
      navigationPhase: map['navigationPhase'] as String?,
      dataItem: map['dataItem'] as String?,
      preventionActivity: map['preventionActivity'] as String?,
    );
  }

  bool get isEmpty => navigationPhase == null && dataItem == null && preventionActivity == null;

  @override
  List<Object?> get props => [navigationPhase, dataItem, preventionActivity];
}

/// נתוני חתימה דיגיטלית (סעיפים 23-24)
class SignatureData extends Equatable {
  final String? name;
  final String? rank;
  final String? role;
  final String? date;
  final String? signatureBase64; // PNG base64

  const SignatureData({
    this.name,
    this.rank,
    this.role,
    this.date,
    this.signatureBase64,
  });

  SignatureData copyWith({
    String? name,
    String? rank,
    String? role,
    String? date,
    String? signatureBase64,
    bool clearSignature = false,
  }) {
    return SignatureData(
      name: name ?? this.name,
      rank: rank ?? this.rank,
      role: role ?? this.role,
      date: date ?? this.date,
      signatureBase64: clearSignature ? null : (signatureBase64 ?? this.signatureBase64),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (name != null) 'name': name,
      if (rank != null) 'rank': rank,
      if (role != null) 'role': role,
      if (date != null) 'date': date,
      if (signatureBase64 != null) 'signatureBase64': signatureBase64,
    };
  }

  factory SignatureData.fromMap(Map<String, dynamic> map) {
    return SignatureData(
      name: map['name'] as String?,
      rank: map['rank'] as String?,
      role: map['role'] as String?,
      date: map['date'] as String?,
      signatureBase64: map['signatureBase64'] as String?,
    );
  }

  bool get hasSigned => signatureBase64 != null && signatureBase64!.isNotEmpty;

  @override
  List<Object?> get props => [name, rank, role, date, signatureBase64];
}

/// דף משתנים לניווט — נספח 24
class VariablesSheet extends Equatable {
  // ===== עמוד 1 — סעיפים 1-9 =====

  // סעיף 1 — הכנה מקדימה
  final String? preliminaryTraining;
  final bool? medicCheckDone;
  final String? medicCheckNotes;
  final bool? weightCheckDone;
  final String? weightCheckNotes;
  final bool? driverBriefingDone;
  final String? driverBriefingNotes;

  // סעיף 2 — לוח זמנים הכנה
  final List<PreparationScheduleRow> preparationSchedule;

  // סעיפים 3-5 — שעות
  final String? departureTime;
  final String? checkpointPassageTime;
  final String? navigationEndTime;

  // סעיף 6 — נקודת כינוס חירום
  final String? emergencyGatheringPoint;

  // סעיף 7 — שעת "גג" ובטיחות
  final String? ceilingTime;
  final String? safetyCeilingTime;

  // סעיפים 8-9 — מזג אוויר ואסטרונומיה
  final String? season;
  final String? weatherConditions;
  final String? weatherTemperature;
  final String? weatherWindSpeed;
  final String? weatherNotes;
  final double? moonIllumination;
  final String? sunsetTime;
  final String? sunriseTime;

  // ===== עמוד 2 — סעיפים 10-17 =====

  // סעיף 10 — בדיקת מערכות
  final List<SystemCheckRow> systemCheckTable;

  // סעיף 11 — תקשורת
  final List<CommunicationRow> communicationTable;

  // סעיף 12 — כוחות שכנים
  final List<NeighboringForceRow> neighboringForces;

  // סעיף 13 — ציר הפיקוד
  final String? commandPostAxis;

  // סעיף 14 — מסוק חילוץ
  final String? helicopterPhone;
  final String? helicopterFrequency;
  final String? helicopterInstructions;

  // סעיף 15 — פקודות אש
  final String? fireInstructions;

  // סעיף 16 — תקריות ותגובות
  final String? incidentsAndResponses;

  // סעיף 17 — נתונים נוספים
  final List<AdditionalDataRow> additionalData;

  // ===== עמוד 3 — סעיפים 18-25 =====

  // סעיף 18 — סריקת נפגעים
  final String? casualtySweepBy;
  final String? casualtySweepDate;
  final String? casualtySweepTime;

  // סעיף 19 — חיפוש וחילוץ
  final String? searchRescueInstructions;

  // סעיף 20 — אישור רכב
  final String? vehicleNumber1;
  final String? vehicleNumber2;
  final bool? afterElevenRestriction;

  // סעיף 21 — הערות מפקד
  final String? commanderNotes;
  final String? previousNavigatorLessons;

  // סעיף 22 — משלים תדריך בטיחות
  final String? safetyBriefingSupplement;

  // סעיף 23 — חתימת מנהל ניווט
  final SignatureData? managerSignature;

  // סעיף 24 — חתימת מאשר
  final SignatureData? approverSignature;

  // סעיף 25 — דף תיאום
  final String? coordinationSheetNotes;

  // מטא-דאטה
  final DateTime? lastUpdatedAt;
  final String? lastUpdatedBy;

  const VariablesSheet({
    // עמוד 1
    this.preliminaryTraining,
    this.medicCheckDone,
    this.medicCheckNotes,
    this.weightCheckDone,
    this.weightCheckNotes,
    this.driverBriefingDone,
    this.driverBriefingNotes,
    this.preparationSchedule = const [],
    this.departureTime,
    this.checkpointPassageTime,
    this.navigationEndTime,
    this.emergencyGatheringPoint,
    this.ceilingTime,
    this.safetyCeilingTime,
    this.season,
    this.weatherConditions,
    this.weatherTemperature,
    this.weatherWindSpeed,
    this.weatherNotes,
    this.moonIllumination,
    this.sunsetTime,
    this.sunriseTime,
    // עמוד 2
    this.systemCheckTable = const [],
    this.communicationTable = const [],
    this.neighboringForces = const [],
    this.commandPostAxis,
    this.helicopterPhone,
    this.helicopterFrequency,
    this.helicopterInstructions,
    this.fireInstructions,
    this.incidentsAndResponses,
    this.additionalData = const [],
    // עמוד 3
    this.casualtySweepBy,
    this.casualtySweepDate,
    this.casualtySweepTime,
    this.searchRescueInstructions,
    this.vehicleNumber1,
    this.vehicleNumber2,
    this.afterElevenRestriction,
    this.commanderNotes,
    this.previousNavigatorLessons,
    this.safetyBriefingSupplement,
    this.managerSignature,
    this.approverSignature,
    this.coordinationSheetNotes,
    // מטא-דאטה
    this.lastUpdatedAt,
    this.lastUpdatedBy,
  });

  VariablesSheet copyWith({
    String? preliminaryTraining,
    bool? medicCheckDone,
    String? medicCheckNotes,
    bool? weightCheckDone,
    String? weightCheckNotes,
    bool? driverBriefingDone,
    String? driverBriefingNotes,
    List<PreparationScheduleRow>? preparationSchedule,
    String? departureTime,
    String? checkpointPassageTime,
    String? navigationEndTime,
    String? emergencyGatheringPoint,
    String? ceilingTime,
    String? safetyCeilingTime,
    String? season,
    String? weatherConditions,
    String? weatherTemperature,
    String? weatherWindSpeed,
    String? weatherNotes,
    double? moonIllumination,
    String? sunsetTime,
    String? sunriseTime,
    List<SystemCheckRow>? systemCheckTable,
    List<CommunicationRow>? communicationTable,
    List<NeighboringForceRow>? neighboringForces,
    String? commandPostAxis,
    String? helicopterPhone,
    String? helicopterFrequency,
    String? helicopterInstructions,
    String? fireInstructions,
    String? incidentsAndResponses,
    List<AdditionalDataRow>? additionalData,
    String? casualtySweepBy,
    String? casualtySweepDate,
    String? casualtySweepTime,
    String? searchRescueInstructions,
    String? vehicleNumber1,
    String? vehicleNumber2,
    bool? afterElevenRestriction,
    String? commanderNotes,
    String? previousNavigatorLessons,
    String? safetyBriefingSupplement,
    SignatureData? managerSignature,
    SignatureData? approverSignature,
    String? coordinationSheetNotes,
    DateTime? lastUpdatedAt,
    String? lastUpdatedBy,
    bool clearMoonIllumination = false,
  }) {
    return VariablesSheet(
      preliminaryTraining: preliminaryTraining ?? this.preliminaryTraining,
      medicCheckDone: medicCheckDone ?? this.medicCheckDone,
      medicCheckNotes: medicCheckNotes ?? this.medicCheckNotes,
      weightCheckDone: weightCheckDone ?? this.weightCheckDone,
      weightCheckNotes: weightCheckNotes ?? this.weightCheckNotes,
      driverBriefingDone: driverBriefingDone ?? this.driverBriefingDone,
      driverBriefingNotes: driverBriefingNotes ?? this.driverBriefingNotes,
      preparationSchedule: preparationSchedule ?? this.preparationSchedule,
      departureTime: departureTime ?? this.departureTime,
      checkpointPassageTime: checkpointPassageTime ?? this.checkpointPassageTime,
      navigationEndTime: navigationEndTime ?? this.navigationEndTime,
      emergencyGatheringPoint: emergencyGatheringPoint ?? this.emergencyGatheringPoint,
      ceilingTime: ceilingTime ?? this.ceilingTime,
      safetyCeilingTime: safetyCeilingTime ?? this.safetyCeilingTime,
      season: season ?? this.season,
      weatherConditions: weatherConditions ?? this.weatherConditions,
      weatherTemperature: weatherTemperature ?? this.weatherTemperature,
      weatherWindSpeed: weatherWindSpeed ?? this.weatherWindSpeed,
      weatherNotes: weatherNotes ?? this.weatherNotes,
      moonIllumination: clearMoonIllumination ? null : (moonIllumination ?? this.moonIllumination),
      sunsetTime: sunsetTime ?? this.sunsetTime,
      sunriseTime: sunriseTime ?? this.sunriseTime,
      systemCheckTable: systemCheckTable ?? this.systemCheckTable,
      communicationTable: communicationTable ?? this.communicationTable,
      neighboringForces: neighboringForces ?? this.neighboringForces,
      commandPostAxis: commandPostAxis ?? this.commandPostAxis,
      helicopterPhone: helicopterPhone ?? this.helicopterPhone,
      helicopterFrequency: helicopterFrequency ?? this.helicopterFrequency,
      helicopterInstructions: helicopterInstructions ?? this.helicopterInstructions,
      fireInstructions: fireInstructions ?? this.fireInstructions,
      incidentsAndResponses: incidentsAndResponses ?? this.incidentsAndResponses,
      additionalData: additionalData ?? this.additionalData,
      casualtySweepBy: casualtySweepBy ?? this.casualtySweepBy,
      casualtySweepDate: casualtySweepDate ?? this.casualtySweepDate,
      casualtySweepTime: casualtySweepTime ?? this.casualtySweepTime,
      searchRescueInstructions: searchRescueInstructions ?? this.searchRescueInstructions,
      vehicleNumber1: vehicleNumber1 ?? this.vehicleNumber1,
      vehicleNumber2: vehicleNumber2 ?? this.vehicleNumber2,
      afterElevenRestriction: afterElevenRestriction ?? this.afterElevenRestriction,
      commanderNotes: commanderNotes ?? this.commanderNotes,
      previousNavigatorLessons: previousNavigatorLessons ?? this.previousNavigatorLessons,
      safetyBriefingSupplement: safetyBriefingSupplement ?? this.safetyBriefingSupplement,
      managerSignature: managerSignature ?? this.managerSignature,
      approverSignature: approverSignature ?? this.approverSignature,
      coordinationSheetNotes: coordinationSheetNotes ?? this.coordinationSheetNotes,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // עמוד 1
      if (preliminaryTraining != null) 'preliminaryTraining': preliminaryTraining,
      if (medicCheckDone != null) 'medicCheckDone': medicCheckDone,
      if (medicCheckNotes != null) 'medicCheckNotes': medicCheckNotes,
      if (weightCheckDone != null) 'weightCheckDone': weightCheckDone,
      if (weightCheckNotes != null) 'weightCheckNotes': weightCheckNotes,
      if (driverBriefingDone != null) 'driverBriefingDone': driverBriefingDone,
      if (driverBriefingNotes != null) 'driverBriefingNotes': driverBriefingNotes,
      if (preparationSchedule.isNotEmpty)
        'preparationSchedule': preparationSchedule.map((r) => r.toMap()).toList(),
      if (departureTime != null) 'departureTime': departureTime,
      if (checkpointPassageTime != null) 'checkpointPassageTime': checkpointPassageTime,
      if (navigationEndTime != null) 'navigationEndTime': navigationEndTime,
      if (emergencyGatheringPoint != null) 'emergencyGatheringPoint': emergencyGatheringPoint,
      if (ceilingTime != null) 'ceilingTime': ceilingTime,
      if (safetyCeilingTime != null) 'safetyCeilingTime': safetyCeilingTime,
      if (season != null) 'season': season,
      if (weatherConditions != null) 'weatherConditions': weatherConditions,
      if (weatherTemperature != null) 'weatherTemperature': weatherTemperature,
      if (weatherWindSpeed != null) 'weatherWindSpeed': weatherWindSpeed,
      if (weatherNotes != null) 'weatherNotes': weatherNotes,
      if (moonIllumination != null) 'moonIllumination': moonIllumination,
      if (sunsetTime != null) 'sunsetTime': sunsetTime,
      if (sunriseTime != null) 'sunriseTime': sunriseTime,
      // עמוד 2
      if (systemCheckTable.isNotEmpty)
        'systemCheckTable': systemCheckTable.map((r) => r.toMap()).toList(),
      if (communicationTable.isNotEmpty)
        'communicationTable': communicationTable.map((r) => r.toMap()).toList(),
      if (neighboringForces.isNotEmpty)
        'neighboringForces': neighboringForces.map((r) => r.toMap()).toList(),
      if (commandPostAxis != null) 'commandPostAxis': commandPostAxis,
      if (helicopterPhone != null) 'helicopterPhone': helicopterPhone,
      if (helicopterFrequency != null) 'helicopterFrequency': helicopterFrequency,
      if (helicopterInstructions != null) 'helicopterInstructions': helicopterInstructions,
      if (fireInstructions != null) 'fireInstructions': fireInstructions,
      if (incidentsAndResponses != null) 'incidentsAndResponses': incidentsAndResponses,
      if (additionalData.isNotEmpty)
        'additionalData': additionalData.map((r) => r.toMap()).toList(),
      // עמוד 3
      if (casualtySweepBy != null) 'casualtySweepBy': casualtySweepBy,
      if (casualtySweepDate != null) 'casualtySweepDate': casualtySweepDate,
      if (casualtySweepTime != null) 'casualtySweepTime': casualtySweepTime,
      if (searchRescueInstructions != null) 'searchRescueInstructions': searchRescueInstructions,
      if (vehicleNumber1 != null) 'vehicleNumber1': vehicleNumber1,
      if (vehicleNumber2 != null) 'vehicleNumber2': vehicleNumber2,
      if (afterElevenRestriction != null) 'afterElevenRestriction': afterElevenRestriction,
      if (commanderNotes != null) 'commanderNotes': commanderNotes,
      if (previousNavigatorLessons != null) 'previousNavigatorLessons': previousNavigatorLessons,
      if (safetyBriefingSupplement != null) 'safetyBriefingSupplement': safetyBriefingSupplement,
      if (managerSignature != null) 'managerSignature': managerSignature!.toMap(),
      if (approverSignature != null) 'approverSignature': approverSignature!.toMap(),
      if (coordinationSheetNotes != null) 'coordinationSheetNotes': coordinationSheetNotes,
      // מטא-דאטה
      if (lastUpdatedAt != null) 'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
      if (lastUpdatedBy != null) 'lastUpdatedBy': lastUpdatedBy,
    };
  }

  factory VariablesSheet.fromMap(Map<String, dynamic> map) {
    return VariablesSheet(
      // עמוד 1
      preliminaryTraining: map['preliminaryTraining'] as String?,
      medicCheckDone: map['medicCheckDone'] as bool?,
      medicCheckNotes: map['medicCheckNotes'] as String?,
      weightCheckDone: map['weightCheckDone'] as bool?,
      weightCheckNotes: map['weightCheckNotes'] as String?,
      driverBriefingDone: map['driverBriefingDone'] as bool?,
      driverBriefingNotes: map['driverBriefingNotes'] as String?,
      preparationSchedule: map['preparationSchedule'] != null
          ? (map['preparationSchedule'] as List)
              .map((r) => PreparationScheduleRow.fromMap(r as Map<String, dynamic>))
              .toList()
          : const [],
      departureTime: map['departureTime'] as String?,
      checkpointPassageTime: map['checkpointPassageTime'] as String?,
      navigationEndTime: map['navigationEndTime'] as String?,
      emergencyGatheringPoint: map['emergencyGatheringPoint'] as String?,
      ceilingTime: map['ceilingTime'] as String?,
      safetyCeilingTime: map['safetyCeilingTime'] as String?,
      season: map['season'] as String?,
      weatherConditions: map['weatherConditions'] as String?,
      weatherTemperature: map['weatherTemperature'] as String?,
      weatherWindSpeed: map['weatherWindSpeed'] as String?,
      weatherNotes: map['weatherNotes'] as String?,
      moonIllumination: (map['moonIllumination'] as num?)?.toDouble(),
      sunsetTime: map['sunsetTime'] as String?,
      sunriseTime: map['sunriseTime'] as String?,
      // עמוד 2
      systemCheckTable: map['systemCheckTable'] != null
          ? (map['systemCheckTable'] as List)
              .map((r) => SystemCheckRow.fromMap(r as Map<String, dynamic>))
              .toList()
          : const [],
      communicationTable: map['communicationTable'] != null
          ? (map['communicationTable'] as List)
              .map((r) => CommunicationRow.fromMap(r as Map<String, dynamic>))
              .toList()
          : const [],
      neighboringForces: map['neighboringForces'] != null
          ? (map['neighboringForces'] as List)
              .map((r) => NeighboringForceRow.fromMap(r as Map<String, dynamic>))
              .toList()
          : const [],
      commandPostAxis: map['commandPostAxis'] as String?,
      helicopterPhone: map['helicopterPhone'] as String?,
      helicopterFrequency: map['helicopterFrequency'] as String?,
      helicopterInstructions: map['helicopterInstructions'] as String?,
      fireInstructions: map['fireInstructions'] as String?,
      incidentsAndResponses: map['incidentsAndResponses'] as String?,
      additionalData: map['additionalData'] != null
          ? (map['additionalData'] as List)
              .map((r) => AdditionalDataRow.fromMap(r as Map<String, dynamic>))
              .toList()
          : const [],
      // עמוד 3
      casualtySweepBy: map['casualtySweepBy'] as String?,
      casualtySweepDate: map['casualtySweepDate'] as String?,
      casualtySweepTime: map['casualtySweepTime'] as String?,
      searchRescueInstructions: map['searchRescueInstructions'] as String?,
      vehicleNumber1: map['vehicleNumber1'] as String?,
      vehicleNumber2: map['vehicleNumber2'] as String?,
      afterElevenRestriction: map['afterElevenRestriction'] as bool?,
      commanderNotes: map['commanderNotes'] as String?,
      previousNavigatorLessons: map['previousNavigatorLessons'] as String?,
      safetyBriefingSupplement: map['safetyBriefingSupplement'] as String?,
      managerSignature: map['managerSignature'] != null
          ? SignatureData.fromMap(map['managerSignature'] as Map<String, dynamic>)
          : null,
      approverSignature: map['approverSignature'] != null
          ? SignatureData.fromMap(map['approverSignature'] as Map<String, dynamic>)
          : null,
      coordinationSheetNotes: map['coordinationSheetNotes'] as String?,
      // מטא-דאטה
      lastUpdatedAt: map['lastUpdatedAt'] != null
          ? DateTime.tryParse(map['lastUpdatedAt'] as String)
          : null,
      lastUpdatedBy: map['lastUpdatedBy'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    preliminaryTraining, medicCheckDone, medicCheckNotes,
    weightCheckDone, weightCheckNotes, driverBriefingDone, driverBriefingNotes,
    preparationSchedule, departureTime, checkpointPassageTime, navigationEndTime,
    emergencyGatheringPoint, ceilingTime, safetyCeilingTime,
    season, weatherConditions, weatherTemperature, weatherWindSpeed, weatherNotes,
    moonIllumination, sunsetTime, sunriseTime,
    systemCheckTable, communicationTable, neighboringForces,
    commandPostAxis, helicopterPhone, helicopterFrequency, helicopterInstructions,
    fireInstructions, incidentsAndResponses, additionalData,
    casualtySweepBy, casualtySweepDate, casualtySweepTime,
    searchRescueInstructions, vehicleNumber1, vehicleNumber2, afterElevenRestriction,
    commanderNotes, previousNavigatorLessons, safetyBriefingSupplement,
    managerSignature, approverSignature, coordinationSheetNotes,
    lastUpdatedAt, lastUpdatedBy,
  ];
}
