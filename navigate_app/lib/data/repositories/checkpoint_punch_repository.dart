import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/checkpoint_punch.dart';

/// Repository לניהול דקירות נקודות
class CheckpointPunchRepository {
  static const String _key = 'checkpoint_punches';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _punchesCollection(String navigationId) {
    return _firestore
        .collection('navigations')
        .doc(navigationId)
        .collection('checkpoint_punches');
  }

  /// יצירת דקירה חדשה
  Future<void> create(CheckpointPunch punch) async {
    print('DEBUG CheckpointPunchRepo: creating punch ${punch.checkpointId}');
    try {
      // שמירה מקומית (SharedPreferences)
      final punches = await getAll();
      punches.add(punch);

      final prefs = await SharedPreferences.getInstance();
      final punchesJson = punches.map((p) => jsonEncode(p.toMap())).toList();
      await prefs.setStringList(_key, punchesJson);

      // סנכרון ל-Firestore
      try {
        await _punchesCollection(punch.navigationId).doc(punch.id).set(punch.toMap());
        print('DEBUG CheckpointPunchRepo: punch synced to Firestore');
      } catch (e) {
        print('DEBUG CheckpointPunchRepo: Firestore sync failed (offline?): $e');
      }
    } catch (e) {
      print('DEBUG CheckpointPunchRepo: error creating punch: $e');
      rethrow;
    }
  }

  /// עדכון דקירה (שינוי סטטוס)
  Future<void> update(CheckpointPunch punch) async {
    try {
      // עדכון מקומי
      final punches = await getAll();
      final index = punches.indexWhere((p) => p.id == punch.id);
      if (index != -1) {
        punches[index] = punch;

        final prefs = await SharedPreferences.getInstance();
        final punchesJson = punches.map((p) => jsonEncode(p.toMap())).toList();
        await prefs.setStringList(_key, punchesJson);

        print('DEBUG CheckpointPunchRepo: punch updated locally');
      }

      // סנכרון ל-Firestore
      try {
        await _punchesCollection(punch.navigationId).doc(punch.id).set(punch.toMap());
        print('DEBUG CheckpointPunchRepo: punch update synced to Firestore');
      } catch (e) {
        print('DEBUG CheckpointPunchRepo: Firestore update sync failed: $e');
      }
    } catch (e) {
      print('DEBUG CheckpointPunchRepo: error updating punch: $e');
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

  /// קבלת דקירות לניווט מ-Firestore (לשימוש מפקדים)
  Future<List<CheckpointPunch>> getByNavigationFromFirestore(String navigationId) async {
    try {
      final snapshot = await _punchesCollection(navigationId).get();
      return snapshot.docs
          .map((doc) => CheckpointPunch.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('DEBUG CheckpointPunchRepo: Firestore getByNavigation error: $e');
      return [];
    }
  }

  /// האזנה בזמן אמת לדקירות (לשימוש מפקדים)
  Stream<List<CheckpointPunch>> watchPunches(String navigationId) {
    return _punchesCollection(navigationId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => CheckpointPunch.fromMap(doc.data()))
          .toList();
    });
  }

  /// מחיקת כל הדקירות לניווט (איפוס לפני התחלה מחדש)
  Future<void> deleteByNavigation(String navigationId) async {
    try {
      // מחיקה מקומית — השארת דקירות של ניווטים אחרים
      final all = await getAll();
      final filtered = all.where((p) => p.navigationId != navigationId).toList();
      final prefs = await SharedPreferences.getInstance();
      final json = filtered.map((p) => jsonEncode(p.toMap())).toList();
      await prefs.setStringList(_key, json);

      // מחיקה מ-Firestore
      try {
        final snapshot = await _punchesCollection(navigationId).get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}
    } catch (e) {
      print('DEBUG CheckpointPunchRepo: error deleting by navigation: $e');
    }
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
