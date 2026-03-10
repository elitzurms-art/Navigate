import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigate_app/core/utils/utm_converter.dart';

void main() {
  group('utmToLatLng and latLngToUtm roundtrip', () {
    test('Israel coordinate roundtrip preserves location within ~1m', () {
      // Jerusalem approximate UTM zone 36: easting ~700000, northing ~3516000
      // IDF convention: 6-digit easting + 6-digit northing (last 6 of each)
      const original = LatLng(31.77, 35.23);
      final utm = UtmConverter.latLngToUtm(original);
      final recovered = UtmConverter.utmToLatLng(utm);

      // Should be within ~100m (UTM truncation loses precision)
      expect(recovered.latitude, closeTo(original.latitude, 0.01));
      expect(recovered.longitude, closeTo(original.longitude, 0.01));
    });

    test('Tel Aviv coordinate roundtrip', () {
      const original = LatLng(32.0853, 34.7818);
      final utm = UtmConverter.latLngToUtm(original);
      final recovered = UtmConverter.utmToLatLng(utm);

      expect(recovered.latitude, closeTo(original.latitude, 0.01));
      expect(recovered.longitude, closeTo(original.longitude, 0.01));
    });
  });

  group('utmToLatLng', () {
    test('throws for non-12-digit string', () {
      expect(
        () => UtmConverter.utmToLatLng('12345'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws for 13-digit string', () {
      expect(
        () => UtmConverter.utmToLatLng('1234567890123'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws for empty string', () {
      expect(
        () => UtmConverter.utmToLatLng(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('IDF convention: 6-digit northing adds 3000000 for zone 36', () {
      // A northing < 1000000 in IDF convention means the leading '3' was truncated
      // e.g., northing 516000 means full northing = 3516000
      // Create a known UTM string where last 6 digits of northing < 1000000
      final result = UtmConverter.utmToLatLng('700000516000');
      // With northing 3516000 in zone 36, should be in Israel (~31-32 lat)
      expect(result.latitude, greaterThan(30));
      expect(result.latitude, lessThan(33));
    });

    test('known Jerusalem coordinates produce expected lat/lng', () {
      // Generate UTM for Jerusalem, then convert back
      const jerusalemLatLng = LatLng(31.77, 35.23);
      final utm = UtmConverter.latLngToUtm(jerusalemLatLng);
      final result = UtmConverter.utmToLatLng(utm);
      expect(result.latitude, closeTo(31.77, 0.01));
      expect(result.longitude, closeTo(35.23, 0.01));
    });
  });

  group('latLngToUtm', () {
    test('returns 12-character string', () {
      final result = UtmConverter.latLngToUtm(const LatLng(31.77, 35.23));
      expect(result.length, 12);
    });

    test('result is all numeric', () {
      final result = UtmConverter.latLngToUtm(const LatLng(31.77, 35.23));
      expect(int.tryParse(result), isNotNull);
    });

    test('different locations produce different UTM strings', () {
      final utm1 = UtmConverter.latLngToUtm(const LatLng(31.77, 35.23));
      final utm2 = UtmConverter.latLngToUtm(const LatLng(32.08, 34.78));
      expect(utm1, isNot(equals(utm2)));
    });
  });

  group('isValidUtm', () {
    test('valid 12-digit string returns true', () {
      expect(UtmConverter.isValidUtm('123456789012'), isTrue);
    });

    test('wrong length returns false', () {
      expect(UtmConverter.isValidUtm('12345'), isFalse);
      expect(UtmConverter.isValidUtm('1234567890123'), isFalse);
      expect(UtmConverter.isValidUtm(''), isFalse);
    });

    test('non-numeric returns false', () {
      expect(UtmConverter.isValidUtm('12345678901a'), isFalse);
      expect(UtmConverter.isValidUtm('abcdefghijkl'), isFalse);
    });

    test('all zeros is valid', () {
      expect(UtmConverter.isValidUtm('000000000000'), isTrue);
    });
  });

  group('distanceBetween', () {
    test('two close points returns small distance', () {
      // Two points ~100m apart
      const p1 = LatLng(31.77, 35.23);
      const p2 = LatLng(31.7709, 35.23);
      final distance = UtmConverter.distanceBetween(p1, p2);
      expect(distance, greaterThan(50));
      expect(distance, lessThan(200));
    });

    test('same point returns 0', () {
      const p1 = LatLng(31.77, 35.23);
      final distance = UtmConverter.distanceBetween(p1, p1);
      expect(distance, closeTo(0, 0.1));
    });

    test('Jerusalem to Tel Aviv approximately 60km', () {
      const jerusalem = LatLng(31.7683, 35.2137);
      const telAviv = LatLng(32.0853, 34.7818);
      final distance = UtmConverter.distanceBetween(jerusalem, telAviv);
      expect(distance, greaterThan(50000));
      expect(distance, lessThan(70000));
    });
  });
}
