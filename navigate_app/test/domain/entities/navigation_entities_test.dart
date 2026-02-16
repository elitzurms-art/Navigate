import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/navigation.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';
import 'package:navigate_app/domain/entities/narration_entry.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';

/// Helper: returns a valid minimal Navigation map with all required fields.
/// Override specific fields by passing them in [overrides].
Map<String, dynamic> buildMinimalNavigationMap([
  Map<String, dynamic> overrides = const {},
]) {
  final now = DateTime(2026, 2, 15, 10, 0, 0);
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
    'createdAt': now.toIso8601String(),
    'updatedAt': now.toIso8601String(),
  };
  base.addAll(overrides);
  return base;
}

void main() {
  // ---------------------------------------------------------------------------
  // AssignedRoute
  // ---------------------------------------------------------------------------
  group('AssignedRoute', () {
    test('toMap/fromMap roundtrip with all fields populated', () {
      final route = AssignedRoute(
        checkpointIds: ['cp1', 'cp2', 'cp3'],
        routeLengthKm: 4.75,
        sequence: ['cp1', 'cp3', 'cp2'],
        startPointId: 'start-1',
        endPointId: 'end-1',
        waypointIds: ['wp1', 'wp2'],
        status: 'too_long',
        isVerified: true,
        approvalStatus: 'approved',
        rejectionNotes: 'needs shorter route',
        plannedPath: [
          const Coordinate(lat: 31.5, lng: 34.5, utm: '123456789012'),
          const Coordinate(lat: 31.6, lng: 34.6, utm: '234567890123'),
        ],
        narrationEntries: [
          const NarrationEntry(
            index: 1,
            pointName: 'Hill 100',
            segmentKm: '1.2',
            cumulativeKm: '1.2',
            bearing: '045 NE',
            description: 'Follow trail north',
            action: 'Turn right',
            elevationM: 100.0,
            walkingTimeMin: 25.0,
            obstacles: 'Rocky terrain',
          ),
        ],
      );

      final map = route.toMap();
      final restored = AssignedRoute.fromMap(map);

      expect(restored, equals(route));
      expect(restored.checkpointIds, ['cp1', 'cp2', 'cp3']);
      expect(restored.routeLengthKm, 4.75);
      expect(restored.sequence, ['cp1', 'cp3', 'cp2']);
      expect(restored.startPointId, 'start-1');
      expect(restored.endPointId, 'end-1');
      expect(restored.waypointIds, ['wp1', 'wp2']);
      expect(restored.status, 'too_long');
      expect(restored.isVerified, true);
      expect(restored.approvalStatus, 'approved');
      expect(restored.rejectionNotes, 'needs shorter route');
      expect(restored.plannedPath.length, 2);
      expect(restored.plannedPath[0].lat, 31.5);
      expect(restored.narrationEntries.length, 1);
      expect(restored.narrationEntries[0].pointName, 'Hill 100');
    });

    test('fromMap with only required fields falls back to defaults', () {
      final map = <String, dynamic>{
        'checkpointIds': ['cp1', 'cp2'],
        'routeLengthKm': 3.0,
        'sequence': ['cp1', 'cp2'],
      };

      final route = AssignedRoute.fromMap(map);

      expect(route.checkpointIds, ['cp1', 'cp2']);
      expect(route.routeLengthKm, 3.0);
      expect(route.sequence, ['cp1', 'cp2']);
      expect(route.startPointId, isNull);
      expect(route.endPointId, isNull);
      expect(route.waypointIds, isEmpty);
      expect(route.status, 'optimal');
      expect(route.isVerified, false);
      expect(route.approvalStatus, 'not_submitted');
      expect(route.rejectionNotes, isNull);
      expect(route.plannedPath, isEmpty);
      expect(route.narrationEntries, isEmpty);
    });

    test('copyWith changes specified fields and preserves others', () {
      const original = AssignedRoute(
        checkpointIds: ['a', 'b'],
        routeLengthKm: 2.0,
        sequence: ['a', 'b'],
        status: 'optimal',
        isVerified: false,
        approvalStatus: 'not_submitted',
        rejectionNotes: 'some note',
      );

      final modified = original.copyWith(
        routeLengthKm: 5.5,
        status: 'too_short',
        isVerified: true,
        approvalStatus: 'approved',
      );

      // Changed fields
      expect(modified.routeLengthKm, 5.5);
      expect(modified.status, 'too_short');
      expect(modified.isVerified, true);
      expect(modified.approvalStatus, 'approved');

      // Preserved fields
      expect(modified.checkpointIds, ['a', 'b']);
      expect(modified.sequence, ['a', 'b']);
      expect(modified.rejectionNotes, 'some note');
    });

    test('copyWith clearRejectionNotes sets rejectionNotes to null', () {
      const original = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 1.0,
        sequence: ['a'],
        rejectionNotes: 'old note',
      );

      final cleared = original.copyWith(clearRejectionNotes: true);
      expect(cleared.rejectionNotes, isNull);
    });

    test('isApproved getter returns correct values for each status', () {
      const approved = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 1.0,
        sequence: ['a'],
        approvalStatus: 'approved',
      );
      expect(approved.isApproved, true);

      const notSubmitted = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 1.0,
        sequence: ['a'],
        approvalStatus: 'not_submitted',
      );
      expect(notSubmitted.isApproved, false);

      const pending = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 1.0,
        sequence: ['a'],
        approvalStatus: 'pending_approval',
      );
      expect(pending.isApproved, false);

      const rejected = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 1.0,
        sequence: ['a'],
        approvalStatus: 'rejected',
      );
      expect(rejected.isApproved, false);
    });

    test('Equatable: same values are equal, different values are not', () {
      const route1 = AssignedRoute(
        checkpointIds: ['cp1', 'cp2'],
        routeLengthKm: 3.5,
        sequence: ['cp1', 'cp2'],
        status: 'optimal',
      );

      const route2 = AssignedRoute(
        checkpointIds: ['cp1', 'cp2'],
        routeLengthKm: 3.5,
        sequence: ['cp1', 'cp2'],
        status: 'optimal',
      );

      const route3 = AssignedRoute(
        checkpointIds: ['cp1', 'cp2'],
        routeLengthKm: 4.0, // different length
        sequence: ['cp1', 'cp2'],
        status: 'optimal',
      );

      expect(route1, equals(route2));
      expect(route1.hashCode, equals(route2.hashCode));
      expect(route1, isNot(equals(route3)));
    });

    test('plannedPath serialization roundtrip with Coordinate list', () {
      const route = AssignedRoute(
        checkpointIds: ['cp1'],
        routeLengthKm: 1.0,
        sequence: ['cp1'],
        plannedPath: [
          Coordinate(lat: 31.0, lng: 34.0, utm: '111111222222'),
          Coordinate(lat: 31.1, lng: 34.1, utm: '333333444444'),
          Coordinate(lat: 31.2, lng: 34.2, utm: '555555666666'),
        ],
      );

      final map = route.toMap();
      expect(map['plannedPath'], isList);
      expect((map['plannedPath'] as List).length, 3);

      final restored = AssignedRoute.fromMap(map);
      expect(restored.plannedPath.length, 3);
      expect(restored.plannedPath[0].lat, 31.0);
      expect(restored.plannedPath[1].lng, 34.1);
      expect(restored.plannedPath[2].utm, '555555666666');
      expect(restored.plannedPath, equals(route.plannedPath));
    });

    test('toMap conditionally omits null/empty fields', () {
      const route = AssignedRoute(
        checkpointIds: ['cp1'],
        routeLengthKm: 2.0,
        sequence: ['cp1'],
        // startPointId is null, endPointId is null
        // waypointIds is empty, plannedPath is empty, narrationEntries is empty
      );

      final map = route.toMap();

      expect(map.containsKey('startPointId'), false);
      expect(map.containsKey('endPointId'), false);
      expect(map.containsKey('waypointIds'), false);
      expect(map.containsKey('plannedPath'), false);
      expect(map.containsKey('narrationEntries'), false);
      expect(map.containsKey('rejectionNotes'), false);

      // Always-present fields
      expect(map.containsKey('checkpointIds'), true);
      expect(map.containsKey('routeLengthKm'), true);
      expect(map.containsKey('sequence'), true);
      expect(map.containsKey('status'), true);
      expect(map.containsKey('isVerified'), true);
      expect(map.containsKey('approvalStatus'), true);
      expect(map.containsKey('isApproved'), true); // backward compat
    });

    test(
        'backward compat: fromMap with isApproved=true and no approvalStatus derives approved',
        () {
      final map = <String, dynamic>{
        'checkpointIds': ['cp1'],
        'routeLengthKm': 1.0,
        'sequence': ['cp1'],
        'isApproved': true,
        // no 'approvalStatus' key
      };

      final route = AssignedRoute.fromMap(map);
      expect(route.approvalStatus, 'approved');
      expect(route.isApproved, true);
    });

    test(
        'backward compat: fromMap with isApproved=false and no approvalStatus derives not_submitted',
        () {
      final map = <String, dynamic>{
        'checkpointIds': ['cp1'],
        'routeLengthKm': 1.0,
        'sequence': ['cp1'],
        'isApproved': false,
        // no 'approvalStatus' key
      };

      final route = AssignedRoute.fromMap(map);
      expect(route.approvalStatus, 'not_submitted');
      expect(route.isApproved, false);
    });

    test(
        'backward compat: fromMap without isApproved AND without approvalStatus defaults to not_submitted',
        () {
      final map = <String, dynamic>{
        'checkpointIds': ['cp1'],
        'routeLengthKm': 1.0,
        'sequence': ['cp1'],
        // neither isApproved nor approvalStatus
      };

      final route = AssignedRoute.fromMap(map);
      expect(route.approvalStatus, 'not_submitted');
      expect(route.isApproved, false);
    });

    test('toMap includes isApproved for backward compatibility', () {
      const route = AssignedRoute(
        checkpointIds: ['cp1'],
        routeLengthKm: 1.0,
        sequence: ['cp1'],
        approvalStatus: 'approved',
      );

      final map = route.toMap();
      expect(map['isApproved'], true);
      expect(map['approvalStatus'], 'approved');
    });

    test('narrationEntries serialization roundtrip', () {
      const route = AssignedRoute(
        checkpointIds: ['cp1', 'cp2'],
        routeLengthKm: 5.0,
        sequence: ['cp1', 'cp2'],
        narrationEntries: [
          NarrationEntry(
            index: 1,
            pointName: 'Start Point',
            segmentKm: '0.0',
            cumulativeKm: '0.0',
            bearing: '000 N',
          ),
          NarrationEntry(
            index: 2,
            pointName: 'Checkpoint Alpha',
            segmentKm: '2.5',
            cumulativeKm: '2.5',
            bearing: '090 E',
            description: 'Follow the ridge',
            action: 'Descend',
            elevationM: 250.0,
            walkingTimeMin: 45.0,
            obstacles: 'Steep slope',
          ),
        ],
      );

      final map = route.toMap();
      final restored = AssignedRoute.fromMap(map);

      expect(restored.narrationEntries.length, 2);
      expect(restored.narrationEntries[0].pointName, 'Start Point');
      expect(restored.narrationEntries[1].elevationM, 250.0);
      expect(restored.narrationEntries[1].walkingTimeMin, 45.0);
      expect(restored.narrationEntries[1].obstacles, 'Steep slope');
      expect(restored.narrationEntries, equals(route.narrationEntries));
    });
  });

  // ---------------------------------------------------------------------------
  // DistributionResult
  // ---------------------------------------------------------------------------
  group('DistributionResult', () {
    test('success result: isSuccess=true, needsApproval=false', () {
      final result = DistributionResult(
        status: 'success',
        routes: {
          'nav1': const AssignedRoute(
            checkpointIds: ['cp1', 'cp2'],
            routeLengthKm: 3.0,
            sequence: ['cp1', 'cp2'],
          ),
        },
      );

      expect(result.isSuccess, true);
      expect(result.needsApproval, false);
      expect(result.hasSharedCheckpoints, false);
      expect(result.sharedCheckpointCount, 0);
      expect(result.approvalOptions, isEmpty);
    });

    test('needs_approval with approvalOptions', () {
      final result = DistributionResult(
        status: 'needs_approval',
        routes: {
          'nav1': const AssignedRoute(
            checkpointIds: ['cp1'],
            routeLengthKm: 1.0,
            sequence: ['cp1'],
            status: 'too_short',
          ),
        },
        approvalOptions: const [
          ApprovalOption(
            type: 'expand_range',
            label: 'Expand distance range',
            expandedMin: 1.0,
            expandedMax: 8.0,
          ),
          ApprovalOption(
            type: 'accept_best',
            label: 'Accept best available',
            outOfRangeCount: 2,
          ),
        ],
      );

      expect(result.isSuccess, false);
      expect(result.needsApproval, true);
      expect(result.approvalOptions.length, 2);
      expect(result.approvalOptions[0].type, 'expand_range');
      expect(result.approvalOptions[1].type, 'accept_best');
    });

    test('hasSharedCheckpoints and sharedCheckpointCount', () {
      const result = DistributionResult(
        status: 'success',
        routes: {},
        hasSharedCheckpoints: true,
        sharedCheckpointCount: 5,
      );

      expect(result.hasSharedCheckpoints, true);
      expect(result.sharedCheckpointCount, 5);
    });

    test('empty routes map', () {
      const result = DistributionResult(
        status: 'success',
        routes: {},
      );

      expect(result.routes, isEmpty);
      expect(result.isSuccess, true);
    });

    test('Equatable: same values are equal', () {
      const result1 = DistributionResult(
        status: 'success',
        routes: {},
        hasSharedCheckpoints: true,
        sharedCheckpointCount: 3,
      );

      const result2 = DistributionResult(
        status: 'success',
        routes: {},
        hasSharedCheckpoints: true,
        sharedCheckpointCount: 3,
      );

      expect(result1, equals(result2));
    });

    test('Equatable: different values are not equal', () {
      const result1 = DistributionResult(
        status: 'success',
        routes: {},
      );

      const result2 = DistributionResult(
        status: 'needs_approval',
        routes: {},
      );

      expect(result1, isNot(equals(result2)));
    });
  });

  // ---------------------------------------------------------------------------
  // ApprovalOption
  // ---------------------------------------------------------------------------
  group('ApprovalOption', () {
    test('expand_range with expandedMin/expandedMax', () {
      const option = ApprovalOption(
        type: 'expand_range',
        label: 'Expand distance range to 1-8 km',
        expandedMin: 1.0,
        expandedMax: 8.0,
      );

      expect(option.type, 'expand_range');
      expect(option.label, 'Expand distance range to 1-8 km');
      expect(option.expandedMin, 1.0);
      expect(option.expandedMax, 8.0);
      expect(option.reducedCheckpoints, isNull);
      expect(option.outOfRangeCount, isNull);
    });

    test('reduce_checkpoints with reducedCheckpoints', () {
      const option = ApprovalOption(
        type: 'reduce_checkpoints',
        label: 'Reduce to 4 checkpoints per navigator',
        reducedCheckpoints: 4,
      );

      expect(option.type, 'reduce_checkpoints');
      expect(option.reducedCheckpoints, 4);
      expect(option.expandedMin, isNull);
      expect(option.expandedMax, isNull);
      expect(option.outOfRangeCount, isNull);
    });

    test('accept_best with outOfRangeCount', () {
      const option = ApprovalOption(
        type: 'accept_best',
        label: 'Accept best available routes',
        outOfRangeCount: 3,
      );

      expect(option.type, 'accept_best');
      expect(option.outOfRangeCount, 3);
      expect(option.expandedMin, isNull);
      expect(option.reducedCheckpoints, isNull);
    });

    test('Equatable: same values are equal, different are not', () {
      const option1 = ApprovalOption(
        type: 'expand_range',
        label: 'Expand',
        expandedMin: 1.0,
        expandedMax: 8.0,
      );

      const option2 = ApprovalOption(
        type: 'expand_range',
        label: 'Expand',
        expandedMin: 1.0,
        expandedMax: 8.0,
      );

      const option3 = ApprovalOption(
        type: 'expand_range',
        label: 'Expand',
        expandedMin: 2.0, // different
        expandedMax: 8.0,
      );

      expect(option1, equals(option2));
      expect(option1.hashCode, equals(option2.hashCode));
      expect(option1, isNot(equals(option3)));
    });
  });

  // ---------------------------------------------------------------------------
  // RouteLengthRange
  // ---------------------------------------------------------------------------
  group('RouteLengthRange', () {
    test('toMap/fromMap roundtrip', () {
      const range = RouteLengthRange(min: 2.5, max: 7.0);
      final map = range.toMap();

      expect(map, {'min': 2.5, 'max': 7.0});

      final restored = RouteLengthRange.fromMap(map);
      expect(restored, equals(range));
      expect(restored.min, 2.5);
      expect(restored.max, 7.0);
    });

    test('fromMap handles integer values by converting to double', () {
      final map = <String, dynamic>{'min': 3, 'max': 10};
      final range = RouteLengthRange.fromMap(map);

      expect(range.min, 3.0);
      expect(range.max, 10.0);
    });

    test('Equatable: same values are equal, different are not', () {
      const range1 = RouteLengthRange(min: 1.0, max: 5.0);
      const range2 = RouteLengthRange(min: 1.0, max: 5.0);
      const range3 = RouteLengthRange(min: 1.0, max: 6.0);

      expect(range1, equals(range2));
      expect(range1.hashCode, equals(range2.hashCode));
      expect(range1, isNot(equals(range3)));
    });
  });

  // ---------------------------------------------------------------------------
  // Coordinate
  // ---------------------------------------------------------------------------
  group('Coordinate', () {
    test('toMap/fromMap roundtrip', () {
      const coord = Coordinate(lat: 31.7683, lng: 35.2137, utm: '123456789012');
      final map = coord.toMap();

      expect(map, {'lat': 31.7683, 'lng': 35.2137, 'utm': '123456789012'});

      final restored = Coordinate.fromMap(map);
      expect(restored, equals(coord));
    });

    test('Equatable', () {
      const c1 = Coordinate(lat: 31.0, lng: 34.0, utm: '000000000000');
      const c2 = Coordinate(lat: 31.0, lng: 34.0, utm: '000000000000');
      const c3 = Coordinate(lat: 32.0, lng: 34.0, utm: '000000000000');

      expect(c1, equals(c2));
      expect(c1, isNot(equals(c3)));
    });
  });

  // ---------------------------------------------------------------------------
  // NarrationEntry
  // ---------------------------------------------------------------------------
  group('NarrationEntry', () {
    test('toMap/fromMap roundtrip with all fields', () {
      const entry = NarrationEntry(
        index: 3,
        segmentKm: '2.1',
        pointName: 'Ridge Top',
        cumulativeKm: '6.3',
        bearing: '180 S',
        description: 'Follow south trail',
        action: 'Continue straight',
        elevationM: 450.0,
        walkingTimeMin: 35.0,
        obstacles: 'Dense vegetation',
      );

      final map = entry.toMap();
      final restored = NarrationEntry.fromMap(map);

      expect(restored, equals(entry));
      expect(restored.index, 3);
      expect(restored.segmentKm, '2.1');
      expect(restored.pointName, 'Ridge Top');
      expect(restored.cumulativeKm, '6.3');
      expect(restored.bearing, '180 S');
      expect(restored.description, 'Follow south trail');
      expect(restored.action, 'Continue straight');
      expect(restored.elevationM, 450.0);
      expect(restored.walkingTimeMin, 35.0);
      expect(restored.obstacles, 'Dense vegetation');
    });

    test('fromMap with minimal fields uses defaults', () {
      final map = <String, dynamic>{
        'index': 1,
        'pointName': 'Checkpoint A',
      };

      final entry = NarrationEntry.fromMap(map);

      expect(entry.index, 1);
      expect(entry.pointName, 'Checkpoint A');
      expect(entry.segmentKm, '');
      expect(entry.cumulativeKm, '');
      expect(entry.bearing, '');
      expect(entry.description, '');
      expect(entry.action, '');
      expect(entry.elevationM, isNull);
      expect(entry.walkingTimeMin, isNull);
      expect(entry.obstacles, '');
    });

    test('toMap conditionally omits null elevation and walkingTime', () {
      const entry = NarrationEntry(
        index: 1,
        pointName: 'Test',
      );

      final map = entry.toMap();
      expect(map.containsKey('elevationM'), false);
      expect(map.containsKey('walkingTimeMin'), false);
    });

    test('toMap includes elevation and walkingTime when present', () {
      const entry = NarrationEntry(
        index: 1,
        pointName: 'Test',
        elevationM: 100.0,
        walkingTimeMin: 20.0,
      );

      final map = entry.toMap();
      expect(map['elevationM'], 100.0);
      expect(map['walkingTimeMin'], 20.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Navigation - route fields
  // ---------------------------------------------------------------------------
  group('Navigation - route fields', () {
    test('routesStage defaults to null, routesDistributed defaults to false',
        () {
      final map = buildMinimalNavigationMap();
      final nav = Navigation.fromMap(map);

      expect(nav.routesStage, isNull);
      expect(nav.routesDistributed, false);
      expect(nav.routes, isEmpty);
    });

    test(
        'toMap/fromMap with routes populated, routesStage=verification, routesDistributed=true',
        () {
      final routeMap = const AssignedRoute(
        checkpointIds: ['cp1', 'cp2', 'cp3'],
        routeLengthKm: 5.2,
        sequence: ['cp1', 'cp3', 'cp2'],
        startPointId: 'start-1',
        endPointId: 'end-1',
        status: 'optimal',
        isVerified: true,
        approvalStatus: 'approved',
        plannedPath: [
          Coordinate(lat: 31.0, lng: 34.0, utm: '111111222222'),
        ],
        narrationEntries: [
          NarrationEntry(index: 1, pointName: 'First'),
        ],
      ).toMap();

      final navMap = buildMinimalNavigationMap({
        'routes': {
          'navigator-001': routeMap,
          'navigator-002': const AssignedRoute(
            checkpointIds: ['cp4', 'cp5'],
            routeLengthKm: 3.8,
            sequence: ['cp4', 'cp5'],
          ).toMap(),
        },
        'routesStage': 'verification',
        'routesDistributed': true,
      });

      final nav = Navigation.fromMap(navMap);

      expect(nav.routes.length, 2);
      expect(nav.routes.containsKey('navigator-001'), true);
      expect(nav.routes.containsKey('navigator-002'), true);
      expect(nav.routes['navigator-001']!.checkpointIds, ['cp1', 'cp2', 'cp3']);
      expect(nav.routes['navigator-001']!.routeLengthKm, 5.2);
      expect(nav.routes['navigator-001']!.startPointId, 'start-1');
      expect(nav.routes['navigator-001']!.isVerified, true);
      expect(nav.routes['navigator-001']!.isApproved, true);
      expect(nav.routes['navigator-001']!.plannedPath.length, 1);
      expect(nav.routes['navigator-001']!.narrationEntries.length, 1);
      expect(nav.routes['navigator-002']!.routeLengthKm, 3.8);
      expect(nav.routesStage, 'verification');
      expect(nav.routesDistributed, true);

      // Roundtrip: toMap -> fromMap
      final serialized = nav.toMap();
      final restored = Navigation.fromMap(serialized);

      expect(restored.routes.length, 2);
      expect(restored.routesStage, 'verification');
      expect(restored.routesDistributed, true);
      expect(restored.routes['navigator-001']!.checkpointIds,
          ['cp1', 'cp2', 'cp3']);
      expect(
          restored.routes['navigator-001']!.approvalStatus, 'approved');
    });

    test(
        'backward compat: fromMap without routesStage/routesDistributed gives defaults',
        () {
      final navMap = buildMinimalNavigationMap();
      // Ensure the keys are not present
      navMap.remove('routesStage');
      navMap.remove('routesDistributed');

      final nav = Navigation.fromMap(navMap);

      expect(nav.routesStage, isNull);
      expect(nav.routesDistributed, false);
    });

    test('copyWith routes/routesStage/routesDistributed', () {
      final navMap = buildMinimalNavigationMap();
      final nav = Navigation.fromMap(navMap);

      expect(nav.routes, isEmpty);
      expect(nav.routesStage, isNull);
      expect(nav.routesDistributed, false);

      final updated = nav.copyWith(
        routes: {
          'nav-100': const AssignedRoute(
            checkpointIds: ['x1', 'x2'],
            routeLengthKm: 6.0,
            sequence: ['x1', 'x2'],
            status: 'needs_adjustment',
          ),
        },
        routesStage: 'editing',
        routesDistributed: true,
      );

      expect(updated.routes.length, 1);
      expect(updated.routes['nav-100']!.routeLengthKm, 6.0);
      expect(updated.routes['nav-100']!.status, 'needs_adjustment');
      expect(updated.routesStage, 'editing');
      expect(updated.routesDistributed, true);

      // Original remains unchanged (immutability)
      expect(nav.routes, isEmpty);
      expect(nav.routesStage, isNull);
      expect(nav.routesDistributed, false);
    });

    test('toMap conditionally includes routesStage only when not null', () {
      final navMap = buildMinimalNavigationMap();
      final nav = Navigation.fromMap(navMap);

      final map1 = nav.toMap();
      expect(map1.containsKey('routesStage'), false);
      expect(map1['routesDistributed'], false);

      final navWithStage = nav.copyWith(routesStage: 'ready');
      final map2 = navWithStage.toMap();
      expect(map2['routesStage'], 'ready');
      expect(map2.containsKey('routesStage'), true);
    });

    test('Navigation route fields roundtrip preserves all route stages', () {
      for (final stage in [
        'not_started',
        'setup',
        'verification',
        'editing',
        'ready',
      ]) {
        final navMap = buildMinimalNavigationMap({
          'routesStage': stage,
          'routesDistributed': stage == 'ready',
        });

        final nav = Navigation.fromMap(navMap);
        expect(nav.routesStage, stage);

        final serialized = nav.toMap();
        final restored = Navigation.fromMap(serialized);
        expect(restored.routesStage, stage);
      }
    });

    test('Navigation with multiple routes serializes all route details', () {
      final routes = <String, dynamic>{};
      for (int i = 0; i < 5; i++) {
        routes['nav-$i'] = AssignedRoute(
          checkpointIds: ['cp-${i * 2}', 'cp-${i * 2 + 1}'],
          routeLengthKm: 2.0 + i * 0.5,
          sequence: ['cp-${i * 2}', 'cp-${i * 2 + 1}'],
          status: i % 2 == 0 ? 'optimal' : 'too_short',
        ).toMap();
      }

      final navMap = buildMinimalNavigationMap({
        'routes': routes,
        'routesStage': 'verification',
        'routesDistributed': true,
      });

      final nav = Navigation.fromMap(navMap);
      expect(nav.routes.length, 5);

      for (int i = 0; i < 5; i++) {
        final route = nav.routes['nav-$i']!;
        expect(route.routeLengthKm, 2.0 + i * 0.5);
        expect(route.status, i % 2 == 0 ? 'optimal' : 'too_short');
      }

      // Full roundtrip
      final restored = Navigation.fromMap(nav.toMap());
      expect(restored.routes.length, 5);
      expect(
          restored.routes['nav-3']!.routeLengthKm, nav.routes['nav-3']!.routeLengthKm);
    });
  });
}
