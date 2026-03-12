import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/checkpoint_punch.dart';

/// Repository להתראות מנווטים — Firestore-based
class NavigatorAlertRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _alertsCollection(String navigationId) {
    return _firestore
        .collection('navigations')
        .doc(navigationId)
        .collection('navigator_alerts');
  }

  /// יצירת התראה חדשה
  Future<void> create(NavigatorAlert alert) async {
    print('DEBUG NavigatorAlertRepository: creating alert ${alert.type.displayName} for ${alert.navigatorId}');
    try {
      await _alertsCollection(alert.navigationId).doc(alert.id).set(alert.toMap());
      print('DEBUG NavigatorAlertRepository: alert saved');
    } catch (e) {
      print('DEBUG NavigatorAlertRepository: error creating alert: $e');
      rethrow;
    }
  }

  /// עדכון התראה (סגירה/resolve)
  Future<void> resolve(String navigationId, String alertId, String resolvedBy) async {
    try {
      await _alertsCollection(navigationId).doc(alertId).update({
        'isActive': false,
        'resolvedAt': DateTime.now().toIso8601String(),
        'resolvedBy': resolvedBy,
      });
      print('DEBUG NavigatorAlertRepository: alert resolved');
    } catch (e) {
      print('DEBUG NavigatorAlertRepository: error resolving alert: $e');
    }
  }

  /// קבלת כל ההתראות לניווט
  Future<List<NavigatorAlert>> getAll(String navigationId) async {
    try {
      final snapshot = await _alertsCollection(navigationId)
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        return NavigatorAlert.fromMap(doc.data());
      }).toList();
    } catch (e) {
      print('DEBUG NavigatorAlertRepository: error loading alerts: $e');
      return [];
    }
  }

  /// קבלת התראות פעילות לניווט (לא healthReport)
  Future<List<NavigatorAlert>> getActiveByNavigation(String navigationId) async {
    try {
      final snapshot = await _alertsCollection(navigationId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => NavigatorAlert.fromMap(doc.data()))
          .where((a) => a.type != AlertType.healthReport)
          .toList();
    } catch (e) {
      print('DEBUG NavigatorAlertRepository: error loading active alerts: $e');
      return [];
    }
  }

  /// האזנה בזמן אמת להתראות פעילות (לשימוש מפקדים)
  Stream<List<NavigatorAlert>> watchActiveAlerts(String navigationId) {
    return _alertsCollection(navigationId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NavigatorAlert.fromMap(doc.data()))
          .where((a) => a.type != AlertType.healthReport)
          .toList();
    });
  }

  /// האזנה להתראות resolved (למנווט — לקבלת reset מרחוק)
  Stream<List<NavigatorAlert>> watchResolvedAlerts(String navigationId, String navigatorId) {
    return _alertsCollection(navigationId)
        .where('navigatorId', isEqualTo: navigatorId)
        .where('isActive', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NavigatorAlert.fromMap(doc.data()))
          .toList();
    });
  }

  /// סגירת כל התראות healthCheckExpired פעילות למנווט (כשמדווח תקינות)
  Future<void> resolveHealthCheckAlerts(String navigationId, String navigatorId, String resolvedBy) async {
    try {
      final snapshot = await _alertsCollection(navigationId)
          .where('navigatorId', isEqualTo: navigatorId)
          .where('type', isEqualTo: AlertType.healthCheckExpired.code)
          .where('isActive', isEqualTo: true)
          .get();
      for (final doc in snapshot.docs) {
        await resolve(navigationId, doc.id, resolvedBy);
      }
    } catch (e) {
      print('DEBUG NavigatorAlertRepository: error resolving health check alerts: $e');
    }
  }

  /// מחיקת כל ההתראות לניווט (איפוס לפני התחלה מחדש)
  Future<void> deleteByNavigation(String navigationId) async {
    // מחיקה מ-Firestore (non-blocking — לא חוסם UI)
    unawaited(() async {
      try {
        final snapshot = await _alertsCollection(navigationId).get();
        if (snapshot.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in snapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      } catch (e) {
        print('DEBUG NavigatorAlertRepository: error deleting by navigation: $e');
      }
    }());
  }

  /// קבלת התראות למנווט ספציפי (ללא healthReport)
  Future<List<NavigatorAlert>> getByNavigator(String navigationId, String navigatorId) async {
    final all = await getAll(navigationId);
    return all.where((a) => a.navigatorId == navigatorId && a.type != AlertType.healthReport).toList();
  }

  /// ספירת התראות פעילות
  Future<int> countActive(String navigationId) async {
    final active = await getActiveByNavigation(navigationId);
    return active.length;
  }

  /// עדכון צ'קליסט ברבור (Firestore only)
  Future<void> updateBarburChecklist(String navigationId, String alertId, Map<String, bool> checklist) async {
    try {
      await _alertsCollection(navigationId).doc(alertId).update({
        'barburChecklist': checklist,
      });
    } catch (e) {
      print('DEBUG NavigatorAlertRepository: error updating barbur checklist: $e');
    }
  }

  /// קבלת התראת ברבור פעילה למנווט (לשחזור state אחרי restart)
  Future<NavigatorAlert?> getActiveBarburAlert(String navigationId, String navigatorId) async {
    try {
      final snapshot = await _alertsCollection(navigationId)
          .where('navigatorId', isEqualTo: navigatorId)
          .where('type', isEqualTo: AlertType.barbur.code)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return NavigatorAlert.fromMap(snapshot.docs.first.data());
    } catch (e) {
      print('DEBUG NavigatorAlertRepository: error getting active barbur alert: $e');
      return null;
    }
  }

  /// האזנה בזמן אמת להתראה ספציפית (לשימוש מנווט — מעקב אחרי צ'קליסט ברבור)
  Stream<NavigatorAlert?> watchAlert(String navigationId, String alertId) {
    return _alertsCollection(navigationId)
        .doc(alertId)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return NavigatorAlert.fromMap(doc.data()!);
    });
  }
}
