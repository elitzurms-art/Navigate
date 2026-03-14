import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../sync/ref_counted_stream.dart';

/// Repository לניהול שידורי חירום (emergency broadcasts)
class EmergencyBroadcastRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final Map<String, RefCountedStream<Map<String, dynamic>?>> _streams =
      {};

  CollectionReference<Map<String, dynamic>> _broadcastsCollection(
          String navigationId) =>
      _firestore
          .collection(AppConstants.navigationsCollection)
          .doc(navigationId)
          .collection('emergency_broadcasts');

  /// יצירת שידור חירום חדש. מחזיר את ה-ID של המסמך שנוצר.
  Future<String> createBroadcast(
    String navigationId, {
    required String message,
    required String instructions,
    required int emergencyMode,
    required String createdBy,
    required List<String> participants,
  }) async {
    final doc = await _broadcastsCollection(navigationId).add({
      'message': message,
      'instructions': instructions,
      'emergencyMode': emergencyMode,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'participants': participants,
      'acknowledgedBy': [],
      'status': 'active',
    });

    // עדכון navigation doc עם דגל חירום
    await _firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .update({
      'emergencyActive': true,
      'emergencyMode': emergencyMode,
      'activeBroadcastId': doc.id,
    });

    return doc.id;
  }

  /// ביטול שידור חירום — יוצר מסמך cancellation ומבטל את המקורי
  Future<String> cancelBroadcast(
    String navigationId, {
    required String? activeBroadcastId,
    required String createdBy,
    required List<String> participants,
  }) async {
    final navRef = _firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId);

    // עדכון סטטוס המקורי ל-cancelled
    if (activeBroadcastId != null) {
      await _broadcastsCollection(navigationId)
          .doc(activeBroadcastId)
          .update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    }

    // יצירת מסמך cancellation
    final cancelDoc = await _broadcastsCollection(navigationId).add({
      'type': 'cancellation',
      'message': 'חזרה לשגרה — המשך בניווט',
      'originalBroadcastId': activeBroadcastId ?? '',
      'participants': participants,
      'acknowledgedBy': [],
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // עדכון דגל חירום על navigation doc
    await navRef.update({
      'emergencyActive': false,
      'cancelBroadcastId': cancelDoc.id,
    });

    return cancelDoc.id;
  }

  /// אישור קבלת שידור חירום ע"י מנווט
  Future<void> acknowledge(
    String navigationId,
    String broadcastId,
    String userId,
  ) async {
    try {
      await _broadcastsCollection(navigationId).doc(broadcastId).update({
        'acknowledgedBy': FieldValue.arrayUnion([userId]),
      });
    } catch (_) {}
  }

  /// מאזין לאישורי קבלה על broadcast ספציפי
  Stream<Map<String, dynamic>?> watchBroadcast(
    String navigationId,
    String broadcastId,
  ) {
    final key = 'broadcast_${navigationId}_$broadcastId';
    _streams[key] ??= RefCountedStream<Map<String, dynamic>?>(
      sourceFactory: () => _broadcastsCollection(navigationId)
          .doc(broadcastId)
          .snapshots()
          .map((snap) => snap.data()),
      pollFallback: () => getBroadcastDoc(navigationId, broadcastId),
    );
    return _streams[key]!.stream;
  }

  /// קריאת one-shot של מסמך broadcast
  Future<Map<String, dynamic>?> getBroadcastDoc(
    String navigationId,
    String broadcastId,
  ) async {
    try {
      final doc =
          await _broadcastsCollection(navigationId).doc(broadcastId).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  /// שליחה מחדש ל-participants שלא אישרו
  Future<void> resendToUnacknowledged(
    String navigationId,
    String broadcastId,
  ) async {
    try {
      final doc =
          await _broadcastsCollection(navigationId).doc(broadcastId).get();
      if (!doc.exists) return;
      final data = doc.data()!;
      final allParticipants =
          List<String>.from(data['participants'] ?? []);
      final acked = List<String>.from(data['acknowledgedBy'] ?? []);
      final missing =
          allParticipants.where((p) => !acked.contains(p)).toList();
      if (missing.isEmpty) return;

      await _broadcastsCollection(navigationId).add({
        'message': data['message'] ?? '',
        'instructions': data['instructions'] ?? '',
        'emergencyMode': data['emergencyMode'] ?? 0,
        'createdBy': data['createdBy'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'participants': missing,
        'acknowledgedBy': [],
        'status': 'retry',
        'originalBroadcastId': broadcastId,
      });
    } catch (_) {}
  }

  /// שליחת ביטול מחדש ל-participants שלא אישרו
  Future<void> resendCancelToUnacknowledged(
    String navigationId,
    String cancelBroadcastId,
  ) async {
    try {
      final doc = await _broadcastsCollection(navigationId)
          .doc(cancelBroadcastId)
          .get();
      if (!doc.exists) return;
      final data = doc.data()!;
      final allParticipants =
          List<String>.from(data['participants'] ?? []);
      final acked = List<String>.from(data['acknowledgedBy'] ?? []);
      final missing =
          allParticipants.where((p) => !acked.contains(p)).toList();
      if (missing.isEmpty) return;

      await _broadcastsCollection(navigationId).add({
        'type': 'cancellation',
        'message': 'חזרה לשגרה — המשך בניווט',
        'originalBroadcastId': cancelBroadcastId,
        'participants': missing,
        'acknowledgedBy': [],
        'createdBy': data['createdBy'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static void clearCache() {
    for (final stream in _streams.values) {
      stream.dispose();
    }
    _streams.clear();
  }
}
