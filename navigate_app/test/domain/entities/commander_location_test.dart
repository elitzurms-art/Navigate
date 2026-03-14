import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/domain/entities/commander_location.dart';

import '../../helpers/entity_factories.dart';

void main() {
  // ---------------------------------------------------------------------------
  // fromFirestore — כל השדות מאוכלסים
  // ---------------------------------------------------------------------------
  group('fromFirestore — all fields', () {
    test('parses all fields from a fully populated map', () {
      final data = <String, dynamic>{
        'userId': '1234567',
        'name': 'מפקד בדיקה',
        'latitude': 31.78,
        'longitude': 34.65,
        'updatedAt': '2026-03-01T10:00:00.000',
      };

      final loc = CommanderLocation.fromFirestore('doc-id-1', data);

      expect(loc.userId, '1234567');
      expect(loc.name, 'מפקד בדיקה');
      expect(loc.position.latitude, 31.78);
      expect(loc.position.longitude, 34.65);
      expect(loc.lastUpdate, DateTime.parse('2026-03-01T10:00:00.000'));
    });
  });

  // ---------------------------------------------------------------------------
  // fromFirestore — שדות חסרים
  // ---------------------------------------------------------------------------
  group('fromFirestore — missing fields', () {
    test('missing userId falls back to docId', () {
      final loc = CommanderLocation.fromFirestore('fallback-doc', <String, dynamic>{});
      expect(loc.userId, 'fallback-doc');
    });

    test('missing name defaults to empty string', () {
      final loc = CommanderLocation.fromFirestore('doc-1', <String, dynamic>{});
      expect(loc.name, '');
    });

    test('missing lat/lng defaults to 0.0', () {
      final loc = CommanderLocation.fromFirestore('doc-1', <String, dynamic>{});
      expect(loc.position.latitude, 0.0);
      expect(loc.position.longitude, 0.0);
    });

    test('missing updatedAt defaults to approximately DateTime.now()', () {
      final before = DateTime.now();
      final loc = CommanderLocation.fromFirestore('doc-1', <String, dynamic>{});
      final after = DateTime.now();

      // lastUpdate should be between before and after (inclusive)
      expect(loc.lastUpdate.isAfter(before) || loc.lastUpdate.isAtSameMomentAs(before), true);
      expect(loc.lastUpdate.isBefore(after) || loc.lastUpdate.isAtSameMomentAs(after), true);
    });
  });

  // ---------------------------------------------------------------------------
  // _parseDateTime
  // ---------------------------------------------------------------------------
  group('_parseDateTime', () {
    test('ISO string is parsed correctly', () {
      final loc = CommanderLocation.fromFirestore('doc-1', {
        'updatedAt': '2026-06-15T18:30:00.000',
      });
      expect(loc.lastUpdate, DateTime.parse('2026-06-15T18:30:00.000'));
    });

    test('null updatedAt falls back to DateTime.now()', () {
      final before = DateTime.now();
      final loc = CommanderLocation.fromFirestore('doc-1', {
        'updatedAt': null,
      });
      final after = DateTime.now();

      expect(loc.lastUpdate.isAfter(before) || loc.lastUpdate.isAtSameMomentAs(before), true);
      expect(loc.lastUpdate.isBefore(after) || loc.lastUpdate.isAtSameMomentAs(after), true);
    });

    test('DateTime object is used directly', () {
      final dt = DateTime(2026, 4, 20, 14, 0);
      final loc = CommanderLocation.fromFirestore('doc-1', {
        'updatedAt': dt,
      });
      expect(loc.lastUpdate, dt);
    });
  });

  // ---------------------------------------------------------------------------
  // docId vs data precedence — userId
  // ---------------------------------------------------------------------------
  group('docId vs data precedence', () {
    test('data userId takes precedence over docId', () {
      final loc = CommanderLocation.fromFirestore('doc-fallback', {
        'userId': '9999999',
      });
      expect(loc.userId, '9999999');
    });

    test('only docId used when userId missing from data', () {
      final loc = CommanderLocation.fromFirestore('doc-only', <String, dynamic>{});
      expect(loc.userId, 'doc-only');
    });
  });

  // ---------------------------------------------------------------------------
  // num coercion — lat/lng כ-int
  // ---------------------------------------------------------------------------
  group('num coercion', () {
    test('latitude and longitude as int are converted to double', () {
      final loc = CommanderLocation.fromFirestore('doc-1', {
        'latitude': 32,
        'longitude': 35,
      });
      expect(loc.position.latitude, 32.0);
      expect(loc.position.longitude, 35.0);
      expect(loc.position.latitude, isA<double>());
      expect(loc.position.longitude, isA<double>());
    });
  });

  // ---------------------------------------------------------------------------
  // Factory helper — createTestCommanderLocation
  // ---------------------------------------------------------------------------
  group('createTestCommanderLocation factory', () {
    test('creates a valid CommanderLocation with defaults', () {
      final loc = createTestCommanderLocation();
      expect(loc.userId, '7654321');
      expect(loc.name, 'מפקד א');
      expect(loc.position.latitude, 31.5);
      expect(loc.position.longitude, 34.8);
    });
  });
}
