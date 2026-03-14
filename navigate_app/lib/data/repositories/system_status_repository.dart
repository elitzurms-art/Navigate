import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/navigator_status.dart';
import '../sync/ref_counted_stream.dart';

/// Repository לניהול סטטוסי מנווטים (system_status subcollection)
class SystemStatusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache סטטי — כי Repositories לא singletons
  static final Map<String, RefCountedStream<Map<String, NavigatorStatus>>>
      _streams = {};

  CollectionReference<Map<String, dynamic>> _statusCollection(
          String navigationId) =>
      _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection('system_status');

  /// מאזין לסטטוסי כל המנווטים בניווט נתון (ref-counted + polling fallback)
  Stream<Map<String, NavigatorStatus>> watchStatuses(String navigationId) {
    final key = 'system_status_$navigationId';
    _streams[key] ??= RefCountedStream<Map<String, NavigatorStatus>>(
      sourceFactory: () => _statusCollection(navigationId)
          .snapshots()
          .map((snap) => _parseStatuses(snap)),
      pollFallback: () => pollStatuses(navigationId),
    );
    return _streams[key]!.stream;
  }

  /// שליפה יזומה של סטטוסים מ-Firestore
  Future<Map<String, NavigatorStatus>> pollStatuses(
      String navigationId) async {
    final snap = await _statusCollection(navigationId).get();
    return _parseStatuses(snap);
  }

  /// דיווח סטטוס מנווט ל-Firestore
  Future<void> reportStatus(
    String navigationId,
    String navigatorId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _statusCollection(navigationId).doc(navigatorId).set(
            data,
            SetOptions(merge: true),
          );
    } catch (_) {}
  }

  /// מחיקת כל סטטוסי המנווטים בניווט
  Future<void> deleteAll(String navigationId) async {
    try {
      final snap = await _statusCollection(navigationId).get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  Map<String, NavigatorStatus> _parseStatuses(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final result = <String, NavigatorStatus>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final navigatorId = data['navigatorId'] as String? ?? doc.id;
      result[navigatorId] = NavigatorStatus.fromFirestore(data);
    }
    return result;
  }

  /// ניקוי cache סטטי (לשימוש בעת התנתקות)
  static void clearCache() {
    for (final stream in _streams.values) {
      stream.dispose();
    }
    _streams.clear();
  }
}
