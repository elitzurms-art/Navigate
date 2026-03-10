import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';

void main() {
  // =========================================================================
  // SafetyTimeSettings
  // =========================================================================
  group('SafetyTimeSettings', () {
    test('toMap/fromMap roundtrip with all fields', () {
      const s = SafetyTimeSettings(type: 'hours', hours: 8, hoursAfterMission: 2);
      final restored = SafetyTimeSettings.fromMap(s.toMap());
      expect(restored, equals(s));
    });

    test('toMap omits null hours', () {
      const s = SafetyTimeSettings(type: 'after_last_mission', hoursAfterMission: 3);
      final map = s.toMap();
      expect(map.containsKey('hours'), isFalse);
      expect(map['hoursAfterMission'], 3);
    });

    test('toMap omits null hoursAfterMission', () {
      const s = SafetyTimeSettings(type: 'hours', hours: 5);
      final map = s.toMap();
      expect(map.containsKey('hoursAfterMission'), isFalse);
      expect(map['hours'], 5);
    });

    test('copyWith overrides fields', () {
      const s = SafetyTimeSettings(type: 'hours', hours: 4);
      final updated = s.copyWith(type: 'after_last_mission', hoursAfterMission: 6);
      expect(updated.type, 'after_last_mission');
      expect(updated.hoursAfterMission, 6);
      expect(updated.hours, 4); // preserved from original
    });

    test('Equatable equality', () {
      const a = SafetyTimeSettings(type: 'hours', hours: 5);
      const b = SafetyTimeSettings(type: 'hours', hours: 5);
      const c = SafetyTimeSettings(type: 'hours', hours: 6);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // =========================================================================
  // DistanceScoreRange
  // =========================================================================
  group('DistanceScoreRange', () {
    test('toMap/fromMap roundtrip', () {
      const r = DistanceScoreRange(maxDistance: 50, scorePercentage: 100);
      final restored = DistanceScoreRange.fromMap(r.toMap());
      expect(restored, equals(r));
    });

    test('Equatable equality', () {
      const a = DistanceScoreRange(maxDistance: 50, scorePercentage: 100);
      const b = DistanceScoreRange(maxDistance: 50, scorePercentage: 100);
      const c = DistanceScoreRange(maxDistance: 100, scorePercentage: 80);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // =========================================================================
  // VerificationSettings
  // =========================================================================
  group('VerificationSettings', () {
    test('toMap/fromMap roundtrip with scoreRanges', () {
      const v = VerificationSettings(
        autoVerification: true,
        verificationType: 'score_by_distance',
        scoreRanges: [
          DistanceScoreRange(maxDistance: 25, scorePercentage: 100),
          DistanceScoreRange(maxDistance: 50, scorePercentage: 80),
        ],
        punchMode: 'free',
      );
      final restored = VerificationSettings.fromMap(v.toMap());
      expect(restored, equals(v));
    });

    test('fromMap defaults: autoVerification=true, punchMode=sequential', () {
      final v = VerificationSettings.fromMap(const {});
      expect(v.autoVerification, isTrue);
      expect(v.punchMode, 'sequential');
      expect(v.verificationType, isNull);
      expect(v.approvalDistance, isNull);
      expect(v.scoreRanges, isNull);
    });

    test('toMap omits null optional fields', () {
      const v = VerificationSettings(autoVerification: false);
      final map = v.toMap();
      expect(map.containsKey('verificationType'), isFalse);
      expect(map.containsKey('approvalDistance'), isFalse);
      expect(map.containsKey('scoreRanges'), isFalse);
      expect(map['autoVerification'], isFalse);
      expect(map['punchMode'], 'sequential');
    });

    test('copyWith preserves and overrides', () {
      const v = VerificationSettings(
        autoVerification: true,
        punchMode: 'sequential',
        approvalDistance: 30,
      );
      final updated = v.copyWith(punchMode: 'free');
      expect(updated.punchMode, 'free');
      expect(updated.approvalDistance, 30);
    });
  });

  // =========================================================================
  // NavigationAlerts
  // =========================================================================
  group('NavigationAlerts', () {
    test('toMap/fromMap roundtrip with all alerts enabled', () {
      const a = NavigationAlerts(
        enabled: true,
        speedAlertEnabled: true,
        maxSpeed: 30,
        noMovementAlertEnabled: true,
        noMovementMinutes: 10,
        ggAlertEnabled: true,
        ggAlertRange: 200,
        routesAlertEnabled: true,
        routesAlertRange: 100,
        nbAlertEnabled: true,
        nbAlertRange: 150,
        navigatorProximityAlertEnabled: true,
        proximityDistance: 50,
        proximityMinTime: 5,
        batteryAlertEnabled: true,
        batteryPercentage: 20,
        noReceptionAlertEnabled: true,
        noReceptionMinTime: 120,
        healthCheckEnabled: false,
        healthCheckIntervalMinutes: 30,
      );
      final restored = NavigationAlerts.fromMap(a.toMap());
      expect(restored, equals(a));
    });

    test('fromMap defaults from empty map', () {
      final a = NavigationAlerts.fromMap(const {});
      expect(a.enabled, isFalse);
      expect(a.speedAlertEnabled, isFalse);
      expect(a.noMovementAlertEnabled, isFalse);
      expect(a.ggAlertEnabled, isFalse);
      expect(a.routesAlertEnabled, isFalse);
      expect(a.nbAlertEnabled, isFalse);
      expect(a.navigatorProximityAlertEnabled, isFalse);
      expect(a.batteryAlertEnabled, isFalse);
      expect(a.noReceptionAlertEnabled, isFalse);
      expect(a.healthCheckEnabled, isTrue);
      expect(a.healthCheckIntervalMinutes, 60);
    });

    test('toMap omits null conditional fields', () {
      const a = NavigationAlerts(enabled: false);
      final map = a.toMap();
      expect(map.containsKey('maxSpeed'), isFalse);
      expect(map.containsKey('noMovementMinutes'), isFalse);
      expect(map.containsKey('ggAlertRange'), isFalse);
      expect(map.containsKey('routesAlertRange'), isFalse);
      expect(map.containsKey('nbAlertRange'), isFalse);
      expect(map.containsKey('proximityDistance'), isFalse);
      expect(map.containsKey('proximityMinTime'), isFalse);
      expect(map.containsKey('batteryPercentage'), isFalse);
      expect(map.containsKey('noReceptionMinTime'), isFalse);
    });

    test('copyWith overrides selected fields', () {
      const a = NavigationAlerts(enabled: false, healthCheckIntervalMinutes: 60);
      final updated = a.copyWith(enabled: true, healthCheckIntervalMinutes: 120);
      expect(updated.enabled, isTrue);
      expect(updated.healthCheckIntervalMinutes, 120);
      expect(updated.healthCheckEnabled, isTrue); // preserved default
    });
  });

  // =========================================================================
  // LearningSettings
  // =========================================================================
  group('LearningSettings', () {
    test('toMap/fromMap roundtrip with all fields', () {
      final date = DateTime(2026, 3, 10);
      final ls = LearningSettings(
        enabledWithPhones: false,
        showAllCheckpoints: true,
        showNavigationDetails: false,
        showMissionTimes: false,
        showRoutes: false,
        allowRouteEditing: false,
        allowRouteNarration: false,
        autoLearningTimes: true,
        learningDate: date,
        learningStartTime: '08:00',
        learningEndTime: '10:00',
        requireCommanderQuiz: true,
        requireSoloQuiz: true,
        quizType: 'regular',
        quizOpenManually: true,
        autoQuizTimes: true,
        quizDate: date,
        quizStartTime: '11:00',
        quizEndTime: '12:00',
      );
      final restored = LearningSettings.fromMap(ls.toMap());
      expect(restored, equals(ls));
    });

    test('fromMap defaults from empty map', () {
      final ls = LearningSettings.fromMap(const {});
      expect(ls.enabledWithPhones, isTrue);
      expect(ls.showAllCheckpoints, isFalse);
      expect(ls.showNavigationDetails, isTrue);
      expect(ls.showMissionTimes, isTrue);
      expect(ls.showRoutes, isTrue);
      expect(ls.allowRouteEditing, isTrue);
      expect(ls.allowRouteNarration, isTrue);
      expect(ls.autoLearningTimes, isFalse);
      expect(ls.learningDate, isNull);
      expect(ls.requireCommanderQuiz, isFalse);
      expect(ls.requireSoloQuiz, isFalse);
      expect(ls.quizType, 'solo');
      expect(ls.quizOpenManually, isFalse);
      expect(ls.autoQuizTimes, isFalse);
    });

    test('learningDate DateTime serialization via ISO8601', () {
      final date = DateTime(2026, 6, 15, 14, 30);
      final ls = LearningSettings(learningDate: date);
      final map = ls.toMap();
      expect(map['learningDate'], date.toIso8601String());
      final restored = LearningSettings.fromMap(map);
      expect(restored.learningDate, date);
    });

    test('toMap omits null date fields', () {
      const ls = LearningSettings();
      final map = ls.toMap();
      expect(map.containsKey('learningDate'), isFalse);
      expect(map.containsKey('learningStartTime'), isFalse);
      expect(map.containsKey('learningEndTime'), isFalse);
      expect(map.containsKey('quizDate'), isFalse);
      expect(map.containsKey('quizStartTime'), isFalse);
      expect(map.containsKey('quizEndTime'), isFalse);
    });

    test('isCommanderQuizCurrentlyOpen returns requireCommanderQuiz value', () {
      const open = LearningSettings(requireCommanderQuiz: true);
      const closed = LearningSettings(requireCommanderQuiz: false);
      expect(open.isCommanderQuizCurrentlyOpen, isTrue);
      expect(closed.isCommanderQuizCurrentlyOpen, isFalse);
    });

    test('isQuizCurrentlyOpen false when requireSoloQuiz is false', () {
      const ls = LearningSettings(requireSoloQuiz: false, quizOpenManually: true);
      expect(ls.isQuizCurrentlyOpen, isFalse);
    });

    test('isQuizCurrentlyOpen true when quizOpenManually is true', () {
      const ls = LearningSettings(requireSoloQuiz: true, quizOpenManually: true);
      expect(ls.isQuizCurrentlyOpen, isTrue);
    });
  });

  // =========================================================================
  // CustomCriterion
  // =========================================================================
  group('CustomCriterion', () {
    test('toMap/fromMap roundtrip', () {
      const c = CustomCriterion(id: 'c1', name: 'Time', weight: 20);
      final restored = CustomCriterion.fromMap(c.toMap());
      expect(restored, equals(c));
    });

    test('copyWith overrides', () {
      const c = CustomCriterion(id: 'c1', name: 'Time', weight: 20);
      final updated = c.copyWith(name: 'Distance', weight: 30);
      expect(updated.id, 'c1');
      expect(updated.name, 'Distance');
      expect(updated.weight, 30);
    });

    test('Equatable equality', () {
      const a = CustomCriterion(id: 'c1', name: 'X', weight: 10);
      const b = CustomCriterion(id: 'c1', name: 'X', weight: 10);
      const c = CustomCriterion(id: 'c2', name: 'X', weight: 10);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // =========================================================================
  // ScoringCriteria
  // =========================================================================
  group('ScoringCriteria', () {
    test('toMap/fromMap roundtrip with custom mode', () {
      const sc = ScoringCriteria(
        mode: 'custom',
        checkpointWeights: {'0': 30, '1': 20, '2': 50},
        customCriteria: [
          CustomCriterion(id: 'c1', name: 'Navigation', weight: 15),
          CustomCriterion(id: 'c2', name: 'Time', weight: 10),
        ],
      );
      final restored = ScoringCriteria.fromMap(sc.toMap());
      expect(restored, equals(sc));
    });

    test('fromMap defaults: mode=equal, empty weights and criteria', () {
      final sc = ScoringCriteria.fromMap(const {});
      expect(sc.mode, 'equal');
      expect(sc.equalWeightPerCheckpoint, isNull);
      expect(sc.checkpointWeights, isEmpty);
      expect(sc.customCriteria, isEmpty);
    });

    test('totalWeight for custom mode sums checkpointWeights + customCriteria', () {
      const sc = ScoringCriteria(
        mode: 'custom',
        checkpointWeights: {'0': 30, '1': 20},
        customCriteria: [CustomCriterion(id: 'c1', name: 'X', weight: 10)],
      );
      expect(sc.totalWeight, 60); // 30+20+10
    });

    test('totalWeight for equal mode only includes customCriteria', () {
      const sc = ScoringCriteria(
        mode: 'equal',
        equalWeightPerCheckpoint: 10,
        customCriteria: [CustomCriterion(id: 'c1', name: 'X', weight: 5)],
      );
      expect(sc.totalWeight, 5); // equal mode: 0 + 5 custom
    });

    test('totalWeightWithCheckpoints for equal mode', () {
      const sc = ScoringCriteria(
        mode: 'equal',
        equalWeightPerCheckpoint: 10,
        customCriteria: [CustomCriterion(id: 'c1', name: 'X', weight: 5)],
      );
      expect(sc.totalWeightWithCheckpoints(4), 45); // 10*4 + 5
    });

    test('totalWeightWithCheckpoints for custom mode ignores checkpointCount', () {
      const sc = ScoringCriteria(
        mode: 'custom',
        checkpointWeights: {'0': 20, '1': 30},
        customCriteria: [CustomCriterion(id: 'c1', name: 'X', weight: 10)],
      );
      expect(sc.totalWeightWithCheckpoints(99), 60); // 20+30+10, ignores 99
    });

    test('toMap omits empty checkpointWeights and customCriteria', () {
      const sc = ScoringCriteria(mode: 'equal');
      final map = sc.toMap();
      expect(map.containsKey('checkpointWeights'), isFalse);
      expect(map.containsKey('customCriteria'), isFalse);
      expect(map.containsKey('equalWeightPerCheckpoint'), isFalse);
    });
  });

  // =========================================================================
  // ReviewSettings
  // =========================================================================
  group('ReviewSettings', () {
    test('toMap/fromMap roundtrip with nested scoringCriteria', () {
      const rs = ReviewSettings(
        showScoresAfterApproval: false,
        scoringCriteria: ScoringCriteria(
          mode: 'custom',
          checkpointWeights: {'0': 50},
          customCriteria: [CustomCriterion(id: 'c1', name: 'Pace', weight: 25)],
        ),
      );
      final restored = ReviewSettings.fromMap(rs.toMap());
      expect(restored, equals(rs));
    });

    test('fromMap defaults: showScoresAfterApproval=true, no criteria', () {
      final rs = ReviewSettings.fromMap(const {});
      expect(rs.showScoresAfterApproval, isTrue);
      expect(rs.scoringCriteria, isNull);
    });

    test('toMap omits null scoringCriteria', () {
      const rs = ReviewSettings();
      final map = rs.toMap();
      expect(map.containsKey('scoringCriteria'), isFalse);
      expect(map['showScoresAfterApproval'], isTrue);
    });

    test('copyWith overrides', () {
      const rs = ReviewSettings(showScoresAfterApproval: true);
      final updated = rs.copyWith(showScoresAfterApproval: false);
      expect(updated.showScoresAfterApproval, isFalse);
    });
  });

  // =========================================================================
  // DisplaySettings
  // =========================================================================
  group('DisplaySettings', () {
    test('toMap/fromMap roundtrip with all fields', () {
      const ds = DisplaySettings(
        defaultMap: 'topo',
        openingLat: 31.5,
        openingLng: 34.8,
        activeLayers: {'checkpoints': true, 'boundaries': false},
        layerOpacity: {'checkpoints': 0.8, 'boundaries': 0.5},
        enableVariablesSheet: false,
      );
      final restored = DisplaySettings.fromMap(ds.toMap());
      expect(restored, equals(ds));
    });

    test('fromMap defaults: enableVariablesSheet=true', () {
      final ds = DisplaySettings.fromMap(const {});
      expect(ds.enableVariablesSheet, isTrue);
      expect(ds.defaultMap, isNull);
      expect(ds.openingLat, isNull);
      expect(ds.openingLng, isNull);
      expect(ds.activeLayers, isNull);
      expect(ds.layerOpacity, isNull);
    });

    test('toMap omits null optional fields', () {
      const ds = DisplaySettings();
      final map = ds.toMap();
      expect(map.containsKey('defaultMap'), isFalse);
      expect(map.containsKey('openingLat'), isFalse);
      expect(map.containsKey('openingLng'), isFalse);
      expect(map.containsKey('activeLayers'), isFalse);
      expect(map.containsKey('layerOpacity'), isFalse);
      expect(map['enableVariablesSheet'], isTrue);
    });

    test('activeLayers map roundtrip', () {
      const ds = DisplaySettings(activeLayers: {'nz': true, 'gg': false});
      final restored = DisplaySettings.fromMap(ds.toMap());
      expect(restored.activeLayers, {'nz': true, 'gg': false});
    });

    test('copyWith overrides', () {
      const ds = DisplaySettings(enableVariablesSheet: true);
      final updated = ds.copyWith(enableVariablesSheet: false, defaultMap: 'satellite');
      expect(updated.enableVariablesSheet, isFalse);
      expect(updated.defaultMap, 'satellite');
    });
  });

  // =========================================================================
  // TimeCalculationSettings
  // =========================================================================
  group('TimeCalculationSettings', () {
    test('toMap/fromMap roundtrip', () {
      const tc = TimeCalculationSettings(
        enabled: false,
        isHeavyLoad: true,
        isNightNavigation: true,
        isSummer: false,
        allowExtensionRequests: false,
        extensionWindowType: 'timed',
        extensionWindowMinutes: 30,
      );
      final restored = TimeCalculationSettings.fromMap(tc.toMap());
      expect(restored, equals(tc));
    });

    test('fromMap defaults from empty map', () {
      final tc = TimeCalculationSettings.fromMap(const {});
      expect(tc.enabled, isTrue);
      expect(tc.isHeavyLoad, isFalse);
      expect(tc.isNightNavigation, isFalse);
      expect(tc.isSummer, isTrue);
      expect(tc.allowExtensionRequests, isTrue);
      expect(tc.extensionWindowType, 'all');
      expect(tc.extensionWindowMinutes, isNull);
    });

    test('toMap omits null extensionWindowMinutes', () {
      const tc = TimeCalculationSettings();
      final map = tc.toMap();
      expect(map.containsKey('extensionWindowMinutes'), isFalse);
    });

    test('walkingSpeedKmh: light + day = 4.0', () {
      const tc = TimeCalculationSettings(isHeavyLoad: false, isNightNavigation: false);
      expect(tc.walkingSpeedKmh, 4.0);
    });

    test('walkingSpeedKmh: light + night = 2.5', () {
      const tc = TimeCalculationSettings(isHeavyLoad: false, isNightNavigation: true);
      expect(tc.walkingSpeedKmh, 2.5);
    });

    test('walkingSpeedKmh: heavy + day = 3.5', () {
      const tc = TimeCalculationSettings(isHeavyLoad: true, isNightNavigation: false);
      expect(tc.walkingSpeedKmh, 3.5);
    });

    test('walkingSpeedKmh: heavy + night = 2.0', () {
      const tc = TimeCalculationSettings(isHeavyLoad: true, isNightNavigation: true);
      expect(tc.walkingSpeedKmh, 2.0);
    });

    test('breakDurationMinutes: <=10km returns 0', () {
      const tc = TimeCalculationSettings(isSummer: true);
      expect(tc.breakDurationMinutes(10.0), 0);
      expect(tc.breakDurationMinutes(5.0), 0);
    });

    test('breakDurationMinutes: summer 25km = 2 breaks * 15min = 30', () {
      const tc = TimeCalculationSettings(isSummer: true);
      expect(tc.breakDurationMinutes(25.0), 30);
    });

    test('breakDurationMinutes: winter 25km = 2 breaks * 10min = 20', () {
      const tc = TimeCalculationSettings(isSummer: false);
      expect(tc.breakDurationMinutes(25.0), 20);
    });

    test('copyWith overrides', () {
      const tc = TimeCalculationSettings();
      final updated = tc.copyWith(isHeavyLoad: true, extensionWindowMinutes: 15);
      expect(updated.isHeavyLoad, isTrue);
      expect(updated.extensionWindowMinutes, 15);
      expect(updated.enabled, isTrue); // preserved
    });
  });

  // =========================================================================
  // CommunicationSettings
  // =========================================================================
  group('CommunicationSettings', () {
    test('toMap/fromMap roundtrip', () {
      const cs = CommunicationSettings(walkieTalkieEnabled: false);
      final restored = CommunicationSettings.fromMap(cs.toMap());
      expect(restored, equals(cs));
    });

    test('fromMap default: walkieTalkieEnabled=true', () {
      final cs = CommunicationSettings.fromMap(const {});
      expect(cs.walkieTalkieEnabled, isTrue);
    });

    test('copyWith overrides', () {
      const cs = CommunicationSettings(walkieTalkieEnabled: true);
      final updated = cs.copyWith(walkieTalkieEnabled: false);
      expect(updated.walkieTalkieEnabled, isFalse);
    });

    test('Equatable equality', () {
      const a = CommunicationSettings(walkieTalkieEnabled: true);
      const b = CommunicationSettings(walkieTalkieEnabled: true);
      const c = CommunicationSettings(walkieTalkieEnabled: false);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // =========================================================================
  // ForceComposition
  // =========================================================================
  group('ForceComposition', () {
    test('toMap/fromMap roundtrip with all fields', () {
      const fc = ForceComposition(
        type: 'guard',
        swapPointId: 'sp1',
        manualGroups: {
          'g1': ['n1', 'n2'],
          'g2': ['n3', 'n4'],
        },
        learningRepresentatives: {'g1': 'n1', 'g2': 'n3'},
        activeRepresentatives: {'g1': 'n2', 'g2': 'n4'},
      );
      final restored = ForceComposition.fromMap(fc.toMap());
      expect(restored, equals(fc));
    });

    test('fromMap defaults: type=solo, empty maps', () {
      final fc = ForceComposition.fromMap(const {});
      expect(fc.type, 'solo');
      expect(fc.swapPointId, isNull);
      expect(fc.manualGroups, isEmpty);
      expect(fc.learningRepresentatives, isEmpty);
      expect(fc.activeRepresentatives, isEmpty);
    });

    test('toMap omits empty maps and null swapPointId', () {
      const fc = ForceComposition();
      final map = fc.toMap();
      expect(map.containsKey('swapPointId'), isFalse);
      expect(map.containsKey('manualGroups'), isFalse);
      expect(map.containsKey('learningRepresentatives'), isFalse);
      expect(map.containsKey('activeRepresentatives'), isFalse);
      expect(map['type'], 'solo');
    });

    test('baseGroupSize and maxGroupSize for each type', () {
      expect(const ForceComposition(type: 'solo').baseGroupSize, 1);
      expect(const ForceComposition(type: 'solo').maxGroupSize, 1);
      expect(const ForceComposition(type: 'guard').baseGroupSize, 2);
      expect(const ForceComposition(type: 'guard').maxGroupSize, 3);
      expect(const ForceComposition(type: 'pair').baseGroupSize, 2);
      expect(const ForceComposition(type: 'pair').maxGroupSize, 3);
      expect(const ForceComposition(type: 'squad').baseGroupSize, 4);
      expect(const ForceComposition(type: 'squad').maxGroupSize, 5);
    });

    test('isSolo, isGuard, isGrouped, isGroupedPairOrSquad', () {
      expect(const ForceComposition(type: 'solo').isSolo, isTrue);
      expect(const ForceComposition(type: 'solo').isGrouped, isFalse);
      expect(const ForceComposition(type: 'guard').isGuard, isTrue);
      expect(const ForceComposition(type: 'guard').isGrouped, isTrue);
      expect(const ForceComposition(type: 'guard').isGroupedPairOrSquad, isFalse);
      expect(const ForceComposition(type: 'pair').isGroupedPairOrSquad, isTrue);
      expect(const ForceComposition(type: 'squad').isGroupedPairOrSquad, isTrue);
    });

    test('copyWith with clearSwapPointId', () {
      const fc = ForceComposition(type: 'guard', swapPointId: 'sp1');
      final updated = fc.copyWith(clearSwapPointId: true);
      expect(updated.swapPointId, isNull);
      expect(updated.type, 'guard');
    });
  });

  // =========================================================================
  // WaypointSettings
  // =========================================================================
  group('WaypointSettings', () {
    test('toMap/fromMap roundtrip', () {
      const ws = WaypointSettings(
        enabled: true,
        waypoints: [
          WaypointCheckpoint(
            checkpointId: 'cp1',
            placementType: 'distance',
            afterDistanceMinKm: 2.0,
            afterDistanceMaxKm: 5.0,
          ),
          WaypointCheckpoint(
            checkpointId: 'cp2',
            placementType: 'between_checkpoints',
            afterCheckpointIndex: 1,
          ),
        ],
      );
      final restored = WaypointSettings.fromMap(ws.toMap());
      expect(restored, equals(ws));
    });

    test('fromMap defaults: enabled=false, empty waypoints', () {
      final ws = WaypointSettings.fromMap(const {});
      expect(ws.enabled, isFalse);
      expect(ws.waypoints, isEmpty);
    });

    test('WaypointCheckpoint backward compat: afterDistanceKm', () {
      final wc = WaypointCheckpoint.fromMap(const {
        'checkpointId': 'cp1',
        'placementType': 'distance',
        'afterDistanceKm': 3.5,
      });
      expect(wc.afterDistanceMinKm, 3.5);
      expect(wc.afterDistanceMaxKm, 3.5);
    });
  });

  // =========================================================================
  // ClusterSettings
  // =========================================================================
  group('ClusterSettings', () {
    test('toMap/fromMap roundtrip', () {
      final date = DateTime(2026, 4, 1);
      final cs = ClusterSettings(
        clusterSize: 5,
        clusterSpreadMeters: 300,
        revealOpenManually: true,
        autoRevealTimes: true,
        revealDate: date,
        revealStartTime: '09:00',
        revealEndTime: '11:00',
      );
      final restored = ClusterSettings.fromMap(cs.toMap());
      expect(restored, equals(cs));
    });

    test('fromMap defaults from empty map', () {
      final cs = ClusterSettings.fromMap(const {});
      expect(cs.clusterSize, 3);
      expect(cs.clusterSpreadMeters, 200);
      expect(cs.revealOpenManually, isFalse);
      expect(cs.autoRevealTimes, isFalse);
      expect(cs.revealDate, isNull);
      expect(cs.revealStartTime, isNull);
      expect(cs.revealEndTime, isNull);
    });

    test('toMap omits null date fields', () {
      const cs = ClusterSettings();
      final map = cs.toMap();
      expect(map.containsKey('revealDate'), isFalse);
      expect(map.containsKey('revealStartTime'), isFalse);
      expect(map.containsKey('revealEndTime'), isFalse);
    });

    test('backward compat: revealEnabled old format', () {
      final cs = ClusterSettings.fromMap(const {
        'revealEnabled': true,
      });
      expect(cs.revealOpenManually, isTrue);
    });

    test('copyWith overrides', () {
      const cs = ClusterSettings();
      final updated = cs.copyWith(clusterSize: 6, clusterSpreadMeters: 400);
      expect(updated.clusterSize, 6);
      expect(updated.clusterSpreadMeters, 400);
    });
  });

  // =========================================================================
  // ParachuteSettings
  // =========================================================================
  group('ParachuteSettings', () {
    test('toMap/fromMap roundtrip with all fields', () {
      const ps = ParachuteSettings(
        dropPointIds: ['dp1', 'dp2'],
        assignmentMethod: 'manual',
        navigatorDropPoints: {'n1': 'dp1', 'n2': 'dp2'},
        subFrameworkDropPoints: {
          'sf1': ['dp1'],
          'sf2': ['dp2'],
        },
        samePointPerSubFramework: true,
        routeMode: 'clusters',
      );
      final restored = ParachuteSettings.fromMap(ps.toMap());
      expect(restored, equals(ps));
    });

    test('fromMap defaults from empty map', () {
      final ps = ParachuteSettings.fromMap(const {});
      expect(ps.dropPointIds, isEmpty);
      expect(ps.assignmentMethod, 'random');
      expect(ps.navigatorDropPoints, isEmpty);
      expect(ps.subFrameworkDropPoints, isEmpty);
      expect(ps.samePointPerSubFramework, isFalse);
      expect(ps.routeMode, 'checkpoints');
    });

    test('toMap omits empty navigatorDropPoints and subFrameworkDropPoints', () {
      const ps = ParachuteSettings();
      final map = ps.toMap();
      expect(map.containsKey('navigatorDropPoints'), isFalse);
      expect(map.containsKey('subFrameworkDropPoints'), isFalse);
      expect(map['dropPointIds'], isEmpty);
      expect(map['assignmentMethod'], 'random');
    });

    test('copyWith overrides', () {
      const ps = ParachuteSettings();
      final updated = ps.copyWith(
        dropPointIds: ['dp1'],
        assignmentMethod: 'by_sub_framework',
        routeMode: 'clusters',
      );
      expect(updated.dropPointIds, ['dp1']);
      expect(updated.assignmentMethod, 'by_sub_framework');
      expect(updated.routeMode, 'clusters');
      expect(updated.samePointPerSubFramework, isFalse); // preserved default
    });

    test('Equatable equality', () {
      const a = ParachuteSettings(dropPointIds: ['dp1'], assignmentMethod: 'random');
      const b = ParachuteSettings(dropPointIds: ['dp1'], assignmentMethod: 'random');
      const c = ParachuteSettings(dropPointIds: ['dp2'], assignmentMethod: 'random');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
