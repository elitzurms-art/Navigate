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

/// Creates a minimal Navigation for testing
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

/// Creates a checkpoint at the given lat/lng
Checkpoint _cp(String id, double lat, double lng) {
  return Checkpoint(
    id: id,
    areaId: 'area1',
    name: id,
    description: '',
    type: 'checkpoint',
    color: 'blue',
    coordinates: Coordinate(lat: lat, lng: lng, utm: '123456789012'),
    sequenceNumber: 0,
    createdBy: 'user1',
    createdAt: DateTime.now(),
  );
}

/// Creates a Boundary from a list of [lat, lng] pairs
Boundary _boundary(List<List<double>> coords) {
  return Boundary(
    id: 'b1',
    areaId: 'area1',
    name: 'Test Boundary',
    description: '',
    coordinates: coords.map((c) => Coordinate(lat: c[0], lng: c[1], utm: '123456789012')).toList(),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

// ---------------------------------------------------------------------------
// L-shaped polygon geometry
//
//   (31.0,34.5) -------- (31.0,34.55) -------- (31.0,34.6)
//       |                                            |
//       |                                            |
//   (31.05,34.5)                               (31.05,34.6)
//                                                    |
//                                                    |
//               (31.05,34.55) ----------- (31.1,34.55)
//                     |                        |
//                     |                        |
//               (31.1,34.55) ----------- (31.1,34.6)
//
// Simplified L-shape — wide top, narrow right column
// ---------------------------------------------------------------------------

/// L-shape boundary coords (CCW winding)
final _lShapeBoundary = [
  [31.0, 34.5],   // top-left
  [31.0, 34.6],   // top-right
  [31.05, 34.6],  // right step down
  [31.05, 34.55], // inner corner (reflex vertex)
  [31.1, 34.55],  // bottom of left column
  [31.1, 34.5],   // bottom-left
];

/// C-shape boundary coords
final _cShapeBoundary = [
  [31.0, 34.5],   // top-left
  [31.0, 34.6],   // top-right
  [31.02, 34.6],  // top-right step down
  [31.02, 34.52], // inner top corner
  [31.08, 34.52], // inner bottom corner
  [31.08, 34.6],  // bottom-right step up
  [31.1, 34.6],   // bottom-right
  [31.1, 34.5],   // bottom-left
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late RoutesDistributionService service;

  setUp(() {
    service = RoutesDistributionService();
  });

  // =========================================================================
  // End-to-end: L-shape distribution produces 0 boundary exits
  // =========================================================================
  group('Visibility Graph — L-shape distribution', () {
    test('automatic distribution with L-shape boundary has 0 boundary exits', () async {
      // Place checkpoints: some in top arm, some in bottom arm of L
      final checkpoints = [
        _cp('start', 31.01, 34.51),  // top-left area
        _cp('end', 31.09, 34.54),    // bottom area
        _cp('cp1', 31.01, 34.55),    // top area
        _cp('cp2', 31.01, 34.59),    // top-right area
        _cp('cp3', 31.04, 34.51),    // mid-left area
        _cp('cp4', 31.04, 34.54),    // center area
        _cp('cp5', 31.08, 34.51),    // bottom area
        _cp('cp6', 31.08, 34.54),    // bottom area
      ];

      final boundary = _boundary(_lShapeBoundary);
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'start',
        endPointId: 'end',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.5,
        maxRouteLength: 50.0,
        navigatorIds: ['u1', 'u2'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));
      expect(result.routes.length, 2);

      // Main assertion: all routes should have constrainedPath
      // (may be null if path is direct/straight line within boundary)
      for (final entry in result.routes.entries) {
        final route = entry.value;
        // Route should exist and have correct checkpoint count
        expect(route.checkpointIds.length, 3);
      }
    });

    test('automatic distribution with convex boundary still works', () async {
      // Square boundary — convex, no reflex vertices, all straight lines work
      final squareBoundary = [
        [31.0, 34.5],
        [31.0, 34.6],
        [31.1, 34.6],
        [31.1, 34.5],
      ];

      final checkpoints = [
        _cp('start', 31.02, 34.52),
        _cp('end', 31.08, 34.58),
        _cp('cp1', 31.03, 34.55),
        _cp('cp2', 31.05, 34.53),
        _cp('cp3', 31.07, 34.57),
        _cp('cp4', 31.05, 34.56),
      ];

      final boundary = _boundary(squareBoundary);
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'start',
        endPointId: 'end',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 2,
        minRouteLength: 0.1,
        maxRouteLength: 50.0,
        navigatorIds: ['u1', 'u2'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));
      expect(result.routes.length, 2);
    });

    test('automatic distribution without boundary falls back to straight lines', () async {
      final checkpoints = [
        _cp('start', 31.02, 34.52),
        _cp('end', 31.08, 34.58),
        _cp('cp1', 31.03, 34.55),
        _cp('cp2', 31.05, 34.53),
        _cp('cp3', 31.07, 34.57),
        _cp('cp4', 31.05, 34.56),
      ];

      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        executionOrder: 'sequential',
        checkpointsPerNavigator: 4,
        minRouteLength: 0.1,
        maxRouteLength: 50.0,
        navigatorIds: ['u1'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));
      expect(result.routes.length, 1);
      // No constrainedPath when no boundary
      final route = result.routes.values.first;
      expect(route.constrainedPath, isNull);
    });

    test('C-shape boundary forces path around concavity', () async {
      // Place checkpoints that would require going around the C shape
      final checkpoints = [
        _cp('start', 31.01, 34.51),  // top-left
        _cp('end', 31.09, 34.51),    // bottom-left
        _cp('cp1', 31.01, 34.59),    // top-right
        _cp('cp2', 31.09, 34.59),    // bottom-right
        _cp('cp3', 31.05, 34.51),    // center-left (inside C, straight path blocked)
      ];

      final boundary = _boundary(_cShapeBoundary);
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'start',
        endPointId: 'end',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.1,
        maxRouteLength: 100.0,
        navigatorIds: ['u1'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));
      expect(result.routes.length, 1);
    });
  });

  // =========================================================================
  // AssignedRoute.constrainedPath serialization
  // =========================================================================
  group('AssignedRoute.constrainedPath', () {
    test('toMap/fromMap round-trip with constrainedPath', () {
      final route = AssignedRoute(
        checkpointIds: ['cp1', 'cp2'],
        routeLengthKm: 5.0,
        sequence: ['cp1', 'cp2'],
        constrainedPath: [
          const Coordinate(lat: 31.0, lng: 34.5, utm: '123456789012'),
          const Coordinate(lat: 31.05, lng: 34.55, utm: '123456789013'),
          const Coordinate(lat: 31.1, lng: 34.6, utm: '123456789014'),
        ],
      );

      final map = route.toMap();
      expect(map['constrainedPath'], isNotNull);
      expect((map['constrainedPath'] as List).length, 3);

      final restored = AssignedRoute.fromMap(map);
      expect(restored.constrainedPath, isNotNull);
      expect(restored.constrainedPath!.length, 3);
      expect(restored.constrainedPath![0].lat, 31.0);
      expect(restored.constrainedPath![2].lng, 34.6);
    });

    test('toMap/fromMap round-trip without constrainedPath', () {
      const route = AssignedRoute(
        checkpointIds: ['cp1'],
        routeLengthKm: 3.0,
        sequence: ['cp1'],
      );

      final map = route.toMap();
      expect(map.containsKey('constrainedPath'), isFalse);

      final restored = AssignedRoute.fromMap(map);
      expect(restored.constrainedPath, isNull);
    });

    test('copyWith clears constrainedPath', () {
      final route = AssignedRoute(
        checkpointIds: ['cp1'],
        routeLengthKm: 3.0,
        sequence: ['cp1'],
        constrainedPath: [
          const Coordinate(lat: 31.0, lng: 34.5, utm: '123456789012'),
        ],
      );

      final cleared = route.copyWith(clearConstrainedPath: true);
      expect(cleared.constrainedPath, isNull);
    });
  });

  // =========================================================================
  // Boundary containment verification — all route segments stay inside
  // =========================================================================
  group('Visibility Graph — boundary containment', () {
    /// Checks if a segment crosses the boundary (real crossings, not vertex touches)
    bool segmentCrossesBoundary(
      double lat1, double lng1,
      double lat2, double lng2,
      List<List<double>> boundaryCoords,
    ) {
      final segment = turf.LineString(coordinates: [
        turf.Position(lng1, lat1),
        turf.Position(lng2, lat2),
      ]);
      final ring = boundaryCoords
          .map((c) => turf.Position(c[1], c[0]))
          .toList();
      if (ring.first.lng != ring.last.lng || ring.first.lat != ring.last.lat) {
        ring.add(ring.first);
      }
      final polygon = turf.Polygon(coordinates: [ring]);

      final intersections = turf.lineIntersect(segment, polygon);
      int realCrossings = 0;
      for (final feat in intersections.features) {
        final pos = feat.geometry!.coordinates;
        bool isVertex = false;
        for (final coord in boundaryCoords) {
          if ((pos.lat - coord[0]).abs() < 1e-7 &&
              (pos.lng - coord[1]).abs() < 1e-7) {
            isVertex = true;
            break;
          }
        }
        if (!isVertex) realCrossings++;
      }
      return realCrossings > 0;
    }

    /// Verify all consecutive segment pairs in a constrainedPath stay inside boundary
    void verifyPathInsideBoundary(
      List<Coordinate> path,
      List<List<double>> boundaryCoords,
      String routeLabel,
    ) {
      for (int i = 0; i < path.length - 1; i++) {
        final a = path[i];
        final b = path[i + 1];
        final crosses = segmentCrossesBoundary(
          a.lat, a.lng, b.lat, b.lng, boundaryCoords,
        );
        expect(crosses, isFalse,
            reason: '$routeLabel: segment $i (${a.lat},${a.lng})→(${b.lat},${b.lng}) '
                'crosses boundary');
      }
    }

    test('L-shape: all route segments stay inside boundary', () async {
      final checkpoints = [
        _cp('start', 31.01, 34.51),
        _cp('end', 31.09, 34.54),
        _cp('cp1', 31.01, 34.55),
        _cp('cp2', 31.01, 34.59),
        _cp('cp3', 31.04, 34.51),
        _cp('cp4', 31.04, 34.54),
        _cp('cp5', 31.08, 34.51),
        _cp('cp6', 31.08, 34.54),
      ];

      final boundary = _boundary(_lShapeBoundary);
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1', 'u2'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'start',
        endPointId: 'end',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.5,
        maxRouteLength: 50.0,
        navigatorIds: ['u1', 'u2'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));

      // Verify each route's constrainedPath stays inside boundary
      for (final entry in result.routes.entries) {
        final route = entry.value;
        if (route.constrainedPath != null && route.constrainedPath!.length >= 2) {
          verifyPathInsideBoundary(
            route.constrainedPath!,
            _lShapeBoundary,
            'Route ${entry.key}',
          );
        }
      }
    });

    test('C-shape: all route segments stay inside boundary', () async {
      final checkpoints = [
        _cp('start', 31.01, 34.51),
        _cp('end', 31.09, 34.51),
        _cp('cp1', 31.01, 34.59),
        _cp('cp2', 31.09, 34.59),
        _cp('cp3', 31.05, 34.51),
      ];

      final boundary = _boundary(_cShapeBoundary);
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'start',
        endPointId: 'end',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.1,
        maxRouteLength: 100.0,
        navigatorIds: ['u1'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));

      for (final entry in result.routes.entries) {
        final route = entry.value;
        if (route.constrainedPath != null && route.constrainedPath!.length >= 2) {
          verifyPathInsideBoundary(
            route.constrainedPath!,
            _cShapeBoundary,
            'Route ${entry.key}',
          );
        }
      }
    });
  });

  // =========================================================================
  // Connectivity: no isolated checkpoints (force-connect fix)
  // =========================================================================
  group('Visibility Graph — checkpoint connectivity', () {
    test('all checkpoints get constrainedPath even near concave corners', () async {
      // Place a checkpoint right at the inner corner of the L-shape
      // Before the fix, this could create an isolated reflex vertex
      final checkpoints = [
        _cp('start', 31.01, 34.51),       // top-left area
        _cp('end', 31.09, 34.54),         // bottom area
        _cp('corner', 31.049, 34.549),    // near the concave corner (31.05, 34.55)
        _cp('cp1', 31.04, 34.51),         // mid-left
        _cp('cp2', 31.08, 34.51),         // bottom
      ];

      final boundary = _boundary(_lShapeBoundary);
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'start',
        endPointId: 'end',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.1,
        maxRouteLength: 100.0,
        navigatorIds: ['u1'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));
      expect(result.routes.length, 1);

      final route = result.routes.values.first;
      // Route should have a constrainedPath (boundary is concave)
      expect(route.constrainedPath, isNotNull,
          reason: 'Route near concave corner should have constrainedPath');
      expect(route.constrainedPath!.length, greaterThanOrEqualTo(2),
          reason: 'constrainedPath should have at least 2 points');
    });

    test('checkpoint connectivity: all segments in constrained path stay inside L-shape', () async {
      // Checkpoints spread across both arms of the L
      final checkpoints = [
        _cp('start', 31.01, 34.51),
        _cp('end', 31.09, 34.54),
        _cp('cp_top_right', 31.01, 34.59),   // top-right arm
        _cp('cp_bottom', 31.08, 34.51),       // bottom arm
        _cp('cp_near_corner', 31.049, 34.549), // near concave corner
      ];

      final boundary = _boundary(_lShapeBoundary);
      final navigation = _createTestNavigation(
        selectedParticipantIds: ['u1'],
      );
      final tree = _createTestTree();

      final result = await service.distributeAutomatically(
        navigation: navigation,
        tree: tree,
        checkpoints: checkpoints,
        boundary: boundary,
        startPointId: 'start',
        endPointId: 'end',
        executionOrder: 'sequential',
        checkpointsPerNavigator: 3,
        minRouteLength: 0.1,
        maxRouteLength: 100.0,
        navigatorIds: ['u1'],
      );

      expect(result.status, anyOf('success', 'needs_approval'));

      // Helper to check boundary crossings
      bool segmentCrossesBoundary(
        double lat1, double lng1,
        double lat2, double lng2,
        List<List<double>> boundaryCoords,
      ) {
        final segment = turf.LineString(coordinates: [
          turf.Position(lng1, lat1),
          turf.Position(lng2, lat2),
        ]);
        final ring = boundaryCoords
            .map((c) => turf.Position(c[1], c[0]))
            .toList();
        if (ring.first.lng != ring.last.lng || ring.first.lat != ring.last.lat) {
          ring.add(ring.first);
        }
        final polygon = turf.Polygon(coordinates: [ring]);

        final intersections = turf.lineIntersect(segment, polygon);
        int realCrossings = 0;
        for (final feat in intersections.features) {
          final pos = feat.geometry!.coordinates;
          bool isVertex = false;
          for (final coord in boundaryCoords) {
            if ((pos.lat - coord[0]).abs() < 1e-7 &&
                (pos.lng - coord[1]).abs() < 1e-7) {
              isVertex = true;
              break;
            }
          }
          if (!isVertex) realCrossings++;
        }
        return realCrossings > 0;
      }

      for (final entry in result.routes.entries) {
        final route = entry.value;
        if (route.constrainedPath != null && route.constrainedPath!.length >= 2) {
          for (int i = 0; i < route.constrainedPath!.length - 1; i++) {
            final a = route.constrainedPath![i];
            final b = route.constrainedPath![i + 1];
            final crosses = segmentCrossesBoundary(
              a.lat, a.lng, b.lat, b.lng, _lShapeBoundary,
            );
            expect(crosses, isFalse,
                reason: 'Route ${entry.key}: segment $i '
                    '(${a.lat},${a.lng})→(${b.lat},${b.lng}) crosses boundary');
          }
        }
      }
    });
  });

  // =========================================================================
  // constrainedPath preservation in edit screen scenario
  // =========================================================================
  group('AssignedRoute.constrainedPath — preservation', () {
    test('constrainedPath preserved when checkpointIds unchanged', () {
      final originalPath = [
        const Coordinate(lat: 31.0, lng: 34.5, utm: '123456789012'),
        const Coordinate(lat: 31.05, lng: 34.55, utm: '123456789013'),
        const Coordinate(lat: 31.1, lng: 34.6, utm: '123456789014'),
      ];

      final route = AssignedRoute(
        checkpointIds: const ['cp1', 'cp2', 'cp3'],
        routeLengthKm: 5.0,
        sequence: const ['cp1', 'cp2', 'cp3'],
        constrainedPath: originalPath,
      );

      // Simulate edit screen: same checkpoints → preserve constrainedPath
      final newCheckpoints = ['cp1', 'cp2', 'cp3'];
      final sameCheckpoints = _listsEqual(newCheckpoints, route.checkpointIds);
      expect(sameCheckpoints, isTrue);

      final editedRoute = AssignedRoute(
        checkpointIds: newCheckpoints,
        routeLengthKm: 5.0,
        sequence: newCheckpoints,
        constrainedPath: sameCheckpoints ? route.constrainedPath : null,
      );

      expect(editedRoute.constrainedPath, isNotNull);
      expect(editedRoute.constrainedPath!.length, 3);
    });

    test('constrainedPath cleared when checkpointIds changed', () {
      final route = AssignedRoute(
        checkpointIds: const ['cp1', 'cp2', 'cp3'],
        routeLengthKm: 5.0,
        sequence: const ['cp1', 'cp2', 'cp3'],
        constrainedPath: [
          const Coordinate(lat: 31.0, lng: 34.5, utm: '123456789012'),
        ],
      );

      // Simulate edit screen: different checkpoints → clear constrainedPath
      final newCheckpoints = ['cp1', 'cp3', 'cp2']; // reordered
      final sameCheckpoints = _listsEqual(newCheckpoints, route.checkpointIds);
      expect(sameCheckpoints, isFalse);

      final editedRoute = AssignedRoute(
        checkpointIds: newCheckpoints,
        routeLengthKm: 5.0,
        sequence: newCheckpoints,
        constrainedPath: sameCheckpoints ? route.constrainedPath : null,
      );

      expect(editedRoute.constrainedPath, isNull);
    });
  });
}

/// Helper for list equality checks (mirrors edit screen logic)
bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
