import 'dart:convert';
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

  /// שליפת כל ה-tracks לניווט
  Future<List<NavigationTrack>> getByNavigation(String navigationId) async {
    return await (_db.select(_db.navigationTracks)
          ..where((t) => t.navigationId.equals(navigationId)))
        .get();
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
      },
      priority: SyncPriority.high,
    );
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
