import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/checkpoint_punch.dart';

/// Repository להתראות מנווטים
class NavigatorAlertRepository {
  static const String _key = 'navigator_alerts';

  /// יצירת התראה חדשה
  Future<void> create(NavigatorAlert alert) async {
    print('🚨 יוצר התראה: ${alert.type.displayName} - ${alert.navigatorId}');
    try {
      final alerts = await getAll();
      alerts.add(alert);

      final prefs = await SharedPreferences.getInstance();
      final alertsJson = alerts.map((a) => jsonEncode(a.toMap())).toList();
      await prefs.setStringList(_key, alertsJson);

      print('✓ התראה נשמרה');

      // TODO: שליחת push notification למפקדים
    } catch (e) {
      print('❌ שגיאה ביצירת התראה: $e');
      rethrow;
    }
  }

  /// עדכון התראה (סגירה)
  Future<void> resolve(String alertId, String resolvedBy) async {
    try {
      final alerts = await getAll();
      final index = alerts.indexWhere((a) => a.id == alertId);
      if (index != -1) {
        final resolved = NavigatorAlert(
          id: alerts[index].id,
          navigationId: alerts[index].navigationId,
          navigatorId: alerts[index].navigatorId,
          type: alerts[index].type,
          location: alerts[index].location,
          timestamp: alerts[index].timestamp,
          isActive: false,
          resolvedAt: DateTime.now(),
          resolvedBy: resolvedBy,
        );

        alerts[index] = resolved;

        final prefs = await SharedPreferences.getInstance();
        final alertsJson = alerts.map((a) => jsonEncode(a.toMap())).toList();
        await prefs.setStringList(_key, alertsJson);

        print('✓ התראה נסגרה');
      }
    } catch (e) {
      print('❌ שגיאה בעדכון התראה: $e');
    }
  }

  /// קבלת כל ההתראות
  Future<List<NavigatorAlert>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = prefs.getStringList(_key) ?? [];

      return alertsJson.map((json) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return NavigatorAlert.fromMap(map);
      }).toList();
    } catch (e) {
      print('❌ שגיאה בטעינת התראות: $e');
      return [];
    }
  }

  /// קבלת התראות פעילות לניווט
  Future<List<NavigatorAlert>> getActiveByNavigation(String navigationId) async {
    final all = await getAll();
    return all.where((a) => a.navigationId == navigationId && a.isActive).toList();
  }

  /// קבלת התראות למנווט
  Future<List<NavigatorAlert>> getByNavigator(String navigatorId) async {
    final all = await getAll();
    return all.where((a) => a.navigatorId == navigatorId).toList();
  }

  /// ספירת התראות פעילות
  Future<int> countActive(String navigationId) async {
    final active = await getActiveByNavigation(navigationId);
    return active.length;
  }
}
