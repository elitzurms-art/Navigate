import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_plus/gps_plus.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('Trilateration', () {
    const trilateration = Trilateration();

    test('calculates position from 3 towers with known positions', () {
      // Three towers around Tel Aviv area
      // Target position: approximately 32.08, 34.78
      final towers = [
        LatLng(32.09, 34.77), // Tower 1: ~1.4km north-west
        LatLng(32.07, 34.79), // Tower 2: ~1.4km south-east
        LatLng(32.08, 34.76), // Tower 3: ~1.8km west
      ];

      // Distances from target to each tower (approximate in meters)
      final distances = [1400.0, 1400.0, 1800.0];

      final result = trilateration.calculate(
        towers: towers,
        distances: distances,
      );

      expect(result, isNotNull);
      // Position should be roughly near 32.08, 34.78
      expect(result!.position.latitude, closeTo(32.08, 0.02));
      expect(result.position.longitude, closeTo(34.78, 0.02));
    });

    test('calculates position from 4 towers (overdetermined)', () {
      // Four towers, target approximately at 32.08, 34.78
      final towers = [
        LatLng(32.09, 34.77),
        LatLng(32.07, 34.79),
        LatLng(32.08, 34.76),
        LatLng(32.09, 34.79),
      ];

      final distances = [1400.0, 1400.0, 1800.0, 1500.0];

      final result = trilateration.calculate(
        towers: towers,
        distances: distances,
      );

      expect(result, isNotNull);
      expect(result!.position.latitude, closeTo(32.08, 0.02));
      expect(result.position.longitude, closeTo(34.78, 0.02));
    });

    test('returns null with fewer than 3 towers', () {
      final towers = [
        LatLng(32.09, 34.77),
        LatLng(32.07, 34.79),
      ];
      final distances = [1400.0, 1400.0];

      final result = trilateration.calculate(
        towers: towers,
        distances: distances,
      );

      expect(result, isNull);
    });

    test('returns null with mismatched list lengths', () {
      final towers = [
        LatLng(32.09, 34.77),
        LatLng(32.07, 34.79),
        LatLng(32.08, 34.76),
      ];
      final distances = [1400.0, 1400.0]; // One missing

      final result = trilateration.calculate(
        towers: towers,
        distances: distances,
      );

      expect(result, isNull);
    });

    test('provides accuracy estimate (RMSE)', () {
      final towers = [
        LatLng(32.09, 34.77),
        LatLng(32.07, 34.79),
        LatLng(32.08, 34.76),
      ];
      final distances = [1400.0, 1400.0, 1800.0];

      final result = trilateration.calculate(
        towers: towers,
        distances: distances,
      );

      expect(result, isNotNull);
      expect(result!.accuracyMeters, isNonNegative);
    });

    test('handles collinear towers gracefully', () {
      // All towers on the same longitude line
      final towers = [
        LatLng(32.07, 34.78),
        LatLng(32.08, 34.78),
        LatLng(32.09, 34.78),
      ];
      final distances = [1000.0, 500.0, 1000.0];

      final result = trilateration.calculate(
        towers: towers,
        distances: distances,
      );

      // May return null (singular matrix) or a result - either is acceptable
      // The important thing is it doesn't crash
      if (result != null) {
        expect(result.position.latitude.isFinite, isTrue);
        expect(result.position.longitude.isFinite, isTrue);
      }
    });

    test('exact position when target is at a known tower', () {
      // Target exactly at tower[0]
      final target = LatLng(32.08, 34.78);
      final towers = [
        target,
        LatLng(32.09, 34.77),
        LatLng(32.07, 34.79),
      ];

      // Distance to first tower is 0, others are real distances
      const earthRadius = 6371000.0;
      final d1 = earthRadius *
          acos(sin(32.08 * pi / 180) * sin(32.09 * pi / 180) +
              cos(32.08 * pi / 180) *
                  cos(32.09 * pi / 180) *
                  cos((34.77 - 34.78) * pi / 180));
      final d2 = earthRadius *
          acos(sin(32.08 * pi / 180) * sin(32.07 * pi / 180) +
              cos(32.08 * pi / 180) *
                  cos(32.07 * pi / 180) *
                  cos((34.79 - 34.78) * pi / 180));

      final distances = [0.0, d1, d2];

      final result = trilateration.calculate(
        towers: towers,
        distances: distances,
      );

      expect(result, isNotNull);
      // Should be very close to the target
      expect(result!.position.latitude, closeTo(32.08, 0.005));
      expect(result.position.longitude, closeTo(34.78, 0.005));
    });
  });
}
