import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/security_violation.dart';

/// Repository לניהול חריגות אבטחה
class SecurityViolationRepository {
  static const String _key = 'security_violations';

  /// יצירת רישום חריגה
  Future<void> create(SecurityViolation violation) async {
    print('🚨 רישום חריגה: ${violation.type.displayName} - ${violation.navigatorId}');

    try {
      final violations = await _getAll();
      violations.add(violation);

      final prefs = await SharedPreferences.getInstance();
      final violationsJson = violations.map((v) => jsonEncode(v.toMap())).toList();
      await prefs.setStringList(_key, violationsJson);

      print('✓ חריגה נשמרה');
    } catch (e) {
      print('❌ שגיאה בשמירת חריגה: $e');
    }
  }

  Future<List<SecurityViolation>> _getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final violationsJson = prefs.getStringList(_key) ?? [];

      return violationsJson.map((json) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return SecurityViolation.fromMap(map);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// קבלת חריגות לניווט
  Future<List<SecurityViolation>> getByNavigation(String navigationId) async {
    try {
      final all = await _getAll();
      return all.where((v) => v.navigationId == navigationId).toList();
    } catch (e) {
      print('❌ שגיאה בטעינת חריגות: $e');
      return [];
    }
  }

  /// קבלת חריגות למנווט
  Future<List<SecurityViolation>> getByNavigator(String navigatorId) async {
    try {
      final all = await _getAll();
      return all.where((v) => v.navigatorId == navigatorId).toList();
    } catch (e) {
      print('❌ שגיאה בטעינת חריגות: $e');
      return [];
    }
  }

  /// ספירת חריגות (לפי חומרה)
  Future<Map<ViolationSeverity, int>> countBySeverity(String navigationId) async {
    final violations = await getByNavigation(navigationId);

    Map<ViolationSeverity, int> counts = {};
    for (final severity in ViolationSeverity.values) {
      counts[severity] = violations.where((v) => v.severity == severity).length;
    }

    return counts;
  }

  /// האם יש חריגות קריטיות
  Future<bool> hasCriticalViolations(String navigationId) async {
    final violations = await getByNavigation(navigationId);
    return violations.any((v) => v.severity == ViolationSeverity.critical);
  }

  /// מחיקת חריגות (לניקוי)
  Future<void> deleteByNavigation(String navigationId) async {
    try {
      final all = await _getAll();
      final filtered = all.where((v) => v.navigationId != navigationId).toList();

      final prefs = await SharedPreferences.getInstance();
      final violationsJson = filtered.map((v) => jsonEncode(v.toMap())).toList();
      await prefs.setStringList(_key, violationsJson);

      print('✓ חריגות נמחקו');
    } catch (e) {
      print('❌ שגיאה במחיקת חריגות: $e');
    }
  }
}
