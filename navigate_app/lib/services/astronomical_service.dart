import 'dart:math';

/// שירות חישובי אסטרונומיה — שקיעה, זריחה, תאורת ירח
class AstronomicalService {
  /// חישוב שעת זריחה
  static DateTime getSunrise(double lat, double lng, DateTime date) {
    final times = _calculateSunTimes(lat, lng, date);
    return times['sunrise']!;
  }

  /// חישוב שעת שקיעה
  static DateTime getSunset(double lat, double lng, DateTime date) {
    final times = _calculateSunTimes(lat, lng, date);
    return times['sunset']!;
  }

  /// חישוב אחוזי תאורת ירח (0.0-1.0)
  static double getMoonIllumination(DateTime date) {
    // Known new moon: January 6, 2000 18:14 UTC
    final knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
    final synodicMonth = 29.53058867; // days

    final daysSinceKnown = date.toUtc().difference(knownNewMoon).inHours / 24.0;
    final phase = (daysSinceKnown % synodicMonth) / synodicMonth;

    // Illumination: 0 at new moon, 1 at full moon
    return (1 - cos(phase * 2 * pi)) / 2;
  }

  /// חישוב זריחה ושקיעה לפי אלגוריתם NOAA פשוט
  static Map<String, DateTime> _calculateSunTimes(double lat, double lng, DateTime date) {
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;

    // Solar declination (approximate)
    final declination = -23.45 * cos(2 * pi / 365 * (dayOfYear + 10));
    final decRad = declination * pi / 180;
    final latRad = lat * pi / 180;

    // Hour angle
    final cosHourAngle = (-sin(0.8333 * pi / 180) - sin(latRad) * sin(decRad)) /
                          (cos(latRad) * cos(decRad));

    // Clamp for polar regions
    final clampedCos = cosHourAngle.clamp(-1.0, 1.0);
    final hourAngle = acos(clampedCos) * 180 / pi;

    // Equation of time (approximate, in minutes)
    final b = 2 * pi * (dayOfYear - 81) / 365;
    final eqTime = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b);

    // Solar noon in minutes from midnight UTC
    final solarNoonMinutes = 720 - 4 * lng - eqTime;

    // Sunrise and sunset in minutes from midnight UTC
    final sunriseMinutes = solarNoonMinutes - hourAngle * 4;
    final sunsetMinutes = solarNoonMinutes + hourAngle * 4;

    // Convert to local DateTime (Israel is UTC+2/+3)
    // We return UTC and let the caller handle timezone
    final sunriseUtc = DateTime.utc(date.year, date.month, date.day)
        .add(Duration(minutes: sunriseMinutes.round()));
    final sunsetUtc = DateTime.utc(date.year, date.month, date.day)
        .add(Duration(minutes: sunsetMinutes.round()));

    return {
      'sunrise': sunriseUtc.toLocal(),
      'sunset': sunsetUtc.toLocal(),
    };
  }
}
