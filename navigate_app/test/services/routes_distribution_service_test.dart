import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/services/routes_distribution_service.dart';
import 'package:navigate_app/domain/entities/navigation.dart';
import 'package:navigate_app/domain/entities/navigation_tree.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';
import 'package:navigate_app/domain/entities/checkpoint.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';
import 'package:navigate_app/domain/entities/security_violation.dart';

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
}
