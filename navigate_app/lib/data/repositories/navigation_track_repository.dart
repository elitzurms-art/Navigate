import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import 'package:uuid/uuid.dart';
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/navigator_personal_status.dart';
import '../../services/gps_tracking_service.dart';

/// Repository לניהול רשומות track של מנווטים
class NavigationTrackRepository {
  final AppDatabase _db = AppDatabase();

  /// שליפת רשומת track למנווט ספציפי בניווט ספציפי
  Future<NavigationTrack?> getByNavigatorAndNavigation(
    String navigatorUserId,
    String navigationId,
  ) async {
    return await (_db.select(_db.navigationTracks)
          ..where((t) =>
              t.navigatorUserId.equals(navigatorUserId) &
              t.navigationId.equals(navigationId)))
        .getSingleOrNull();
  }

  /// שליפת כל ה-tracks לניווט (מקומי)
  Future<List<NavigationTrack>> getByNavigation(String navigationId) async {
    return await (_db.select(_db.navigationTracks)
          ..where((t) => t.navigationId.equals(navigationId)))
        .get();
  }

  /// שליפת tracks מ-Firestore (לשימוש במפקד/מנהל שאין לו tracks מקומיים)
  Future<List<NavigationTrack>> getByNavigationFromFirestore(String navigationId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: navigationId)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return NavigationTrack(
        id: data['id'] as String? ?? doc.id,
        navigationId: data['navigationId'] as String? ?? navigationId,
        navigatorUserId: data['navigatorUserId'] as String? ?? '',
        trackPointsJson: data['trackPointsJson'] as String? ?? '[]',
        stabbingsJson: data['stabbingsJson'] as String? ?? '[]',
        startedAt: data['startedAt'] != null
            ? (data['startedAt'] is Timestamp
                ? (data['startedAt'] as Timestamp).toDate()
                : DateTime.tryParse(data['startedAt'].toString()) ?? DateTime.now())
            : DateTime.now(),
        endedAt: data['endedAt'] != null
            ? (data['endedAt'] is Timestamp
                ? (data['endedAt'] as Timestamp).toDate()
                : DateTime.tryParse(data['endedAt'].toString()))
            : null,
        isActive: data['isActive'] as bool? ?? false,
        isDisqualified: data['isDisqualified'] as bool? ?? false,
        overrideAllowOpenMap: data['overrideAllowOpenMap'] as bool? ?? false,
        overrideShowSelfLocation: data['overrideShowSelfLocation'] as bool? ?? false,
        overrideShowRouteOnMap: data['overrideShowRouteOnMap'] as bool? ?? false,
      );
    }).toList();
  }

  /// התחלת ניווט — יצירת רשומת track עם isActive=true
  Future<NavigationTrack> startNavigation({
    required String navigatorUserId,
    required String navigationId,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    await _db.into(_db.navigationTracks).insert(
      NavigationTracksCompanion.insert(
        id: id,
        navigationId: navigationId,
        navigatorUserId: navigatorUserId,
        trackPointsJson: '[]',
        stabbingsJson: '[]',
        startedAt: now,
        isActive: true,
        isDisqualified: false,
      ),
    );

    return (await (_db.select(_db.navigationTracks)
          ..where((t) => t.id.equals(id)))
        .getSingle());
  }

  /// סיום ניווט — עדכון isActive=false, endedAt=now
  Future<void> endNavigation(String trackId) async {
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      isActive: const Value(false),
      endedAt: Value(DateTime.now()),
    ));
  }

  /// שליפת track לפי מזהה
  Future<NavigationTrack> getById(String trackId) async {
    return await (_db.select(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .getSingle();
  }

  /// עדכון נקודות מסלול (batch — כל X שניות)
  Future<void> updateTrackPoints(String trackId, List<TrackPoint> points) async {
    final json = jsonEncode(points.map((p) => p.toMap()).toList());
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(trackPointsJson: Value(json)));
  }

  /// סנכרון track ל-Firestore דרך SyncManager
  Future<void> syncTrackToFirestore(NavigationTrack track) async {
    await SyncManager().queueOperation(
      collection: AppConstants.navigationTracksCollection,
      documentId: track.id,
      operation: 'update',
      data: {
        'id': track.id,
        'navigationId': track.navigationId,
        'navigatorUserId': track.navigatorUserId,
        'trackPointsJson': track.trackPointsJson,
        'stabbingsJson': track.stabbingsJson,
        'startedAt': track.startedAt.toIso8601String(),
        'endedAt': track.endedAt?.toIso8601String(),
        'isActive': track.isActive,
        'isDisqualified': track.isDisqualified,
        'overrideAllowOpenMap': track.overrideAllowOpenMap,
        'overrideShowSelfLocation': track.overrideShowSelfLocation,
        'overrideShowRouteOnMap': track.overrideShowRouteOnMap,
      },
      priority: SyncPriority.high,
    );
  }

  /// פסילת מנווט — סימון isDisqualified=true ב-Drift + Firestore
  Future<void> disqualifyNavigator(String trackId) async {
    // עדכון ב-Drift
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(const NavigationTracksCompanion(
      isDisqualified: Value(true),
    ));

    // עדכון ישיר ב-Firestore
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({'isDisqualified': true});
    } catch (_) {
      // Firestore לא זמין — יתוקן בסנכרון הבא
    }
  }

  /// ביטול פסילת מנווט — סימון isDisqualified=false ב-Drift + Firestore
  Future<void> undoDisqualification(String trackId) async {
    // עדכון ב-Drift
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(const NavigationTracksCompanion(
      isDisqualified: Value(false),
    ));

    // עדכון ישיר ב-Firestore
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({'isDisqualified': false});
    } catch (_) {
      // Firestore לא זמין — יתוקן בסנכרון הבא
    }
  }

  /// עדכון דריסות הגדרות מפה פר-מנווט (Drift + Firestore)
  Future<void> updateMapOverrides(
    String trackId, {
    required bool allowOpenMap,
    required bool showSelfLocation,
    required bool showRouteOnMap,
  }) async {
    // עדכון ב-Drift
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideAllowOpenMap: Value(allowOpenMap),
      overrideShowSelfLocation: Value(showSelfLocation),
      overrideShowRouteOnMap: Value(showRouteOnMap),
    ));

    // עדכון ישיר ב-Firestore
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({
        'overrideAllowOpenMap': allowOpenMap,
        'overrideShowSelfLocation': showSelfLocation,
        'overrideShowRouteOnMap': showRouteOnMap,
      });
    } catch (_) {
      // Firestore לא זמין — יתוקן בסנכרון הבא
    }
  }

  /// מחיקת tracks למנווט ספציפי בניווט ספציפי (לשימוש מפקד — התחלה/איפוס)
  Future<void> deleteByNavigator(String navigationId, String navigatorUserId) async {
    // מחיקה מ-Drift
    await (_db.delete(_db.navigationTracks)
          ..where((t) =>
              t.navigationId.equals(navigationId) &
              t.navigatorUserId.equals(navigatorUserId)))
        .go();

    // מחיקה מ-Firestore
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .where('navigatorUserId', isEqualTo: navigatorUserId)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (_) {
      // Firestore לא זמין — יתוקן בסנכרון הבא
    }
  }

  /// מחיקת כל ה-tracks לניווט (איפוס לפני התחלה מחדש)
  Future<void> deleteByNavigation(String navigationId) async {
    await (_db.delete(_db.navigationTracks)
          ..where((t) => t.navigationId.equals(navigationId)))
        .go();
  }

  /// איפוס כל ה-tracks לניווט — endedAt=null, isActive=false
  /// (לשימוש כשניווט חוזר ל-waiting/active אחרי סיום כללי)
  Future<void> resetTracksForNavigation(String navigationId) async {
    // איפוס מקומי ב-Drift
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.navigationId.equals(navigationId)))
        .write(const NavigationTracksCompanion(
      endedAt: Value(null),
      isActive: Value(false),
    ));

    // איפוס ב-Firestore
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'endedAt': null,
          'isActive': false,
        });
      }
    } catch (_) {
      // Firestore לא זמין — יתוקן בסנכרון הבא
    }
  }

  /// גזירת סטטוס אישי מרשומת track
  Future<NavigatorPersonalStatus> getPersonalStatus({
    required String navigatorUserId,
    required String navigationId,
  }) async {
    final track = await getByNavigatorAndNavigation(
      navigatorUserId,
      navigationId,
    );

    if (track == null) {
      return NavigatorPersonalStatus.waiting;
    }

    return NavigatorPersonalStatus.deriveFromTrack(
      hasTrack: true,
      isActive: track.isActive,
      endedAt: track.endedAt,
    );
  }
}
