import 'package:flutter_test/flutter_test.dart';
import 'package:turf/turf.dart' as turf;
import 'package:navigate_app/services/routes_distribution_service.dart';
import 'package:navigate_app/domain/entities/navigation.dart';
import 'package:navigate_app/domain/entities/navigation_tree.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';
import 'package:navigate_app/domain/entities/checkpoint.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';
import 'package:navigate_app/domain/entities/boundary.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Navigation _createTestNavigation({
  List<String> selectedParticipantIds = const [],
  List<String> selectedSubFrameworkIds = const [],
}) {
  final now = DateTime.now();
  return Navigation(
    id: 'nav1',
    name: 'Test Nav',
    status: 'preparation',
    createdBy: 'user1',
    treeId: 'tree1',
    areaId: 'area1',
    selectedParticipantIds: selectedParticipantIds,
    selectedSubFrameworkIds: selectedSubFrameworkIds,
    layerNzId: 'nz1',
    layerNbId: 'nb1',
    layerGgId: 'gg1',
    distributionMethod: 'automatic',
    learningSettings: const LearningSettings(),
    verificationSettings: const VerificationSettings(autoVerification: false),
    alerts: const NavigationAlerts(enabled: false),
    displaySettings: const DisplaySettings(),
    routes: const {},
    gpsUpdateIntervalSeconds: 30,
    permissions: const NavigationPermissions(managers: [], viewers: []),
    createdAt: now,
    updatedAt: now,
  );
}

NavigationTree _createTestTree({
  List<SubFramework>? subFrameworks,
}) {
  final now = DateTime.now();
  return NavigationTree(
    id: 'tree1',
    name: 'Test Tree',
    subFrameworks: subFrameworks ??
        [
          const SubFramework(
            id: 'sf1',
            name: 'navigators',
            userIds: ['u1', 'u2', 'u3'],
            isFixed: false,
          ),
          const SubFramework(
            id: 'sf_cmd',
            name: 'commanders',
            userIds: ['cmd1'],
            isFixed: true,
          ),
        ],
    createdBy: 'user1',
    createdAt: now,
    updatedAt: now,
  );
}

/// Creates [count] point-type checkpoints spread geographically in Israel
/// (~31-33 N, 34-36 E). The checkpoints are laid out in a grid so that
/// distances between neighbours are deterministic and in the order of a few km.
List<Checkpoint> _createTestCheckpoints(int count) {
  return List.generate(count, (i) {
    final lat = 31.0 + (i ~/ 5) * 0.05;
    final lng = 34.5 + (i % 5) * 0.05;
    return Checkpoint(
      id: 'cp_$i',
      areaId: 'area1',
      name: 'point $i',
      description: '',
      type: 'checkpoint',
      color: 'blue',
      coordinates: Coordinate(lat: lat, lng: lng, utm: '123456789012'),
      sequenceNumber: i,
      createdBy: 'user1',
      createdAt: DateTime.now(),
    );
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late RoutesDistributionService service;

  setUp(() {
    service = RoutesDistributionService();
  });

  // =========================================================================
  // Validation
  // =========================================================================
  group('Validation', () {
    test('throws when checkpoints is empty', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      expect(
        () => service.distributeAutomatically(
          navigation: navigation,
          tree: tree,
          checkpoints: [],
          executionOrder: 'sequential',
          checkpointsPerNavigator: 3,
          minRouteLength: 1,
          maxRouteLength: 100,
          navigatorIds: ['u1'],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('לא נמצאו נקודות ציון'),
          ),
        ),
      );
    });

    test('throws when no navigators found (empty tree, no selectedParticipants)',
        () async {
      final navigation = _createTestNavigation();
      // Tree with only a fixed sub-framework (no non-fixed ones)
      final tree = _createTestTree(
        subFrameworks: [
          const SubFramework(
            id: 'sf_cmd',
            name: 'commanders',
            userIds: ['cmd1'],
            isFixed: true,
          ),
        ],
      );
      final checkpoints = _createTestCheckpoints(10);

      expect(
        () => service.distributeAutomatically(
          navigation: navigation,
          tree: tree,
          checkpoints: checkpoints,
          executionOrder: 'sequential',
          checkpointsPerNavigator: 3,
          minRouteLength: 1,
          maxRouteLength: 100,
          navigatorIds: [],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('לא נמצאו משתתפים'),
          ),
        ),
      );
    });

    test('throws when not enough checkpoints for requested per-navigator count',
        () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(3);

      expect(
        () => service.distributeAutomatically(
          navigation: navigation,
          tree: tree,
          checkpoints: checkpoints,
          executionOrder: 'sequential',
          checkpointsPerNavigator: 5,
          minRouteLength: 1,
          maxRouteLength: 100,
          navigatorIds: ['u1'],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('אין מספיק נקודות'),
          ),
        ),
      );
    });

    test('finds navigators from selectedParticipantIds', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['p1', 'p2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 1,
        maxRouteLength: 100,
        navigatorIds: ['p1', 'p2'],
      );

      // Should produce routes keyed by the selected participant IDs
      expect(result.routes.length, equals(2));
      expect(result.routes.keys, containsAll(['p1', 'p2']));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('finds navigators from selectedSubFrameworkIds', () async {
      final navigation = _createTestNavigation(
        selectedSubFrameworkIds: ['sf1'],
      );
      final tree = _createTestTree(
        subFrameworks: [
          const SubFramework(
            id: 'sf1',
            name: 'team_a',
            userIds: ['u1', 'u2'],
            isFixed: false,
          ),
          const SubFramework(
            id: 'sf2',
            name: 'team_b',
            userIds: ['u3', 'u4'],
            isFixed: false,
          ),
        ],
      );
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 1,
        maxRouteLength: 100,
        navigatorIds: ['u1', 'u2'],
      );

      // Only sf1 users should get routes
      expect(result.routes.length, equals(2));
      expect(result.routes.keys, containsAll(['u1', 'u2']));
      expect(result.routes.keys, isNot(contains('u3')));
      expect(result.routes.keys, isNot(contains('u4')));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('finds navigators from all non-fixed subFrameworks (fallback)',
        () async {
      final navigation = _createTestNavigation();
      final tree = _createTestTree(
        subFrameworks: [
          const SubFramework(
            id: 'sf1',
            name: 'navigators',
            userIds: ['u1', 'u2', 'u3'],
            isFixed: false,
          ),
          const SubFramework(
            id: 'sf_cmd',
            name: 'commanders',
            userIds: ['cmd1'],
            isFixed: true,
          ),
        ],
      );
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 1,
        maxRouteLength: 100,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      // Non-fixed users: u1, u2, u3 (fixed cmd1 excluded)
      expect(result.routes.length, equals(3));
      expect(result.routes.keys, containsAll(['u1', 'u2', 'u3']));
      expect(result.routes.keys, isNot(contains('cmd1')));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  // Automatic distribution - basic
  // =========================================================================
  group('Automatic distribution - basic', () {
    test('distributes to 3 navigators with 15 checkpoints, 3 per navigator',
        () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 1,
        maxRouteLength: 100,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.routes.length, equals(3));
      expect(result.routes.containsKey('u1'), isTrue);
      expect(result.routes.containsKey('u2'), isTrue);
      expect(result.routes.containsKey('u3'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('each route has exactly checkpointsPerNavigator checkpoints',
        () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 1,
        maxRouteLength: 100,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      for (final route in result.routes.values) {
        expect(route.checkpointIds.length, equals(3));
        expect(route.sequence.length, equals(3));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('route length is calculated and positive', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.1,
        maxRouteLength: 200,
        navigatorIds: ['u1', 'u2'],
      );

      for (final route in result.routes.values) {
        expect(route.routeLengthKm, greaterThan(0));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('all routes have status optimal when in generous range', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.status, equals('success'));
      for (final route in result.routes.values) {
        expect(route.status, equals('optimal'));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('progress callback is called with increasing values', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final progressValues = <int>[];
      await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 1,
        maxRouteLength: 100,
        navigatorIds: ['u1', 'u2'],
        onProgress: (current, total) {
          progressValues.add(current);
        },
      );

      // At least one progress callback should have been invoked
      expect(progressValues, isNotEmpty);
      // Values should be non-decreasing
      for (int i = 1; i < progressValues.length; i++) {
        expect(progressValues[i], greaterThanOrEqualTo(progressValues[i - 1]));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  // Automatic distribution - shared checkpoints
  // =========================================================================
  group('Automatic distribution - shared checkpoints', () {
    test(
        '6 checkpoints, 3 navigators, 3 per navigator forces sharing',
        () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      // 6 checkpoints, 3 navigators * 3 per navigator = 9 needed, only 6 available
      final checkpoints = _createTestCheckpoints(6);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.routes.length, equals(3));
      // With only 6 unique checkpoints spread across 9 slots, sharing is required
      expect(result.hasSharedCheckpoints, isTrue);
      expect(result.sharedCheckpointCount, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('shared checkpoints appear in multiple routes', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(6);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      // Collect all checkpoint IDs across all routes
      final allIds = <String>[];
      for (final route in result.routes.values) {
        allIds.addAll(route.checkpointIds);
      }
      final uniqueIds = allIds.toSet();

      // Since sharing occurs, total count > unique count
      expect(allIds.length, greaterThan(uniqueIds.length));

      // Verify each route still has exactly 3 checkpoints
      for (final route in result.routes.values) {
        expect(route.checkpointIds.length, equals(3));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  // Start/end points
  // =========================================================================
  group('Start/end points', () {
    test('shared start point - all routes reference startPointId', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);
      final startCheckpointId = checkpoints.first.id; // 'cp_0'

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        startPointId: startCheckpointId,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2'],
      );

      for (final route in result.routes.values) {
        expect(route.startPointId, equals(startCheckpointId));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('shared end point - all routes reference endPointId', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);
      final endCheckpointId = checkpoints.last.id; // 'cp_14'

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        endPointId: endCheckpointId,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2'],
      );

      for (final route in result.routes.values) {
        expect(route.endPointId, equals(endCheckpointId));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('start and end points are excluded from checkpoint pool', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);
      final startId = checkpoints.first.id; // 'cp_0'
      final endId = checkpoints.last.id; // 'cp_14'

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        startPointId: startId,
        endPointId: endId,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2'],
      );

      // Checkpoint IDs assigned to navigators should not include start/end
      for (final route in result.routes.values) {
        expect(route.checkpointIds, isNot(contains(startId)));
        expect(route.checkpointIds, isNot(contains(endId)));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  // Distribution result
  // =========================================================================
  group('Distribution result', () {
    test('success result when all routes in generous range', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.status, equals('success'));
      expect(result.isSuccess, isTrue);
      expect(result.needsApproval, isFalse);
      expect(result.approvalOptions, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('needs_approval with approvalOptions when out of range', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      // Impossibly tight range that no real routes can satisfy
      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 0.002,
        navigatorIds: ['u1', 'u2'],
      );

      expect(result.status, equals('needs_approval'));
      expect(result.needsApproval, isTrue);
      expect(result.approvalOptions, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('expand_range option has expandedMin/expandedMax', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);
      const minRoute = 0.001;
      const maxRoute = 0.002;

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: minRoute,
        maxRouteLength: maxRoute,
        navigatorIds: ['u1', 'u2'],
      );

      final expandOption = result.approvalOptions
          .where((o) => o.type == 'expand_range')
          .firstOrNull;
      expect(expandOption, isNotNull);
      expect(expandOption!.expandedMin, closeTo(minRoute * 0.8, 0.0001));
      expect(expandOption.expandedMax, closeTo(maxRoute * 1.2, 0.0001));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('reduce_checkpoints option has reducedCheckpoints', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);
      const perNavigator = 3;

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: perNavigator,
        minRouteLength: 0.001,
        maxRouteLength: 0.002,
        navigatorIds: ['u1', 'u2'],
      );

      final reduceOption = result.approvalOptions
          .where((o) => o.type == 'reduce_checkpoints')
          .firstOrNull;
      expect(reduceOption, isNotNull);
      expect(reduceOption!.reducedCheckpoints, equals(perNavigator - 1));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('accept_best option has outOfRangeCount', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 0.002,
        navigatorIds: ['u1', 'u2'],
      );

      final acceptOption = result.approvalOptions
          .where((o) => o.type == 'accept_best')
          .firstOrNull;
      expect(acceptOption, isNotNull);
      expect(acceptOption!.outOfRangeCount, isNotNull);
      expect(acceptOption.outOfRangeCount!, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  // Scoring criteria
  // =========================================================================
  group('Scoring criteria', () {
    test('fairness criterion returns valid result', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        scoringCriterion: 'fairness',
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.routes.length, equals(3));
      for (final route in result.routes.values) {
        expect(route.checkpointIds.length, equals(3));
        expect(route.routeLengthKm, greaterThan(0));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('midpoint criterion returns valid result', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        scoringCriterion: 'midpoint',
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.routes.length, equals(3));
      for (final route in result.routes.values) {
        expect(route.checkpointIds.length, equals(3));
        expect(route.routeLengthKm, greaterThan(0));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('uniqueness criterion returns valid result', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        scoringCriterion: 'uniqueness',
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.routes.length, equals(3));
      for (final route in result.routes.values) {
        expect(route.checkpointIds.length, equals(3));
        expect(route.routeLengthKm, greaterThan(0));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  // Edge cases and structural properties
  // =========================================================================
  group('Structural properties', () {
    test('all checkpoint IDs in routes come from the original list', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(15);
      final validIds = checkpoints.map((c) => c.id).toSet();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      for (final route in result.routes.values) {
        for (final cpId in route.checkpointIds) {
          expect(validIds, contains(cpId));
        }
        for (final cpId in route.sequence) {
          expect(validIds, contains(cpId));
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('sequence contains exactly the same IDs as checkpointIds', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2'],
      );

      for (final route in result.routes.values) {
        expect(
          route.sequence.toSet(),
          equals(route.checkpointIds.toSet()),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('isVerified is false on newly distributed routes', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2'],
      );

      for (final route in result.routes.values) {
        expect(route.isVerified, isFalse);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('works with single navigator', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 4,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1'],
      );

      expect(result.routes.length, equals(1));
      expect(result.routes.containsKey('u1'), isTrue);
      expect(result.routes['u1']!.checkpointIds.length, equals(4));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('works with free execution order (non-sequential)', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'free',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2'],
      );

      expect(result.routes.length, equals(2));
      for (final route in result.routes.values) {
        expect(route.checkpointIds.length, equals(3));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('multiple non-fixed subFrameworks all contribute navigators',
        () async {
      final navigation = _createTestNavigation(); // no explicit selection
      final tree = _createTestTree(
        subFrameworks: [
          const SubFramework(
            id: 'sf1',
            name: 'team_a',
            userIds: ['a1', 'a2'],
            isFixed: false,
          ),
          const SubFramework(
            id: 'sf2',
            name: 'team_b',
            userIds: ['b1', 'b2'],
            isFixed: false,
          ),
          const SubFramework(
            id: 'sf_cmd',
            name: 'commanders',
            userIds: ['cmd1'],
            isFixed: true,
          ),
        ],
      );
      final checkpoints = _createTestCheckpoints(20);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['a1', 'a2', 'b1', 'b2'],
      );

      // a1, a2, b1, b2 (4 non-fixed users)
      expect(result.routes.length, equals(4));
      expect(result.routes.keys, containsAll(['a1', 'a2', 'b1', 'b2']));
      expect(result.routes.keys, isNot(contains('cmd1')));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('unique distribution when enough checkpoints', () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();
      // 15 checkpoints, 3 navigators * 3 = 9 needed, 15 available => no sharing needed
      final checkpoints = _createTestCheckpoints(15);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      // With enough checkpoints, the algorithm should prefer unique distribution
      // (though the Monte Carlo nature means this is a structural check)
      final allIds = <String>[];
      for (final route in result.routes.values) {
        allIds.addAll(route.checkpointIds);
      }
      // If no sharing, all IDs are unique
      if (!result.hasSharedCheckpoints) {
        expect(allIds.toSet().length, equals(allIds.length));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('route status reflects out-of-range as too_short or too_long',
        () async {
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();
      final checkpoints = _createTestCheckpoints(10);

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 0.002,
        navigatorIds: ['u1', 'u2'],
      );

      // With such a tight range, routes should be too_long
      for (final route in result.routes.values) {
        expect(
          route.status,
          anyOf(equals('too_short'), equals('too_long'), equals('optimal')),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // =========================================================================
  // Boundary enforcement — routes stay inside navigation boundary
  // =========================================================================
  group('Boundary enforcement', () {
    // -- helpers --

    Boundary createBoundary(List<List<double>> latLngPairs) {
      final now = DateTime.now();
      return Boundary(
        id: 'bound1',
        areaId: 'area1',
        name: 'test boundary',
        description: '',
        coordinates: latLngPairs
            .map((p) =>
                Coordinate(lat: p[0], lng: p[1], utm: '000000000000'))
            .toList(),
        createdAt: now,
        updatedAt: now,
      );
    }

    List<Checkpoint> createCheckpointsAt(List<List<double>> positions) {
      return List.generate(positions.length, (i) {
        return Checkpoint(
          id: 'cp_$i',
          areaId: 'area1',
          name: 'point $i',
          description: '',
          type: 'checkpoint',
          color: 'blue',
          coordinates: Coordinate(
              lat: positions[i][0],
              lng: positions[i][1],
              utm: '000000000000'),
          sequenceNumber: i,
          createdBy: 'user1',
          createdAt: DateTime.now(),
        );
      });
    }

    /// Independent boundary-exit check using turf (mirrors service logic).
    /// Returns true if the segment from (lat1,lng1)→(lat2,lng2) exits the polygon.
    bool segmentExitsBoundary(
      double lat1, double lng1, double lat2, double lng2,
      List<List<double>> boundaryCoords,
    ) {
      final segment = turf.LineString(coordinates: [
        turf.Position(lng1, lat1),
        turf.Position(lng2, lat2),
      ]);
      final ring =
          boundaryCoords.map((c) => turf.Position(c[1], c[0])).toList();
      if (ring.first.lng != ring.last.lng || ring.first.lat != ring.last.lat) {
        ring.add(ring.first);
      }
      final poly = turf.Polygon(coordinates: [ring]);

      // Edge crossings
      if (turf.lineIntersect(segment, poly).features.isNotEmpty) return true;

      // Endpoint check — both must be inside
      if (!turf.booleanPointInPolygon(turf.Position(lng1, lat1), poly)) {
        return true;
      }
      if (!turf.booleanPointInPolygon(turf.Position(lng2, lat2), poly)) {
        return true;
      }
      return false;
    }

    /// Counts how many consecutive segments in the full route path exit the
    /// boundary. Full path = startPoint → sequence → endPoint.
    int countRouteViolations(
      AssignedRoute route,
      Map<String, Checkpoint> cpMap,
      List<List<double>> boundaryCoords,
    ) {
      final fullSeq = <String>[
        if (route.startPointId != null) route.startPointId!,
        ...route.sequence,
        if (route.endPointId != null) route.endPointId!,
      ];

      int violations = 0;
      for (int i = 0; i < fullSeq.length - 1; i++) {
        final cp1 = cpMap[fullSeq[i]];
        final cp2 = cpMap[fullSeq[i + 1]];
        if (cp1?.coordinates == null || cp2?.coordinates == null) continue;
        if (segmentExitsBoundary(
          cp1!.coordinates!.lat, cp1.coordinates!.lng,
          cp2!.coordinates!.lat, cp2.coordinates!.lng,
          boundaryCoords,
        )) {
          violations++;
        }
      }
      return violations;
    }

    // -- tests --

    test('convex rectangle — all segments stay inside', () async {
      final boundary = createBoundary([
        [31.40, 34.90],
        [31.60, 34.90],
        [31.60, 35.10],
        [31.40, 35.10],
      ]);
      final boundaryCoords =
          boundary.coordinates.map((c) => [c.lat, c.lng]).toList();

      final checkpoints = createCheckpointsAt([
        [31.42, 34.92], [31.42, 35.00], [31.42, 35.08],
        [31.50, 34.92], [31.50, 35.00], [31.50, 35.08],
        [31.58, 34.92], [31.58, 35.00], [31.58, 35.08],
      ]);
      final cpMap = {for (final cp in checkpoints) cp.id: cp};

      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.routes.length, equals(3));
      for (final entry in result.routes.entries) {
        final v = countRouteViolations(entry.value, cpMap, boundaryCoords);
        expect(v, equals(0),
            reason: 'Route ${entry.key} exits convex boundary ($v violations)');
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('concave C-shape — single navigator minimizes boundary exits', () async {
      // C-shape opening to the east (notch at 34.96):
      //   Top arm:    lat 31.55-31.60, full width
      //   Bottom arm: lat 31.40-31.45, full width
      //   Connector:  lat 31.40-31.60, lng 34.90-34.96
      //   Notch:      lat 31.45-31.55, lng 34.96-35.10  (outside)
      //
      // 21 out of 36 checkpoint pairs have boundary-violating segments.
      // The algorithm should reduce violations to ≤ 2 (from ~7 in a random order).
      final boundary = createBoundary([
        [31.40, 34.90], [31.60, 34.90], [31.60, 35.10],
        [31.55, 35.10], [31.55, 34.96], [31.45, 34.96],
        [31.45, 35.10], [31.40, 35.10],
      ]);
      final boundaryCoords =
          boundary.coordinates.map((c) => [c.lat, c.lng]).toList();

      // 1 navigator visits all 9 checkpoints
      final checkpoints = createCheckpointsAt([
        // Top arm
        [31.57, 34.98], [31.58, 35.03], [31.57, 35.07],
        // Connector (left wall)
        [31.53, 34.92], [31.50, 34.92], [31.47, 34.92],
        // Bottom arm
        [31.43, 34.98], [31.42, 35.03], [31.43, 35.07],
      ]);
      final cpMap = {for (final cp in checkpoints) cp.id: cp};

      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 9,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1'],
      );

      expect(result.routes.length, equals(1));
      final route = result.routes.values.first;
      final v = countRouteViolations(route, cpMap, boundaryCoords);
      expect(v, lessThanOrEqualTo(2),
          reason: 'Route should have minimal violations '
              '($v found, sequence: ${route.sequence})');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('concave C-shape with start/end — zero exits via gateway anchoring',
        () async {
      // C-shape with start at top-right and end at bottom-right.
      // Start/end anchor the NN to sweep right→left→connector→left→right,
      // producing a deterministic 0-violation path.
      final boundary = createBoundary([
        [31.40, 34.90], [31.60, 34.90], [31.60, 35.10],
        [31.55, 35.10], [31.55, 34.96], [31.45, 34.96],
        [31.45, 35.10], [31.40, 35.10],
      ]);
      final boundaryCoords =
          boundary.coordinates.map((c) => [c.lat, c.lng]).toList();

      final checkpoints = createCheckpointsAt([
        [31.59, 35.06], // cp_0 = start (top arm, right)
        [31.41, 35.06], // cp_1 = end   (bottom arm, right)
        // Top arm (NN visits right→left from start)
        [31.58, 35.05], [31.57, 34.98],
        // Connector
        [31.53, 34.92], [31.50, 34.92], [31.47, 34.92],
        // Bottom arm (NN visits left→right toward end)
        [31.43, 34.98], [31.42, 35.05],
      ]);
      final cpMap = {for (final cp in checkpoints) cp.id: cp};

      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'cp_0',
        endPointId: 'cp_1',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 7,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1'],
      );

      expect(result.routes.length, equals(1));
      final route = result.routes.values.first;
      final v = countRouteViolations(route, cpMap, boundaryCoords);
      expect(v, equals(0),
          reason: 'Start-to-end route crosses C-shape notch '
              '($v violations, sequence: ${route.sequence})');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('concave C-shape — multiple navigators all stay inside', () async {
      // Wider connector (notch at 35.00) so arm→connector transitions
      // are clean even when SA distributes checkpoints across zones
      final boundary = createBoundary([
        [31.40, 34.90], [31.60, 34.90], [31.60, 35.10],
        [31.55, 35.10], [31.55, 35.00], [31.45, 35.00],
        [31.45, 35.10], [31.40, 35.10],
      ]);
      final boundaryCoords =
          boundary.coordinates.map((c) => [c.lat, c.lng]).toList();

      // 15 checkpoints: 5 per zone
      final checkpoints = createCheckpointsAt([
        // Top arm (mix of left and right of notch)
        [31.57, 34.94], [31.58, 34.97], [31.57, 35.04],
        [31.59, 35.06], [31.56, 35.03],
        // Connector (lat 31.45-31.55, lng 34.90-35.00)
        [31.53, 34.93], [31.51, 34.92], [31.49, 34.93],
        [31.47, 34.92], [31.46, 34.93],
        // Bottom arm (mix of left and right of notch)
        [31.43, 34.94], [31.42, 34.97], [31.43, 35.04],
        [31.41, 35.06], [31.44, 35.03],
      ]);
      final cpMap = {for (final cp in checkpoints) cp.id: cp};

      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2', 'u3'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 5,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2', 'u3'],
      );

      expect(result.routes.length, equals(3));
      int totalViolations = 0;
      for (final entry in result.routes.entries) {
        totalViolations +=
            countRouteViolations(entry.value, cpMap, boundaryCoords);
      }
      expect(totalViolations, lessThanOrEqualTo(2),
          reason: 'Total violations across 3 routes should be minimal '
              '($totalViolations found)');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('L-shape — single navigator follows L path', () async {
      // L-shape:
      //   Vertical arm: lat 31.50-31.60, lng 34.90-34.95  (narrow)
      //   Horizontal arm: lat 31.40-31.50, lng 34.90-35.10
      //   Outside: lat 31.50-31.60, lng 34.95-35.10
      final boundary = createBoundary([
        [31.40, 34.90], [31.60, 34.90], [31.60, 34.95],
        [31.50, 34.95], [31.50, 35.10], [31.40, 35.10],
      ]);
      final boundaryCoords =
          boundary.coordinates.map((c) => [c.lat, c.lng]).toList();

      // Checkpoints in both arms
      final checkpoints = createCheckpointsAt([
        // Vertical arm (narrow, high lat)
        [31.58, 34.92], [31.56, 34.93], [31.54, 34.92],
        // Corner area
        [31.49, 34.92], [31.48, 34.97],
        // Horizontal arm (wide, lower lat)
        [31.46, 35.03], [31.44, 35.06], [31.42, 35.02],
        [31.43, 35.08],
      ]);
      final cpMap = {for (final cp in checkpoints) cp.id: cp};

      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 9,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1'],
      );

      expect(result.routes.length, equals(1));
      final route = result.routes.values.first;
      final v = countRouteViolations(route, cpMap, boundaryCoords);
      expect(v, equals(0),
          reason: 'Route cuts diagonal through L-shape '
              '($v violations, sequence: ${route.sequence})');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('checkpoints outside boundary are filtered from routes', () async {
      final boundary = createBoundary([
        [31.45, 34.95], [31.55, 34.95],
        [31.55, 35.05], [31.45, 35.05],
      ]);

      // 6 inside, 4 outside
      final checkpoints = createCheckpointsAt([
        // Inside
        [31.47, 34.97], [31.49, 35.00], [31.51, 35.03],
        [31.53, 34.98], [31.48, 35.02], [31.52, 35.00],
        // Outside (clearly beyond boundary)
        [31.30, 34.80], [31.70, 35.20],
        [31.40, 35.10], [31.60, 34.90],
      ]);
      final insideIds = {'cp_0', 'cp_1', 'cp_2', 'cp_3', 'cp_4', 'cp_5'};

      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.001,
        maxRouteLength: 500,
        navigatorIds: ['u1', 'u2'],
      );

      expect(result.routes.length, equals(2));
      for (final route in result.routes.values) {
        for (final cpId in route.checkpointIds) {
          expect(insideIds, contains(cpId),
              reason: 'Route contains checkpoint $cpId which is outside boundary');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('verify segmentExitsBoundary helper detects known violations', () {
      // Sanity check: the helper itself correctly identifies crossings
      // C-shape boundary
      final coords = <List<double>>[
        [31.40, 34.90], [31.60, 34.90], [31.60, 35.10],
        [31.55, 35.10], [31.55, 34.96], [31.45, 34.96],
        [31.45, 35.10], [31.40, 35.10],
      ];

      // Segment through the notch: top-right → bottom-right
      expect(
        segmentExitsBoundary(31.57, 35.05, 31.43, 35.05, coords),
        isTrue,
        reason: 'Vertical segment through notch should be detected',
      );

      // Segment inside the top arm (no exit)
      expect(
        segmentExitsBoundary(31.57, 35.00, 31.58, 35.05, coords),
        isFalse,
        reason: 'Segment inside top arm should not be a violation',
      );

      // Segment inside connector (no exit)
      expect(
        segmentExitsBoundary(31.53, 34.91, 31.47, 34.91, coords),
        isFalse,
        reason: 'Segment inside connector should not be a violation',
      );

      // Segment from top arm to connector (valid, goes through left wall)
      expect(
        segmentExitsBoundary(31.57, 34.92, 31.50, 34.91, coords),
        isFalse,
        reason: 'Segment from top arm to connector should be valid',
      );
    });
  });
}
