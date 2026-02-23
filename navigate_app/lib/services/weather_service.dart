import 'dart:convert';
import 'package:http/http.dart' as http;

/// תוצאת מזג אוויר
class WeatherResult {
  final double temperature; // celsius
  final String description; // תיאור (עברית אם זמין)
  final double windSpeed; // m/s
  final int humidity; // %
  final String? icon;
  final String? notes; // דגשים מיוחדים

  const WeatherResult({
    required this.temperature,
    required this.description,
    required this.windSpeed,
    required this.humidity,
    this.icon,
    this.notes,
  });
}

/// שירות מזג אוויר — OpenWeatherMap API
class WeatherService {
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  final String? _apiKey;

  WeatherService({String? apiKey}) : _apiKey = apiKey;

  /// משיכת תחזית מזג אוויר לפי מיקום ותאריך
  /// [lat], [lng] — קואורדינטות מרכז הניווט
  /// [date] — תאריך הניווט המתוכנן
  Future<WeatherResult?> getWeatherForLocation({
    required double lat,
    required double lng,
    required DateTime date,
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) return null;

    try {
      final now = DateTime.now();
      final daysUntil = date.difference(now).inDays;

      if (daysUntil < 0) {
        // תאריך עבר — אין תחזית
        return null;
      }

      if (daysUntil <= 5) {
        // תחזית 5 ימים — forecast API
        return await _fetchForecast(lat, lng, date);
      }

      // מעבר ל-5 ימים — לא זמין בחינם
      return null;
    } catch (e) {
      print('WeatherService: Error fetching weather: $e');
      return null;
    }
  }

  Future<WeatherResult?> _fetchForecast(double lat, double lng, DateTime targetDate) async {
    final uri = Uri.parse('$_baseUrl/forecast'
        '?lat=$lat&lng=$lng'
        '&appid=$_apiKey'
        '&units=metric'
        '&lang=he');

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    final list = data['list'] as List?;
    if (list == null || list.isEmpty) return null;

    // מציאת התחזית הקרובה ביותר לתאריך הרצוי
    Map<String, dynamic>? closest;
    int closestDiff = 999999;

    final targetTimestamp = targetDate.millisecondsSinceEpoch ~/ 1000;

    for (final item in list) {
      final dt = item['dt'] as int;
      final diff = (dt - targetTimestamp).abs();
      if (diff < closestDiff) {
        closestDiff = diff;
        closest = item as Map<String, dynamic>;
      }
    }

    if (closest == null) return null;

    final main = closest['main'] as Map<String, dynamic>;
    final weather = (closest['weather'] as List).first as Map<String, dynamic>;
    final wind = closest['wind'] as Map<String, dynamic>?;

    final temp = (main['temp'] as num).toDouble();
    final windSpeed = (wind?['speed'] as num?)?.toDouble() ?? 0;
    final humidity = (main['humidity'] as num?)?.toInt() ?? 0;

    // דגשים מיוחדים
    String? notes;
    if (temp > 35) notes = 'חום קיצוני — יש להגביר שתיית מים';
    if (temp < 5) notes = 'קור קיצוני — יש לוודא ביגוד מתאים';
    if (windSpeed > 15) notes = '${notes != null ? "$notes\n" : ""}רוחות חזקות';

    return WeatherResult(
      temperature: temp,
      description: weather['description'] as String? ?? '',
      windSpeed: windSpeed,
      humidity: humidity,
      icon: weather['icon'] as String?,
      notes: notes,
    );
  }
}
