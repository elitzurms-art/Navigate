import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/core/utils/geometry_utils.dart';
import 'package:navigate_app/domain/entities/coordinate.dart';
import 'package:navigate_app/domain/entities/navigation.dart';
import 'package:navigate_app/domain/entities/navigation_settings.dart';

void main() {
  // Reusable test data
  const jerusalem = Coordinate(lat: 31.7683, lng: 35.2137, utm: '');
  const telAviv = Coordinate(lat: 32.0853, lng: 34.7818, utm: '');

  // Simple square polygon around central Israel
  const square = [
    Coordinate(lat: 31.0, lng: 34.0, utm: ''),
    Coordinate(lat: 31.0, lng: 35.0, utm: ''),
    Coordinate(lat: 32.0, lng: 35.0, utm: ''),
    Coordinate(lat: 32.0, lng: 34.0, utm: ''),
  ];

  const insideSquare = Coordinate(lat: 31.5, lng: 34.5, utm: '');
  const outsideSquare = Coordinate(lat: 33.0, lng: 36.0, utm: '');

  group('distanceBetweenMeters', () {
    test('same point returns 0', () {
      final distance = GeometryUtils.distanceBetweenMeters(jerusalem, jerusalem);
      expect(distance, 0.0);
    });

    test('known distance: 1 degree latitude is approximately 111km', () {
      const pointA = Coordinate(lat: 0.0, lng: 0.0, utm: '');
      const pointB = Coordinate(lat: 1.0, lng: 0.0, utm: '');
      final distance = GeometryUtils.distanceBetweenMeters(pointA, pointB);
      // 1 degree lat ≈ 111,195 m
      expect(distance, closeTo(111195, 500));
    });

    test('Jerusalem to Tel Aviv is approximately 60km', () {
      final distance = GeometryUtils.distanceBetweenMeters(jerusalem, telAviv);
      // Approximately 54-65 km
      expect(distance, greaterThan(50000));
      expect(distance, lessThan(70000));
    });

    test('distance is symmetric', () {
      final d1 = GeometryUtils.distanceBetweenMeters(jerusalem, telAviv);
      final d2 = GeometryUtils.distanceBetweenMeters(telAviv, jerusalem);
      expect(d1, closeTo(d2, 0.01));
    });
  });

  group('bearingBetween', () {
    test('due north returns approximately 0 degrees', () {
      const from = Coordinate(lat: 31.0, lng: 35.0, utm: '');
      const to = Coordinate(lat: 32.0, lng: 35.0, utm: '');
      final bearing = GeometryUtils.bearingBetween(from, to);
      expect(bearing, closeTo(0, 1.0));
    });

    test('due east returns approximately 90 degrees', () {
      const from = Coordinate(lat: 31.0, lng: 34.0, utm: '');
      const to = Coordinate(lat: 31.0, lng: 35.0, utm: '');
      final bearing = GeometryUtils.bearingBetween(from, to);
      expect(bearing, closeTo(90, 1.0));
    });

    test('due south returns approximately 180 degrees', () {
      const from = Coordinate(lat: 32.0, lng: 35.0, utm: '');
      const to = Coordinate(lat: 31.0, lng: 35.0, utm: '');
      final bearing = GeometryUtils.bearingBetween(from, to);
      expect(bearing, closeTo(180, 1.0));
    });

    test('bearing is always in range [0, 360)', () {
      final bearing = GeometryUtils.bearingBetween(jerusalem, telAviv);
      expect(bearing, greaterThanOrEqualTo(0));
      expect(bearing, lessThan(360));
    });
  });

  group('distanceFromPointToSegmentMeters', () {
    test('point on segment returns approximately 0', () {
      const segA = Coordinate(lat: 31.0, lng: 34.0, utm: '');
      const segB = Coordinate(lat: 31.0, lng: 35.0, utm: '');
      // Midpoint of the segment
      const point = Coordinate(lat: 31.0, lng: 34.5, utm: '');
      final distance =
          GeometryUtils.distanceFromPointToSegmentMeters(point, segA, segB);
      expect(distance, closeTo(0, 10));
    });

    test('degenerate segment (same point) returns distance to point', () {
      const segA = Coordinate(lat: 31.0, lng: 34.0, utm: '');
      const point = Coordinate(lat: 31.0, lng: 35.0, utm: '');
      final distance =
          GeometryUtils.distanceFromPointToSegmentMeters(point, segA, segA);
      final directDistance =
          GeometryUtils.distanceBetweenMeters(point, segA);
      expect(distance, closeTo(directDistance, 0.01));
    });

    test('point perpendicular to segment is closer than to endpoints', () {
      const segA = Coordinate(lat: 31.0, lng: 34.0, utm: '');
      const segB = Coordinate(lat: 31.0, lng: 36.0, utm: '');
      const point = Coordinate(lat: 31.5, lng: 35.0, utm: '');
      final distToSeg =
          GeometryUtils.distanceFromPointToSegmentMeters(point, segA, segB);
      final distToA = GeometryUtils.distanceBetweenMeters(point, segA);
      final distToB = GeometryUtils.distanceBetweenMeters(point, segB);
      expect(distToSeg, lessThan(distToA));
      expect(distToSeg, lessThan(distToB));
    });
  });

  group('calculatePathLengthKm', () {
    test('empty path returns 0', () {
      expect(GeometryUtils.calculatePathLengthKm([]), 0.0);
    });

    test('single point returns 0', () {
      expect(GeometryUtils.calculatePathLengthKm([jerusalem]), 0.0);
    });

    test('two points returns distance in km', () {
      const a = Coordinate(lat: 0.0, lng: 0.0, utm: '');
      const b = Coordinate(lat: 1.0, lng: 0.0, utm: '');
      final lengthKm = GeometryUtils.calculatePathLengthKm([a, b]);
      // ~111.195 km
      expect(lengthKm, closeTo(111.195, 1.0));
    });

    test('three point path accumulates distance', () {
      const a = Coordinate(lat: 0.0, lng: 0.0, utm: '');
      const b = Coordinate(lat: 1.0, lng: 0.0, utm: '');
      const c = Coordinate(lat: 2.0, lng: 0.0, utm: '');
      final lengthKm = GeometryUtils.calculatePathLengthKm([a, b, c]);
      // ~222 km
      expect(lengthKm, closeTo(222.39, 2.0));
    });
  });

  group('isPointInPolygon', () {
    test('point inside square returns true', () {
      expect(GeometryUtils.isPointInPolygon(insideSquare, square), isTrue);
    });

    test('point outside square returns false', () {
      expect(GeometryUtils.isPointInPolygon(outsideSquare, square), isFalse);
    });

    test('less than 3 vertices returns false', () {
      const twoPoints = [
        Coordinate(lat: 31.0, lng: 34.0, utm: ''),
        Coordinate(lat: 32.0, lng: 35.0, utm: ''),
      ];
      expect(GeometryUtils.isPointInPolygon(insideSquare, twoPoints), isFalse);
    });

    test('empty polygon returns false', () {
      expect(GeometryUtils.isPointInPolygon(insideSquare, []), isFalse);
    });

    test('point on vertex may return true or false (edge case)', () {
      // Not testing specific behavior — just ensuring no crash
      final result = GeometryUtils.isPointInPolygon(square[0], square);
      expect(result, isA<bool>());
    });
  });

  group('distanceFromPointToPolygonMeters', () {
    test('point inside polygon returns 0', () {
      final distance = GeometryUtils.distanceFromPointToPolygonMeters(
          insideSquare, square);
      expect(distance, 0.0);
    });

    test('point outside polygon returns positive distance', () {
      final distance = GeometryUtils.distanceFromPointToPolygonMeters(
          outsideSquare, square);
      expect(distance, greaterThan(0));
    });

    test('less than 3 vertices returns infinity', () {
      final distance = GeometryUtils.distanceFromPointToPolygonMeters(
        insideSquare,
        [const Coordinate(lat: 31.0, lng: 34.0, utm: '')],
      );
      expect(distance, double.infinity);
    });

    test('empty polygon returns infinity', () {
      final distance =
          GeometryUtils.distanceFromPointToPolygonMeters(insideSquare, []);
      expect(distance, double.infinity);
    });
  });

  group('getPolygonCenter', () {
    test('simple square returns center', () {
      final center = GeometryUtils.getPolygonCenter(square);
      expect(center.lat, closeTo(31.5, 0.001));
      expect(center.lng, closeTo(34.5, 0.001));
    });

    test('empty polygon returns (0, 0)', () {
      final center = GeometryUtils.getPolygonCenter([]);
      expect(center.lat, 0.0);
      expect(center.lng, 0.0);
      expect(center.utm, '');
    });

    test('single point returns that point', () {
      final center = GeometryUtils.getPolygonCenter([jerusalem]);
      expect(center.lat, closeTo(jerusalem.lat, 0.001));
      expect(center.lng, closeTo(jerusalem.lng, 0.001));
    });
  });

  group('doPolygonsIntersect', () {
    test('overlapping polygons return true', () {
      const polygon2 = [
        Coordinate(lat: 31.5, lng: 34.5, utm: ''),
        Coordinate(lat: 31.5, lng: 35.5, utm: ''),
        Coordinate(lat: 32.5, lng: 35.5, utm: ''),
        Coordinate(lat: 32.5, lng: 34.5, utm: ''),
      ];
      expect(GeometryUtils.doPolygonsIntersect(square, polygon2), isTrue);
    });

    test('separate polygons return false', () {
      const farPolygon = [
        Coordinate(lat: 40.0, lng: 40.0, utm: ''),
        Coordinate(lat: 40.0, lng: 41.0, utm: ''),
        Coordinate(lat: 41.0, lng: 41.0, utm: ''),
        Coordinate(lat: 41.0, lng: 40.0, utm: ''),
      ];
      expect(GeometryUtils.doPolygonsIntersect(square, farPolygon), isFalse);
    });

    test('less than 3 vertices returns false', () {
      const twoPoints = [
        Coordinate(lat: 31.0, lng: 34.0, utm: ''),
        Coordinate(lat: 32.0, lng: 35.0, utm: ''),
      ];
      expect(GeometryUtils.doPolygonsIntersect(square, twoPoints), isFalse);
      expect(GeometryUtils.doPolygonsIntersect(twoPoints, square), isFalse);
    });

    test('one polygon fully inside another returns true', () {
      const innerSquare = [
        Coordinate(lat: 31.2, lng: 34.2, utm: ''),
        Coordinate(lat: 31.2, lng: 34.8, utm: ''),
        Coordinate(lat: 31.8, lng: 34.8, utm: ''),
        Coordinate(lat: 31.8, lng: 34.2, utm: ''),
      ];
      expect(GeometryUtils.doPolygonsIntersect(square, innerSquare), isTrue);
    });
  });

  group('doesSegmentIntersectPolygon', () {
    test('segment crossing polygon returns true', () {
      const segA = Coordinate(lat: 31.5, lng: 33.0, utm: '');
      const segB = Coordinate(lat: 31.5, lng: 36.0, utm: '');
      expect(
          GeometryUtils.doesSegmentIntersectPolygon(segA, segB, square), isTrue);
    });

    test('segment outside polygon returns false', () {
      const segA = Coordinate(lat: 33.0, lng: 36.0, utm: '');
      const segB = Coordinate(lat: 34.0, lng: 37.0, utm: '');
      expect(GeometryUtils.doesSegmentIntersectPolygon(segA, segB, square),
          isFalse);
    });

    test('segment starting inside polygon returns true', () {
      const segA = Coordinate(lat: 31.5, lng: 34.5, utm: '');
      const segB = Coordinate(lat: 33.0, lng: 36.0, utm: '');
      expect(
          GeometryUtils.doesSegmentIntersectPolygon(segA, segB, square), isTrue);
    });

    test('less than 3 polygon vertices returns false', () {
      const segA = Coordinate(lat: 31.5, lng: 34.5, utm: '');
      const segB = Coordinate(lat: 32.0, lng: 35.0, utm: '');
      expect(
          GeometryUtils.doesSegmentIntersectPolygon(segA, segB, [square[0]]),
          isFalse);
    });
  });

  group('formatNavigationTime', () {
    test('0 minutes formats correctly', () {
      expect(GeometryUtils.formatNavigationTime(0), "0 דק'");
    });

    test('45 minutes formats correctly', () {
      expect(GeometryUtils.formatNavigationTime(45), "45 דק'");
    });

    test('60 minutes formats as 1 hour', () {
      expect(GeometryUtils.formatNavigationTime(60), '1 שעות');
    });

    test('90 minutes formats as hours:minutes', () {
      expect(GeometryUtils.formatNavigationTime(90), '1:30 שעות');
    });

    test('120 minutes formats as 2 hours', () {
      expect(GeometryUtils.formatNavigationTime(120), '2 שעות');
    });

    test('125 minutes formats as 2:05', () {
      expect(GeometryUtils.formatNavigationTime(125), '2:05 שעות');
    });
  });

  group('getBoundingBox', () {
    test('empty polygon returns all zeros', () {
      final bbox = GeometryUtils.getBoundingBox([]);
      expect(bbox.minLat, 0.0);
      expect(bbox.maxLat, 0.0);
      expect(bbox.minLng, 0.0);
      expect(bbox.maxLng, 0.0);
      expect(bbox.center.lat, 0.0);
      expect(bbox.center.lng, 0.0);
      expect(bbox.radius, 0.0);
    });

    test('square returns correct bounding box', () {
      final bbox = GeometryUtils.getBoundingBox(square);
      expect(bbox.minLat, 31.0);
      expect(bbox.maxLat, 32.0);
      expect(bbox.minLng, 34.0);
      expect(bbox.maxLng, 35.0);
    });

    test('bounding box center is correct for square', () {
      final bbox = GeometryUtils.getBoundingBox(square);
      expect(bbox.center.lat, closeTo(31.5, 0.001));
      expect(bbox.center.lng, closeTo(34.5, 0.001));
    });

    test('bounding box radius uses the larger dimension', () {
      final bbox = GeometryUtils.getBoundingBox(square);
      // Both dimensions are 1.0, so radius = 0.5
      expect(bbox.radius, closeTo(0.5, 0.001));
    });

    test('non-square polygon has correct asymmetric bounding box', () {
      const widePolygon = [
        Coordinate(lat: 31.0, lng: 33.0, utm: ''),
        Coordinate(lat: 31.0, lng: 36.0, utm: ''),
        Coordinate(lat: 32.0, lng: 36.0, utm: ''),
      ];
      final bbox = GeometryUtils.getBoundingBox(widePolygon);
      expect(bbox.minLng, 33.0);
      expect(bbox.maxLng, 36.0);
      // Radius uses larger dimension: lng range = 3.0 > lat range = 1.0
      expect(bbox.radius, closeTo(1.5, 0.001));
    });
  });

  group('filterPointsInPolygon', () {
    final testPoints = [
      insideSquare,
      outsideSquare,
      const Coordinate(lat: 31.5, lng: 34.8, utm: ''), // inside
      const Coordinate(lat: 35.0, lng: 40.0, utm: ''), // outside
    ];

    test('empty polygon returns all points', () {
      final filtered = GeometryUtils.filterPointsInPolygon<Coordinate>(
        points: testPoints,
        getCoordinate: (c) => c,
        polygon: [],
      );
      expect(filtered.length, testPoints.length);
    });

    test('filters correctly with valid polygon', () {
      final filtered = GeometryUtils.filterPointsInPolygon<Coordinate>(
        points: testPoints,
        getCoordinate: (c) => c,
        polygon: square,
      );
      // insideSquare + (31.5, 34.8) are inside
      expect(filtered.length, 2);
      expect(filtered, contains(insideSquare));
    });

    test('all points inside returns all', () {
      final insidePoints = [
        const Coordinate(lat: 31.2, lng: 34.2, utm: ''),
        const Coordinate(lat: 31.8, lng: 34.8, utm: ''),
      ];
      final filtered = GeometryUtils.filterPointsInPolygon<Coordinate>(
        points: insidePoints,
        getCoordinate: (c) => c,
        polygon: square,
      );
      expect(filtered.length, 2);
    });

    test('all points outside returns empty', () {
      final outsidePoints = [
        const Coordinate(lat: 33.0, lng: 36.0, utm: ''),
        const Coordinate(lat: 40.0, lng: 40.0, utm: ''),
      ];
      final filtered = GeometryUtils.filterPointsInPolygon<Coordinate>(
        points: outsidePoints,
        getCoordinate: (c) => c,
        polygon: square,
      );
      expect(filtered, isEmpty);
    });
  });

  group('calculateNavigationTimeMinutes', () {
    test('returns 0 when settings disabled', () {
      const settings = TimeCalculationSettings(enabled: false);
      final time = GeometryUtils.calculateNavigationTimeMinutes(
        routeLengthKm: 10.0,
        settings: settings,
      );
      expect(time, 0);
    });

    test('calculates time for short route (no breaks)', () {
      // Default: walkingSpeedKmh = 4.0 (not heavy, not night), isSummer = true
      const settings = TimeCalculationSettings();
      // 8km at 4km/h = 120 min, no break (<=10km)
      final time = GeometryUtils.calculateNavigationTimeMinutes(
        routeLengthKm: 8.0,
        settings: settings,
      );
      expect(time, 120); // 8/4*60 = 120
    });

    test('calculates time for long route (with breaks)', () {
      // Default: walkingSpeedKmh = 4.0, isSummer = true (15 min per break)
      const settings = TimeCalculationSettings();
      // 20km at 4km/h = 300 min walking, breaks: floor(20/10) = 2 breaks * 15 = 30 min
      // Total = 330, ceil = 330
      final time = GeometryUtils.calculateNavigationTimeMinutes(
        routeLengthKm: 20.0,
        settings: settings,
      );
      expect(time, 330);
    });

    test('adds extension minutes', () {
      const settings = TimeCalculationSettings();
      final timeWithout = GeometryUtils.calculateNavigationTimeMinutes(
        routeLengthKm: 8.0,
        settings: settings,
      );
      final timeWith = GeometryUtils.calculateNavigationTimeMinutes(
        routeLengthKm: 8.0,
        settings: settings,
        extensionMinutes: 15,
      );
      expect(timeWith, timeWithout + 15);
    });

    test('heavy load night navigation uses slower speed', () {
      const settings = TimeCalculationSettings(
        isHeavyLoad: true,
        isNightNavigation: true,
      );
      // walkingSpeedKmh = 2.0 (heavy + night)
      // 8km at 2km/h = 240 min, no break
      final time = GeometryUtils.calculateNavigationTimeMinutes(
        routeLengthKm: 8.0,
        settings: settings,
      );
      expect(time, 240);
    });
  });

  group('getEffectiveTimeMinutes', () {
    test('uses manualTimeMinutes when set', () {
      const route = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 20.0,
        sequence: ['a'],
        manualTimeMinutes: 45,
      );
      const settings = TimeCalculationSettings();
      final time = GeometryUtils.getEffectiveTimeMinutes(
        route: route,
        settings: settings,
      );
      expect(time, 45);
    });

    test('manual time includes extension minutes', () {
      const route = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 20.0,
        sequence: ['a'],
        manualTimeMinutes: 45,
      );
      const settings = TimeCalculationSettings();
      final time = GeometryUtils.getEffectiveTimeMinutes(
        route: route,
        settings: settings,
        extensionMinutes: 10,
      );
      expect(time, 55);
    });

    test('falls back to automatic calculation when no manual time', () {
      const route = AssignedRoute(
        checkpointIds: ['a'],
        routeLengthKm: 8.0,
        sequence: ['a'],
      );
      const settings = TimeCalculationSettings();
      final time = GeometryUtils.getEffectiveTimeMinutes(
        route: route,
        settings: settings,
      );
      // 8km / 4.0 km/h * 60 = 120 min
      expect(time, 120);
    });
  });

  group('calculateSafetyTime', () {
    test('returns null when settings disabled', () {
      const settings = TimeCalculationSettings(enabled: false);
      final result = GeometryUtils.calculateSafetyTime(
        activeStartTime: DateTime(2026, 3, 10, 8, 0),
        routes: {
          'nav1': const AssignedRoute(
            checkpointIds: ['a'],
            routeLengthKm: 8.0,
            sequence: ['a'],
          ),
        },
        settings: settings,
      );
      expect(result, isNull);
    });

    test('returns null when routes empty', () {
      const settings = TimeCalculationSettings();
      final result = GeometryUtils.calculateSafetyTime(
        activeStartTime: DateTime(2026, 3, 10, 8, 0),
        routes: {},
        settings: settings,
      );
      expect(result, isNull);
    });

    test('calculates safety time as max route time + 60 minutes', () {
      const settings = TimeCalculationSettings();
      final startTime = DateTime(2026, 3, 10, 8, 0);
      final result = GeometryUtils.calculateSafetyTime(
        activeStartTime: startTime,
        routes: {
          'nav1': const AssignedRoute(
            checkpointIds: ['a'],
            routeLengthKm: 8.0,
            sequence: ['a'],
          ),
        },
        settings: settings,
      );
      // 8km/4km/h = 120 min + 60 min safety = 180 min from start
      expect(result, isNotNull);
      expect(
        result!.difference(startTime).inMinutes,
        180,
      );
    });
  });
}
