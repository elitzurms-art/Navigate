import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/checkpoint_punch.dart';

/// Repository לניהול דקירות נקודות
class CheckpointPunchRepository {
  static const String _key = 'checkpoint_punches';

  /// יצירת דקירה חדשה
  Future<void> create(CheckpointPunch punch) async {
    print('📌 יוצר דקירה: ${punch.checkpointId}');
    try {
      final punches = await getAll();
      punches.add(punch);

      final prefs = await SharedPreferences.getInstance();
      final punchesJson = punches.map((p) => jsonEncode(p.toMap())).toList();
      await prefs.setStringList(_key, punchesJson);

      print('✓ דקירה נשמרה');

      // TODO: סנכרון ל-Firestore
    } catch (e) {
      print('❌ שגיאה ביצירת דקירה: $e');
      rethrow;
    }
  }

  /// עדכון דקירה (שינוי סטטוס)
  Future<void> update(CheckpointPunch punch) async {
    try {
      final punches = await getAll();
      final index = punches.indexWhere((p) => p.id == punch.id);
      if (index != -1) {
        punches[index] = punch;

        final prefs = await SharedPreferences.getInstance();
        final punchesJson = punches.map((p) => jsonEncode(p.toMap())).toList();
        await prefs.setStringList(_key, punchesJson);

        print('✓ דקירה עודכנה');
      }
    } catch (e) {
      print('❌ שגיאה בעדכון דקירה: $e');
      rethrow;
    }
  }

  /// מחיקת דקירה (סימון כמחוק)
  Future<void> markAsDeleted(String punchId) async {
    try {
      final punches = await getAll();
      final punch = punches.firstWhere((p) => p.id == punchId);
      final updated = punch.copyWith(status: PunchStatus.deleted);
      await update(updated);
    } catch (e) {
      print('❌ שגיאה במחיקת דקירה: $e');
    }
  }

  /// קבלת כל הדקירות
  Future<List<CheckpointPunch>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final punchesJson = prefs.getStringList(_key) ?? [];

      return punchesJson.map((json) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return CheckpointPunch.fromMap(map);
      }).toList();
    } catch (e) {
      print('❌ שגיאה בטעינת דקירות: $e');
      return [];
    }
  }

  /// קבלת דקירות לניווט
  Future<List<CheckpointPunch>> getByNavigation(String navigationId) async {
    final all = await getAll();
    return all.where((p) => p.navigationId == navigationId).toList();
  }

  /// קבלת דקירות למנווט
  Future<List<CheckpointPunch>> getByNavigator(String navigatorId) async {
    final all = await getAll();
    return all.where((p) => p.navigatorId == navigatorId).toList();
  }

  /// אישור דקירה
  Future<void> approve(String punchId, String approvedBy) async {
    final punches = await getAll();
    final punch = punches.firstWhere((p) => p.id == punchId);
    final updated = punch.copyWith(
      status: PunchStatus.approved,
      approvalTime: DateTime.now(),
      approvedBy: approvedBy,
    );
    await update(updated);
  }

  /// דחיית דקירה
  Future<void> reject(String punchId, String reason) async {
    final punches = await getAll();
    final punch = punches.firstWhere((p) => p.id == punchId);
    final updated = punch.copyWith(
      status: PunchStatus.rejected,
      rejectionReason: reason,
    );
    await update(updated);
  }
}
