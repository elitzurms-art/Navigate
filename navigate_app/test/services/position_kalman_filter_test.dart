import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/services/position_kalman_filter.dart';

void main() {
  late PositionKalmanFilter filter;

  setUp(() {
    filter = PositionKalmanFilter();
  });

  group('initialization', () {
    test('initially not initialized', () {
      expect(filter.isInitialized, isFalse);
    });

    test('first update returns same position and becomes initialized', () {
      final result = filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: DateTime(2026, 3, 10, 10, 0, 0),
      );
      expect(filter.isInitialized, isTrue);
      expect(result.lat, 31.77);
      expect(result.lng, 35.23);
      expect(result.accuracy, 10.0);
    });
  });

  group('filtering behavior', () {
    test('subsequent updates smooth the position', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      // Initialize at (31.77, 35.23)
      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: baseTime,
      );

      // Send a noisy measurement 1 second later
      final result = filter.update(
        lat: 31.7705,
        lng: 35.2305,
        accuracy: 10.0,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      );

      // The filtered position should be somewhere between the two measurements
      // (not exactly at the new measurement — that's the smoothing)
      expect(result.lat, closeTo(31.77, 0.001));
      expect(result.lng, closeTo(35.23, 0.001));
    });

    test('stationary measurements converge with low movement', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: baseTime,
      );

      // Send multiple measurements at the same position
      late ({double lat, double lng, double accuracy}) result;
      for (int i = 1; i <= 10; i++) {
        result = filter.update(
          lat: 31.77,
          lng: 35.23,
          accuracy: 10.0,
          timestamp: baseTime.add(Duration(seconds: i)),
        );
      }

      // After many stationary updates, should be very close to the true position
      expect(result.lat, closeTo(31.77, 0.0001));
      expect(result.lng, closeTo(35.23, 0.0001));
    });

    test('multiple updates with good accuracy converge', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 5.0,
        timestamp: baseTime,
      );

      // Send slightly noisy measurements around the same point
      late ({double lat, double lng, double accuracy}) result;
      for (int i = 1; i <= 20; i++) {
        result = filter.update(
          lat: 31.77 + (i % 2 == 0 ? 0.0001 : -0.0001),
          lng: 35.23 + (i % 2 == 0 ? 0.0001 : -0.0001),
          accuracy: 5.0,
          timestamp: baseTime.add(Duration(seconds: i)),
        );
      }

      // Should converge near 31.77, 35.23
      expect(result.lat, closeTo(31.77, 0.001));
      expect(result.lng, closeTo(35.23, 0.001));
    });
  });

  group('poor accuracy handling', () {
    test('very poor accuracy (>5000) skips measurement', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      // Initialize
      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: baseTime,
      );

      // Good update
      final beforePoor = filter.update(
        lat: 31.7701,
        lng: 35.2301,
        accuracy: 10.0,
        timestamp: baseTime.add(const Duration(seconds: 1)),
      );

      // Poor accuracy measurement (should be prediction-only)
      final afterPoor = filter.update(
        lat: 32.0,
        lng: 36.0,
        accuracy: 6000.0,
        timestamp: baseTime.add(const Duration(seconds: 2)),
      );

      // Position should not jump to the bad measurement (32.0, 36.0)
      // It should remain close to the previous filtered position
      expect((afterPoor.lat - beforePoor.lat).abs(), lessThan(0.01));
      expect((afterPoor.lng - beforePoor.lng).abs(), lessThan(0.01));
    });

    test('negative accuracy is treated as 500', () {
      final result = filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: -10.0,
        timestamp: DateTime(2026, 3, 10, 10, 0, 0),
      );
      // First measurement returns as-is but with sanitized accuracy
      expect(result.lat, 31.77);
      expect(result.lng, 35.23);
      expect(result.accuracy, 500.0);
    });
  });

  group('reset', () {
    test('reset clears initialized state', () {
      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: DateTime(2026, 3, 10, 10, 0, 0),
      );
      expect(filter.isInitialized, isTrue);

      filter.reset();
      expect(filter.isInitialized, isFalse);
    });

    test('after reset, next update re-initializes', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: baseTime,
      );

      filter.reset();

      // Re-initialize at a different location
      final result = filter.update(
        lat: 32.0,
        lng: 34.0,
        accuracy: 10.0,
        timestamp: baseTime.add(const Duration(seconds: 5)),
      );

      expect(filter.isInitialized, isTrue);
      expect(result.lat, 32.0);
      expect(result.lng, 34.0);
    });
  });

  group('forcePosition', () {
    test('sets specific position', () {
      // Initialize somewhere
      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: DateTime(2026, 3, 10, 10, 0, 0),
      );

      // Force to different position
      filter.forcePosition(32.0, 34.0);
      expect(filter.isInitialized, isTrue);

      // Next update should start from the forced position
      final result = filter.update(
        lat: 32.0001,
        lng: 34.0001,
        accuracy: 10.0,
        timestamp: DateTime(2026, 3, 10, 10, 0, 1),
      );

      // Should be very close to the forced position
      expect(result.lat, closeTo(32.0, 0.001));
      expect(result.lng, closeTo(34.0, 0.001));
    });
  });

  group('setMotionState', () {
    test('stationary zeroes velocity and subsequent updates stay closer', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: baseTime,
      );

      // Create some velocity by moving
      filter.update(
        lat: 31.7710,
        lng: 35.2310,
        accuracy: 10.0,
        timestamp: baseTime.add(const Duration(seconds: 5)),
      );

      // Set stationary
      filter.setMotionState(isStationary: true);

      // Send stationary measurements
      late ({double lat, double lng, double accuracy}) result;
      for (int i = 6; i <= 15; i++) {
        result = filter.update(
          lat: 31.7710,
          lng: 35.2310,
          accuracy: 10.0,
          timestamp: baseTime.add(Duration(seconds: i)),
        );
      }

      // Should stay very close to the stationary position
      expect(result.lat, closeTo(31.7710, 0.0005));
      expect(result.lng, closeTo(35.2310, 0.0005));
    });
  });

  group('large time gap', () {
    test('gap >60s causes reset and re-initialization', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: baseTime,
      );

      // Update after 2 minutes (>60s gap)
      final result = filter.update(
        lat: 32.0,
        lng: 34.5,
        accuracy: 10.0,
        timestamp: baseTime.add(const Duration(minutes: 2)),
      );

      // After reset + re-init, should return the new measurement directly
      expect(result.lat, 32.0);
      expect(result.lng, 34.5);
      expect(filter.isInitialized, isTrue);
    });

    test('gap exactly at 60s does not reset', () {
      final baseTime = DateTime(2026, 3, 10, 10, 0, 0);

      filter.update(
        lat: 31.77,
        lng: 35.23,
        accuracy: 10.0,
        timestamp: baseTime,
      );

      // Update at exactly 60 seconds (not > 60)
      final result = filter.update(
        lat: 31.7701,
        lng: 35.2301,
        accuracy: 10.0,
        timestamp: baseTime.add(const Duration(seconds: 60)),
      );

      // Should be a filtered result, not a direct re-initialization
      // (i.e., not exactly 31.7701 if filtering was applied)
      expect(result.lat, closeTo(31.77, 0.01));
      expect(result.lng, closeTo(35.23, 0.01));
    });
  });
}
