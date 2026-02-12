import 'package:flutter_test/flutter_test.dart';
import 'package:gps_plus/gps_plus.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('WeightedCentroid', () {
    const centroid = WeightedCentroid();

    test('single tower returns tower position', () {
      final towers = [LatLng(32.08, 34.78)];
      final distances = [500.0];
      final ranges = [1000];

      final result = centroid.calculate(
        towers: towers,
        distances: distances,
        ranges: ranges,
      );

      expect(result, isNotNull);
      expect(result!.position.latitude, closeTo(32.08, 0.001));
      expect(result.position.longitude, closeTo(34.78, 0.001));
      expect(result.accuracyMeters, closeTo(1000.0, 0.01));
    });

    test('two towers - closer tower gets more weight', () {
      final towers = [
        LatLng(32.08, 34.77), // Tower A (closer)
        LatLng(32.08, 34.79), // Tower B (farther)
      ];
      final distances = [200.0, 800.0]; // A is much closer
      final ranges = [1000, 1000];

      final result = centroid.calculate(
        towers: towers,
        distances: distances,
        ranges: ranges,
      );

      expect(result, isNotNull);
      // Position should be biased toward Tower A (34.77)
      expect(result!.position.longitude, lessThan(34.78));
    });

    test('equal distances gives midpoint', () {
      final towers = [
        LatLng(32.08, 34.77),
        LatLng(32.08, 34.79),
      ];
      final distances = [500.0, 500.0]; // Equal distance
      final ranges = [1000, 1000];

      final result = centroid.calculate(
        towers: towers,
        distances: distances,
        ranges: ranges,
      );

      expect(result, isNotNull);
      // Should be approximately at the midpoint
      expect(result!.position.latitude, closeTo(32.08, 0.001));
      expect(result.position.longitude, closeTo(34.78, 0.001));
    });

    test('returns null with empty lists', () {
      final result = centroid.calculate(
        towers: [],
        distances: [],
        ranges: [],
      );

      expect(result, isNull);
    });

    test('returns null with mismatched list lengths', () {
      final result = centroid.calculate(
        towers: [LatLng(32.08, 34.78)],
        distances: [500.0, 800.0],
        ranges: [1000],
      );

      expect(result, isNull);
    });

    test('accuracy is weighted average of ranges', () {
      final towers = [
        LatLng(32.08, 34.77),
        LatLng(32.08, 34.79),
      ];
      final distances = [500.0, 500.0]; // Equal distance = equal weight
      final ranges = [500, 1500];

      final result = centroid.calculate(
        towers: towers,
        distances: distances,
        ranges: ranges,
      );

      expect(result, isNotNull);
      // With equal weights, accuracy should be average of ranges
      expect(result!.accuracyMeters, closeTo(1000.0, 1.0));
    });

    test('clamps minimum distance to 100m', () {
      // Very close towers shouldn't cause numeric issues
      final towers = [
        LatLng(32.08, 34.77),
        LatLng(32.08, 34.79),
      ];
      final distances = [10.0, 10.0]; // Very close - will be clamped to 100
      final ranges = [500, 500];

      final result = centroid.calculate(
        towers: towers,
        distances: distances,
        ranges: ranges,
      );

      expect(result, isNotNull);
      expect(result!.position.latitude.isFinite, isTrue);
      expect(result.position.longitude.isFinite, isTrue);
    });
  });
}
