import 'dart:math';
import 'package:latlong2/latlong.dart';

/// כלי להמרת קואורדינטות UTM ל-GPS ולהיפך
class UtmConverter {
  static const double a = 6378137.0; // WGS84 semi-major axis
  static const double e = 0.081819190842622; // WGS84 eccentricity
  static const double k0 = 0.9996; // UTM scale factor

  /// המרת UTM ל-LatLng (GPS)
  ///
  /// [utmString] - מחרוזת UTM בפורמט של 12 ספרות (XXXXXXXXXXXXYYYY)
  /// [zone] - אזור UTM (ברירת מחדל 36 לישראל)
  /// [isNorthern] - האם האזור בחצי הכדור הצפוני (ברירת מחדל true)
  static LatLng utmToLatLng(String utmString, {int zone = 36, bool isNorthern = true}) {
    if (utmString.length != 12) {
      throw ArgumentError('מחרוזת UTM חייבת להכיל בדיוק 12 ספרות');
    }

    // חילוץ Easting ו-Northing
    final easting = double.parse(utmString.substring(0, 6));
    final northing = double.parse(utmString.substring(6, 12));

    return _utmToLatLng(easting, northing, zone, isNorthern);
  }

  /// המרת LatLng (GPS) ל-UTM
  ///
  /// מחזיר מחרוזת UTM של 12 ספרות
  static String latLngToUtm(LatLng latLng, {int zone = 36}) {
    final result = _latLngToUtm(latLng.latitude, latLng.longitude, zone);

    // עיגול לשלמים והמרה למחרוזת בת 12 תווים
    final eastingStr = result['easting']!.round().toString().padLeft(6, '0');
    final northingStr = result['northing']!.round().toString().padLeft(6, '0');

    return eastingStr + northingStr;
  }

  /// המרה פנימית של UTM ל-LatLng
  static LatLng _utmToLatLng(double easting, double northing, int zone, bool isNorthern) {
    final x = easting - 500000.0;
    final y = isNorthern ? northing : northing - 10000000.0;

    final M = y / k0;
    final mu = M / (a * (1 - pow(e, 2) / 4 - 3 * pow(e, 4) / 64 - 5 * pow(e, 6) / 256));

    final e1 = (1 - sqrt(1 - pow(e, 2))) / (1 + sqrt(1 - pow(e, 2)));

    final phi1 = mu +
        (3 * e1 / 2 - 27 * pow(e1, 3) / 32) * sin(2 * mu) +
        (21 * pow(e1, 2) / 16 - 55 * pow(e1, 4) / 32) * sin(4 * mu) +
        (151 * pow(e1, 3) / 96) * sin(6 * mu);

    final N1 = a / sqrt(1 - pow(e * sin(phi1), 2));
    final T1 = pow(tan(phi1), 2);
    final C1 = pow(e, 2) * pow(cos(phi1), 2) / (1 - pow(e, 2));
    final R1 = a * (1 - pow(e, 2)) / pow(1 - pow(e * sin(phi1), 2), 1.5);
    final D = x / (N1 * k0);

    final latitude = phi1 -
        (N1 * tan(phi1) / R1) *
        (pow(D, 2) / 2 -
        (5 + 3 * T1 + 10 * C1 - 4 * pow(C1, 2) - 9 * pow(e, 2)) * pow(D, 4) / 24 +
        (61 + 90 * T1 + 298 * C1 + 45 * pow(T1, 2) - 252 * pow(e, 2) - 3 * pow(C1, 2)) * pow(D, 6) / 720);

    final longitude =
        (D - (1 + 2 * T1 + C1) * pow(D, 3) / 6 +
        (5 - 2 * C1 + 28 * T1 - 3 * pow(C1, 2) + 8 * pow(e, 2) + 24 * pow(T1, 2)) * pow(D, 5) / 120) /
        cos(phi1);

    final latDegrees = latitude * 180 / pi;
    final lonDegrees = ((zone - 1) * 6 - 180 + 3) + longitude * 180 / pi;

    return LatLng(latDegrees, lonDegrees);
  }

  /// המרה פנימית של LatLng ל-UTM
  static Map<String, double> _latLngToUtm(double latitude, double longitude, int zone) {
    final lat = latitude * pi / 180;
    final lon = longitude * pi / 180;
    final lonOrigin = ((zone - 1) * 6 - 180 + 3) * pi / 180;

    final N = a / sqrt(1 - pow(e * sin(lat), 2));
    final T = pow(tan(lat), 2);
    final C = pow(e, 2) * pow(cos(lat), 2) / (1 - pow(e, 2));
    final A = (lon - lonOrigin) * cos(lat);

    final M = a * ((1 - pow(e, 2) / 4 - 3 * pow(e, 4) / 64 - 5 * pow(e, 6) / 256) * lat -
        (3 * pow(e, 2) / 8 + 3 * pow(e, 4) / 32 + 45 * pow(e, 6) / 1024) * sin(2 * lat) +
        (15 * pow(e, 4) / 256 + 45 * pow(e, 6) / 1024) * sin(4 * lat) -
        (35 * pow(e, 6) / 3072) * sin(6 * lat));

    final easting = k0 * N *
        (A + (1 - T + C) * pow(A, 3) / 6 +
        (5 - 18 * T + pow(T, 2) + 72 * C - 58 * pow(e, 2)) * pow(A, 5) / 120) +
        500000.0;

    final northing = k0 *
        (M + N * tan(lat) *
        (pow(A, 2) / 2 + (5 - T + 9 * C + 4 * pow(C, 2)) * pow(A, 4) / 24 +
        (61 - 58 * T + pow(T, 2) + 600 * C - 330 * pow(e, 2)) * pow(A, 6) / 720));

    return {
      'easting': easting,
      'northing': latitude >= 0 ? northing : northing + 10000000.0,
    };
  }

  /// בדיקת תקינות מחרוזת UTM
  static bool isValidUtm(String utmString) {
    if (utmString.length != 12) return false;
    return int.tryParse(utmString) != null;
  }

  /// חישוב מרחק בין שתי נקודות GPS (במטרים)
  static double distanceBetween(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, point1, point2);
  }
}
