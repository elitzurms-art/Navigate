import 'package:cloud_firestore/cloud_firestore.dart';

/// שירות לחישוב הפרש שעון בין המכשיר לשרת Firebase
class ClockSyncService {
  static final ClockSyncService _instance = ClockSyncService._();
  factory ClockSyncService() => _instance;
  ClockSyncService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// מחשב את ההפרש בין שעון המכשיר לשעון השרת.
  /// מחזיר Duration חיובי אם השרת מקדים, שלילי אם המכשיר מקדים.
  Future<Duration> computeServerTimeOffset() async {
    try {
      final doc = _firestore.collection('sync_metadata').doc('_clock_check');
      final beforeWrite = DateTime.now();
      await doc.set({'t': FieldValue.serverTimestamp()});
      final snap = await doc.get();
      final afterRead = DateTime.now();

      final serverTime = (snap.data()?['t'] as Timestamp?)?.toDate();
      if (serverTime == null) return Duration.zero;

      // הזמן האמיתי של הכתיבה הוא בערך באמצע בין beforeWrite ל-afterRead
      final estimatedLocalTime = beforeWrite.add(
        Duration(
          milliseconds:
              afterRead.difference(beforeWrite).inMilliseconds ~/ 2,
        ),
      );
      return serverTime.difference(estimatedLocalTime);
    } catch (_) {
      return Duration.zero;
    }
  }
}
