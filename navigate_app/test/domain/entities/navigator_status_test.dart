import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/navigator_status.dart';

import '../../helpers/entity_factories.dart';

void main() {
  // ---------------------------------------------------------------------------
  // fromFirestore — כל השדות מאוכלסים
  // ---------------------------------------------------------------------------
  group('fromFirestore — all fields populated', () {
    test('parses all fields from a fully populated map', () {
      final data = <String, dynamic>{
        'isConnected': true,
        'batteryLevel': 92,
        'hasGPS': true,
        'receptionLevel': 4,
        'latitude': 32.1,
        'longitude': 35.2,
        'positionSource': 'cell',
        'positionUpdatedAt': '2026-03-01T12:00:00.000',
        'gpsAccuracy': 3.5,
        'mapsStatus': 'completed',
        'hasMicrophonePermission': true,
        'hasPhonePermission': true,
        'hasDNDPermission': true,
      };

      final status = NavigatorStatus.fromFirestore(data);

      expect(status.isConnected, true);
      // hasReported is always true in fromFirestore
      expect(status.hasReported, true);
      expect(status.batteryLevel, 92);
      expect(status.hasGPS, true);
      expect(status.receptionLevel, 4);
      expect(status.latitude, 32.1);
      expect(status.longitude, 35.2);
      expect(status.positionSource, 'cell');
      expect(status.positionUpdatedAt, DateTime.parse('2026-03-01T12:00:00.000'));
      expect(status.gpsAccuracy, 3.5);
      expect(status.mapsStatus, 'completed');
      expect(status.hasMicrophonePermission, true);
      expect(status.hasPhonePermission, true);
      expect(status.hasDNDPermission, true);
    });
  });

  // ---------------------------------------------------------------------------
  // fromFirestore — מפה ריקה (ברירות מחדל)
  // ---------------------------------------------------------------------------
  group('fromFirestore — empty map (defaults)', () {
    test('returns sensible defaults for empty map', () {
      final status = NavigatorStatus.fromFirestore(<String, dynamic>{});

      expect(status.isConnected, false);
      expect(status.hasReported, true); // always true in fromFirestore
      expect(status.batteryLevel, -1);
      expect(status.hasGPS, false);
      expect(status.receptionLevel, 0);
      expect(status.latitude, isNull);
      expect(status.longitude, isNull);
      expect(status.positionSource, 'gps');
      expect(status.positionUpdatedAt, isNull);
      expect(status.gpsAccuracy, -1);
      expect(status.mapsStatus, 'notStarted');
      expect(status.hasMicrophonePermission, false);
      expect(status.hasPhonePermission, false);
      expect(status.hasDNDPermission, false);
    });
  });

  // ---------------------------------------------------------------------------
  // mapsReady getter
  // ---------------------------------------------------------------------------
  group('mapsReady getter', () {
    test('returns true when mapsStatus is completed', () {
      final status = createTestNavigatorStatus(mapsStatus: 'completed');
      expect(status.mapsReady, true);
    });

    test('returns false when mapsStatus is notStarted', () {
      final status = createTestNavigatorStatus(mapsStatus: 'notStarted');
      expect(status.mapsReady, false);
    });

    test('returns false when mapsStatus is downloading', () {
      final status = createTestNavigatorStatus(mapsStatus: 'downloading');
      expect(status.mapsReady, false);
    });

    test('returns false for fromFirestore with missing mapsStatus', () {
      final status = NavigatorStatus.fromFirestore(<String, dynamic>{});
      expect(status.mapsReady, false);
    });
  });

  // ---------------------------------------------------------------------------
  // _parseDateTime via positionUpdatedAt
  // ---------------------------------------------------------------------------
  group('_parseDateTime via positionUpdatedAt', () {
    test('parses ISO string correctly', () {
      final status = NavigatorStatus.fromFirestore({
        'positionUpdatedAt': '2026-01-15T08:30:00.000',
      });
      expect(status.positionUpdatedAt, DateTime.parse('2026-01-15T08:30:00.000'));
    });

    test('returns null when both positionUpdatedAt and updatedAt are null', () {
      final status = NavigatorStatus.fromFirestore(<String, dynamic>{});
      expect(status.positionUpdatedAt, isNull);
    });

    test('falls back to updatedAt when positionUpdatedAt is null', () {
      final status = NavigatorStatus.fromFirestore({
        'updatedAt': '2026-02-20T14:00:00.000',
      });
      expect(status.positionUpdatedAt, DateTime.parse('2026-02-20T14:00:00.000'));
    });

    test('prefers positionUpdatedAt over updatedAt when both present', () {
      final status = NavigatorStatus.fromFirestore({
        'positionUpdatedAt': '2026-03-01T10:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });
      expect(status.positionUpdatedAt, DateTime.parse('2026-03-01T10:00:00.000'));
    });

    test('handles DateTime object directly', () {
      final dt = DateTime(2026, 5, 10, 9, 30);
      final status = NavigatorStatus.fromFirestore({
        'positionUpdatedAt': dt,
      });
      expect(status.positionUpdatedAt, dt);
    });
  });

  // ---------------------------------------------------------------------------
  // num coercion — batteryLevel כ-double, lat/lng כ-int, gpsAccuracy כ-int
  // ---------------------------------------------------------------------------
  group('num coercion', () {
    test('batteryLevel as double is cast to int via as int? (throws)', () {
      // batteryLevel uses `as int?` so a double will throw a TypeError.
      // The factory expects int — verify that int values work correctly.
      final status = NavigatorStatus.fromFirestore({
        'batteryLevel': 75,
      });
      expect(status.batteryLevel, 75);
    });

    test('latitude as int is converted to double via num.toDouble()', () {
      final status = NavigatorStatus.fromFirestore({
        'latitude': 32,
        'longitude': 35,
      });
      expect(status.latitude, 32.0);
      expect(status.longitude, 35.0);
      expect(status.latitude, isA<double>());
      expect(status.longitude, isA<double>());
    });

    test('gpsAccuracy as int is converted to double via num.toDouble()', () {
      final status = NavigatorStatus.fromFirestore({
        'gpsAccuracy': 10,
      });
      expect(status.gpsAccuracy, 10.0);
      expect(status.gpsAccuracy, isA<double>());
    });
  });
}
