import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import 'package:uuid/uuid.dart';
import '../datasources/local/app_database.dart';
import '../sync/sync_manager.dart';
import '../sync/ref_counted_stream.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/navigator_personal_status.dart';
import '../../services/gps_tracking_service.dart';

/// Repository לניהול רשומות track של מנווטים
class NavigationTrackRepository {
  final AppDatabase _db = AppDatabase();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache סטטי — כי Repositories לא singletons
  static final Map<String, RefCountedStream<List<Map<String, dynamic>>>>
      _tracksStreams = {};
  static final Map<String, RefCountedStream<Map<String, dynamic>?>>
      _trackDocStreams = {};

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
        overrideAllowManualPosition: data['overrideAllowManualPosition'] as bool? ?? false,
        overrideWalkieTalkieEnabled: data['overrideWalkieTalkieEnabled'] as bool? ?? false,
        manualPositionUsed: data['manualPositionUsed'] as bool? ?? false,
        manualPositionUsedAt: data['manualPositionUsedAt'] != null
            ? (data['manualPositionUsedAt'] is Timestamp
                ? (data['manualPositionUsedAt'] as Timestamp).toDate()
                : DateTime.tryParse(data['manualPositionUsedAt'].toString()))
            : null,
        isGroupSecondary: data['isGroupSecondary'] as bool? ?? false,
        starCurrentPointIndex: (data['starCurrentPointIndex'] as num?)?.toInt(),
        starLearningEndTime: data['starLearningEndTime'] != null
            ? (data['starLearningEndTime'] is Timestamp
                ? (data['starLearningEndTime'] as Timestamp).toDate()
                : DateTime.tryParse(data['starLearningEndTime'].toString()))
            : null,
        starNavigatingEndTime: data['starNavigatingEndTime'] != null
            ? (data['starNavigatingEndTime'] is Timestamp
                ? (data['starNavigatingEndTime'] as Timestamp).toDate()
                : DateTime.tryParse(data['starNavigatingEndTime'].toString()))
            : null,
        starReturnedToCenter: data['starReturnedToCenter'] as bool? ?? false,
        overrideRevealEnabled: data['overrideRevealEnabled'] as bool?,
        overrideAlertSoundVolumesJson: data['overrideAlertSoundVolumes'] is Map
            ? jsonEncode(data['overrideAlertSoundVolumes'])
            : data['overrideAlertSoundVolumesJson'] as String?,
      );
    }).toList();
  }

  /// התחלת ניווט — יצירת רשומת track עם isActive=true
  Future<NavigationTrack> startNavigation({
    required String navigatorUserId,
    required String navigationId,
    bool isGroupSecondary = false,
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
        isGroupSecondary: Value(isGroupSecondary),
      ),
    );

    return (await (_db.select(_db.navigationTracks)
          ..where((t) => t.id.equals(id)))
        .getSingle());
  }

  /// סיום ניווט — עדכון isActive=false, endedAt=now
  Future<void> endNavigation(String trackId) async {
    final now = DateTime.now();

    // עדכון ב-Drift
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      isActive: const Value(false),
      endedAt: Value(now),
    ));

    // עדכון ישיר ב-Firestore — set+merge בטוח גם אם המסמך לא קיים (אופליין start)
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .set({
        'isActive': false,
        'endedAt': now.toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Firestore לא זמין — syncTrackToFirestore יטפל בהמשך
    }
  }

  /// המשך ניווט — עדכון isActive=true, endedAt=null (הפוך מ-endNavigation)
  Future<void> resumeNavigation(String trackId) async {
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(const NavigationTracksCompanion(
      isActive: Value(true),
      endedAt: Value(null),
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
  ///
  /// הערה: שדות override (overrideAllowOpenMap, overrideShowSelfLocation, וכו')
  /// לא נשלחים כאן כי הם נכתבים ישירות ל-Firestore ע"י המפקד בלבד.
  /// שליחתם עם ברירת מחדל false דורסת את ברירות המחדל מהגדרות הניווט.
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
        'startedAt': track.startedAt.toUtc().toIso8601String(),
        'endedAt': track.endedAt?.toUtc().toIso8601String(),
        'isActive': track.isActive,
        'isDisqualified': track.isDisqualified,
        'manualPositionUsed': track.manualPositionUsed,
        'manualPositionUsedAt': track.manualPositionUsedAt?.toUtc().toIso8601String(),
        'isGroupSecondary': track.isGroupSecondary,
      },
      priority: SyncPriority.high,
    );
  }

  /// פסילת מנווט — סימון isDisqualified=true ב-Drift + Firestore
  Future<void> disqualifyNavigator(String trackId, {String? reason}) async {
    // עדכון ב-Drift
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(const NavigationTracksCompanion(
      isDisqualified: Value(true),
    ));

    // עדכון ישיר ב-Firestore (כולל סיבת פסילה)
    try {
      final data = <String, dynamic>{'isDisqualified': true};
      if (reason != null) {
        data['disqualificationReason'] = reason;
      }
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update(data);
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

  /// פסילת מנווט לפי navigatorId + navigationId — מוצא track ומסמן כפסול
  Future<void> disqualifyByNavigator(String navigatorId, String navigationId, {String? reason}) async {
    final track = await getByNavigatorAndNavigation(navigatorId, navigationId);
    if (track != null) {
      await disqualifyNavigator(track.id, reason: reason);
    }
  }

  /// עדכון דריסות הגדרות מפה ב-Drift בלבד (לשימוש מנווט — ללא כתיבה ל-Firestore)
  /// מונע מ-_saveTrackPoints לדרוס את ההגדרות שהמפקד שלח
  Future<void> updateMapOverridesLocal(
    String trackId, {
    required bool allowOpenMap,
    required bool showSelfLocation,
    required bool showRouteOnMap,
  }) async {
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideAllowOpenMap: Value(allowOpenMap),
      overrideShowSelfLocation: Value(showSelfLocation),
      overrideShowRouteOnMap: Value(showRouteOnMap),
    ));
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

  /// עדכון דריסת מיקום ידני ב-Drift בלבד (לשימוש מנווט — ללא כתיבה ל-Firestore)
  Future<void> updateManualPositionOverrideLocal(String trackId, {required bool allowManualPosition}) async {
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideAllowManualPosition: Value(allowManualPosition),
    ));
  }

  /// עדכון דריסת הגדרת דקירת מיקום ידני פר-מנווט (Drift + Firestore)
  Future<void> updateManualPositionOverride(String trackId, {required bool allowManualPosition}) async {
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideAllowManualPosition: Value(allowManualPosition),
      manualPositionUsed: const Value(false),
      manualPositionUsedAt: const Value(null),
    ));
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({
        'overrideAllowManualPosition': allowManualPosition,
        'manualPositionUsed': false,
        'manualPositionUsedAt': null,
      });
    } catch (_) {}
  }

  /// עדכון דריסת ווקי טוקי פר-מנווט (Drift + Firestore)
  Future<void> updateWalkieTalkieOverride(String trackId, {required bool enabled}) async {
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideWalkieTalkieEnabled: Value(enabled),
    ));
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({'overrideWalkieTalkieEnabled': enabled});
      print('DEBUG updateWalkieTalkieOverride: SUCCESS trackId=$trackId, enabled=$enabled');
    } catch (e) {
      print('DEBUG updateWalkieTalkieOverride: FAILED trackId=$trackId, enabled=$enabled, error=$e');
    }
  }

  /// עדכון דריסת אמצעי מיקום פר-מנווט (Drift + Firestore)
  Future<void> updatePositionSourcesOverride(String trackId, {required List<String>? enabledSources}) async {
    final json = enabledSources != null ? jsonEncode(enabledSources) : null;
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideEnabledPositionSourcesJson: Value(json),
    ));
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({'overrideEnabledPositionSources': enabledSources});
    } catch (_) {}
  }

  /// עדכון דריסת חשיפת אשכולות פר-מנווט (Drift + Firestore)
  Future<void> updateRevealOverride(String trackId, {required bool? enabled}) async {
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideRevealEnabled: Value(enabled),
    ));
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({'overrideRevealEnabled': enabled});
    } catch (_) {}
  }

  /// עדכון דריסת עוצמות צליל התראה פר-מנווט (Drift + Firestore)
  Future<void> updateAlertSoundVolumesOverride(String trackId, {required Map<String, double>? volumes}) async {
    final json = volumes != null ? jsonEncode(volumes) : null;
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideAlertSoundVolumesJson: Value(json),
    ));
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({'overrideAlertSoundVolumes': volumes});
    } catch (_) {}
  }

  /// עדכון דריסת ווקי טוקי מקומי בלבד (לשימוש מנווט)
  Future<void> updateWalkieTalkieOverrideLocal(String trackId, {required bool enabled}) async {
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      overrideWalkieTalkieEnabled: Value(enabled),
    ));
  }

  /// סימון שנעשה שימוש בדקירת מיקום ידני (Drift + Firestore)
  Future<void> markManualPositionUsed(String trackId) async {
    final now = DateTime.now();
    await (_db.update(_db.navigationTracks)..where((t) => t.id.equals(trackId)))
        .write(NavigationTracksCompanion(
      manualPositionUsed: const Value(true),
      manualPositionUsedAt: Value(now),
    ));
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update({'manualPositionUsed': true, 'manualPositionUsedAt': now.toUtc().toIso8601String()});
    } catch (_) {}
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

    // איפוס ב-Firestore — fire-and-forget (לא חוסם UI)
    FirebaseFirestore.instance
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: navigationId)
        .get()
        .then((snapshot) {
      for (final doc in snapshot.docs) {
        doc.reference.update({
          'endedAt': null,
          'isActive': false,
        });
      }
    }).catchError((_) {
      // Firestore לא זמין — יתוקן בסנכרון הבא
    });
  }

  /// עדכון מצב כוכב — Drift + Firestore (dual write)
  Future<void> updateStarState(
    String trackId, {
    int? pointIndex,
    DateTime? learningEndTime,
    DateTime? navigatingEndTime,
    bool? returnedToCenter,
    DateTime? starStartedAt,
  }) async {
    // עדכון ב-Drift (starStartedAt is Firestore-only, no Drift column)
    final companion = NavigationTracksCompanion(
      starCurrentPointIndex: pointIndex != null ? Value(pointIndex) : const Value.absent(),
      starLearningEndTime: learningEndTime != null ? Value(learningEndTime) : const Value.absent(),
      starNavigatingEndTime: navigatingEndTime != null ? Value(navigatingEndTime) : const Value.absent(),
      starReturnedToCenter: returnedToCenter != null ? Value(returnedToCenter) : const Value.absent(),
    );
    await (_db.update(_db.navigationTracks)
          ..where((t) => t.id.equals(trackId)))
        .write(companion);

    // עדכון ישיר ב-Firestore
    try {
      final data = <String, dynamic>{};
      if (pointIndex != null) data['starCurrentPointIndex'] = pointIndex;
      if (learningEndTime != null) data['starLearningEndTime'] = learningEndTime.toUtc().toIso8601String();
      if (navigatingEndTime != null) data['starNavigatingEndTime'] = navigatingEndTime.toUtc().toIso8601String();
      if (returnedToCenter != null) data['starReturnedToCenter'] = returnedToCenter;
      if (starStartedAt != null) data['starStartedAt'] = Timestamp.fromDate(starStartedAt);
      if (data.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection(AppConstants.navigationTracksCollection)
            .doc(trackId)
            .update(data);
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

  // ===========================================================================
  // Ref-counted Firestore streams
  // ===========================================================================

  /// מאזין לכל ה-tracks של ניווט נתון (ref-counted + polling fallback)
  Stream<List<Map<String, dynamic>>> watchTracksByNavigation(
      String navigationId) {
    final key = 'tracks_$navigationId';
    _tracksStreams[key] ??= RefCountedStream<List<Map<String, dynamic>>>(
      sourceFactory: () => _firestore
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .snapshots()
          .map((snap) =>
              snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()),
      pollFallback: () async {
        final snap = await _firestore
            .collection(AppConstants.navigationTracksCollection)
            .where('navigationId', isEqualTo: navigationId)
            .get();
        return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      },
    );
    return _tracksStreams[key]!.stream;
  }

  /// מאזין ל-track doc ספציפי (לזיהוי שינויים מרחוק — עצירה, override)
  Stream<Map<String, dynamic>?> watchTrackDoc(String trackId) {
    final key = 'track_doc_$trackId';
    _trackDocStreams[key] ??= RefCountedStream<Map<String, dynamic>?>(
      sourceFactory: () => _firestore
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .snapshots()
          .map((snap) =>
              snap.exists ? {'id': snap.id, ...snap.data()!} : null),
      pollFallback: () async {
        final snap = await _firestore
            .collection(AppConstants.navigationTracksCollection)
            .doc(trackId)
            .get();
        return snap.exists ? {'id': snap.id, ...snap.data()!} : null;
      },
    );
    return _trackDocStreams[key]!.stream;
  }

  /// מאזין ל-track של מנווט ספציפי בניווט (לשותף/שומר)
  Stream<Map<String, dynamic>?> watchTrackByNavigator(
    String navigationId,
    String navigatorUserId,
  ) {
    final key = 'track_nav_${navigationId}_$navigatorUserId';
    _trackDocStreams[key] ??= RefCountedStream<Map<String, dynamic>?>(
      sourceFactory: () => _firestore
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .where('navigatorUserId', isEqualTo: navigatorUserId)
          .snapshots()
          .map((snap) => snap.docs.isNotEmpty
              ? {'id': snap.docs.first.id, ...snap.docs.first.data()}
              : null),
      pollFallback: () async {
        final snap = await _firestore
            .collection(AppConstants.navigationTracksCollection)
            .where('navigationId', isEqualTo: navigationId)
            .where('navigatorUserId', isEqualTo: navigatorUserId)
            .get();
        return snap.docs.isNotEmpty
            ? {'id': snap.docs.first.id, ...snap.docs.first.data()}
            : null;
      },
    );
    return _trackDocStreams[key]!.stream;
  }

  /// עצירת מנווט מרחוק (batch write)
  Future<void> stopNavigatorRemote(
    String navigationId,
    String navigatorId,
  ) async {
    final now = DateTime.now();
    final snapshot = await _firestore
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: navigationId)
        .where('navigatorUserId', isEqualTo: navigatorId)
        .where('isActive', isEqualTo: true)
        .get();

    if (snapshot.docs.isEmpty) {
      // Fallback: חפש כל track ללא endedAt
      final allTracks = await _firestore
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .where('navigatorUserId', isEqualTo: navigatorId)
          .get();
      final batch = _firestore.batch();
      final endedDocIds = <String>[];
      for (final doc in allTracks.docs) {
        final trackData = doc.data();
        if (trackData['endedAt'] == null) {
          batch.update(doc.reference, {
            'isActive': false,
            'endedAt': now.toIso8601String(),
          });
          endedDocIds.add(doc.id);
        }
      }
      if (endedDocIds.isNotEmpty) {
        unawaited(batch.commit().catchError((_) {}));
        for (final docId in endedDocIds) {
          try {
            await endNavigation(docId);
          } catch (_) {}
        }
      }
    } else {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isActive': false,
          'endedAt': now.toIso8601String(),
        });
      }
      unawaited(batch.commit().catchError((_) {}));
      for (final doc in snapshot.docs) {
        try {
          await endNavigation(doc.id);
        } catch (_) {}
      }
    }

    // עדכון updatedAt על navigation doc לטריגר UI
    unawaited(_firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .update({'updatedAt': FieldValue.serverTimestamp()})
        .catchError((_) {}));
  }

  /// עצירת כל המנווטים בניווט
  Future<void> stopAllNavigatorsRemote(String navigationId) async {
    final now = DateTime.now();
    final snapshot = await _firestore
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: navigationId)
        .where('isActive', isEqualTo: true)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isActive': false,
          'endedAt': now.toIso8601String(),
        });
      }
      unawaited(batch.commit().catchError((_) {}));
      for (final doc in snapshot.docs) {
        try {
          await endNavigation(doc.id);
        } catch (_) {}
      }
    }
  }

  /// חידוש מנווט שהופסק
  Future<void> resumeNavigatorRemote(
    String navigationId,
    String navigatorId,
  ) async {
    final snapshot = await _firestore
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: navigationId)
        .where('navigatorUserId', isEqualTo: navigatorId)
        .get();

    if (snapshot.docs.isEmpty) return;
    final trackDoc = snapshot.docs.first;

    unawaited(trackDoc.reference.update({
      'isActive': true,
      'endedAt': null,
    }).catchError((_) {}));

    await resumeNavigation(trackDoc.id);
  }

  /// איפוס מנווט (מחיקת track + punches)
  Future<void> resetNavigatorRemote(
    String navigationId,
    String navigatorId,
  ) async {
    final snapshot = await _firestore
        .collection(AppConstants.navigationTracksCollection)
        .where('navigationId', isEqualTo: navigationId)
        .where('navigatorUserId', isEqualTo: navigatorId)
        .get();

    if (snapshot.docs.isNotEmpty) {
      unawaited(
          snapshot.docs.first.reference.delete().catchError((_) {}));
    }

    await deleteByNavigator(navigationId, navigatorId);

    unawaited(_firestore
        .collection(AppConstants.navigationsCollection)
        .doc(navigationId)
        .update({'updatedAt': FieldValue.serverTimestamp()})
        .catchError((_) {}));
  }

  /// כתיבת override per-navigator
  Future<void> setTrackOverride(
    String trackId,
    Map<String, dynamic> overrides,
  ) async {
    try {
      await _firestore
          .collection(AppConstants.navigationTracksCollection)
          .doc(trackId)
          .update(overrides);
    } catch (_) {}
  }

  /// חיפוש track ID ע"פ ניווט ומנווט (Firestore)
  Future<String?> findTrackId(
    String navigationId,
    String navigatorId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.navigationTracksCollection)
          .where('navigationId', isEqualTo: navigationId)
          .where('navigatorUserId', isEqualTo: navigatorId)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
    } catch (_) {
      return null;
    }
  }

  /// ניקוי cache סטטי
  static void clearCache() {
    for (final s in _tracksStreams.values) {
      s.dispose();
    }
    _tracksStreams.clear();
    for (final s in _trackDocStreams.values) {
      s.dispose();
    }
    _trackDocStreams.clear();
  }
}
